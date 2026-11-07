using Core, Pixel

// What an animation recording may hold: an animated picture is meant to be short and light.
const AnimationFramesPerSecond = 15'u64
const AnimationMaxDuration     = 30_000_000'u64     // Microseconds.

// Thickness of the frame drawn around the recorded area, in logical units, and the air between
// the frame and the area: the frame stands outside, so it never appears in the frames.
const RecordFrameWidth = 2.0
const RecordFrameGap   = 1.0

// Where a recording stands.
enum RecorderState
{
    Recording
    Paused
    Stopped       // Ended by the reader or by its limit: the frames become a capture.
    Cancelled     // Abandoned: nothing is kept.
}

// The recording in progress, ended by the command that started it.
var g_Recorder: *Recorder?

// One recording of a screen area into the frame file of a new capture.
//
// The area is grabbed on the interface thread at a fixed rate, while one task at a time writes
// the previous frame to the file. A frame that arrives while the task is still writing is dropped
// and counted, so a slow disk costs frames, never memory.
struct Recorder
{
    late main:   *MainWnd
    area:        Math.Rectangle     // Recorded area, in physical virtual-desktop pixels.
    file:        String             // Capture the frames belong to.
    writer:      Frames.Writer
    state:       RecorderState
    resumedAt:   u64           // Monotonic time the recording last started or resumed.
    recorded:    u64           // Time recorded before the last resume, in microseconds.
    nextFrame:   u64           // Recorded time of the next frame to grab.
    task:        Swag.Task     // Writes `pending` to the file.
    pending:     Image
    pendingTime: u64
    writeFailed: bool     // Set by the task when the file could not be written.
    dropped:     u32      // Frames not recorded because the previous one was still being written.
    hud:         *RecordHud?
    edges:       Array'(*Surface)     // The frame around the area.
}

impl Recorder
{
    // Records `area`, in physical virtual-desktop pixels, until the reader stops, cancels or the
    // limit is reached. Returns the new animation capture, or null when nothing was kept.
    func record(main: *MainWnd, area: Math.Rectangle)->*Capture? fail
    {
        Swag.assert(not g_Recorder)

        // The recorder is reached by the command that stops it, from the frames run below.
        let recorder = Memory.new'Recorder()
        defer Memory.delete(recorder)
        recorder.main   = main
        recorder.area   = area
        recorder.file   = Library.newFileName()
        recorder.writer = try Frames.Writer.create(Capture.mediaPathOf(recorder.file), cast(s32, area.width), cast(s32, area.height), .BGRA8)
        defer #fail discard catch File.delete(Capture.mediaPathOf(recorder.file))

        g_Recorder = recorder
        defer g_Recorder = null

        recorder.showChrome()
        defer recorder.hideChrome()

        recorder.resumedAt = Time.monotonicMicroseconds()
        while recorder.state == .Recording or recorder.state == .Paused
        {
            g_App.runFrame()
            recorder.advance()
        }

        // Land the last frame, then finish the file.
        recorder.task.wait()
        let duration = recorder.elapsed()
        try recorder.writer.close(duration)

        if recorder.writeFailed do
            fail Errors.InvalidFormatError{}
        if recorder.state == .Cancelled or recorder.writer.frameCount() == 0
        {
            discard catch File.delete(Capture.mediaPathOf(recorder.file))
            return null
        }

        with let result = Memory.new'Capture()
        {
            .file = recorder.file
            try .adoptRecording()
            .setScreenSource(g_CaptureWindow.application, g_CaptureWindow.executable, g_CaptureWindow.title, g_CaptureWindow.className)
        }

        return result
    }

    // Returns the time recorded so far, pauses excluded, in microseconds.
    mtd const elapsed()->u64
    {
        if .state != .Recording do
            return .recorded
        return .recorded + (Time.monotonicMicroseconds() - .resumedAt)
    }

    // Suspends the recording; the time spent paused is not recorded.
    mtd pause()
    {
        if .state != .Recording do
            return
        .recorded = .elapsed()
        .state    = .Paused
        .hud?.invalidate()
    }

    // Continues a paused recording.
    mtd resume()
    {
        if .state != .Paused do
            return
        .resumedAt = Time.monotonicMicroseconds()
        .state     = .Recording
        .hud?.invalidate()
    }

    // Ends the recording and keeps it.
    mtd stop()
    {
        if .state != .Recording and .state != .Paused do
            return
        .recorded = .elapsed()
        .state    = .Stopped
    }

    // Ends the recording and keeps nothing.
    mtd cancel()
    {
        .state = .Cancelled
    }

    // Grabs the next frame when its time has come, and ends the recording at its limit.
    private mtd advance()
    {
        .hud?.invalidate()
        if .state != .Recording do
            return

        let time = .elapsed()
        if time >= AnimationMaxDuration
        {
            .recorded = AnimationMaxDuration
            .state    = .Stopped
            return
        }

        if .writeFailed
        {
            .state = .Stopped
            return
        }

        if time < .nextFrame do
            return

        // A frame whose time passed while the interface was busy is not grabbed late.
        let interval = 1_000_000 / AnimationFramesPerSecond
        .nextFrame += interval
        while .nextFrame <= time
        {
            .nextFrame += interval
            .dropped   += 1
        }

        if .task.isPending()
        {
            .dropped += 1
            return
        }

        let x = cast(s32, .area.x)
        let y = cast(s32, .area.y)
        let w = cast(s32, .area.width)
        let h = cast(s32, .area.height)
        .pending = catch getScreenRectImage(.main.captureOptions.captureCursor, x, y, w, h)
        {
            .dropped += 1
            return
        }

        .pendingTime = time
        .task.submit(func|recorder = me|()
        {
            catch recorder.writer.add(recorder.pending, recorder.pendingTime) do
                recorder.writeFailed = true
        })
    }

    // Shows the frame around the area and the recording pill beside it.
    private mtd showChrome()
    {
        // The frame and the pill are native top-most windows of the application, which a
        // headless test host cannot give back to the next test, as for the grab itself.
        #static if #command == Swag.CompilerCommand.Test
        {
            return
        }

        let scale = Env.monitorForPoint({.area.horzCenter(), .area.vertCenter()}).scaleFactor
        let thick = Math.ceil(RecordFrameWidth * scale)
        let gap   = Math.ceil(RecordFrameGap * scale)
        let side  = gap + thick

        let outer = Math.Rectangle{.area.x - side, .area.y - side, .area.width + 2 * side, .area.height + 2 * side}
        .addEdge({outer.x, outer.y, outer.width, thick})
        .addEdge({outer.x, outer.bottom() - thick, outer.width, thick})
        .addEdge({outer.x, outer.y + thick, thick, outer.height - 2 * thick})
        .addEdge({outer.right() - thick, outer.y + thick, thick, outer.height - 2 * thick})

        .hud = RecordHud.open(me, outer, scale)
    }

    // Removes the frame and the pill.
    private mtd hideChrome()
    {
        for edge in .edges do
            edge[].destroy()
        .edges.clear()
        .hud?.surface?.destroy()
        .hud = null
    }

    // Adds one side of the frame, in physical screen pixels.
    private mtd addEdge(rect: Math.Rectangle)
    {
        let surface = catch g_App.createSurface(0, 0, 4, 4, .ToolWindow | .TopMost | .NoShadow)
        {
            return
        }

        with let edge = Wnd.create'RecordEdge(surface.wnd)
        {
            .dockStyle = .Center
        }

        surface.setView(edge)
        surface.setPosition(rect)
        surface.show()
        .edges.add(surface)
    }
}

// One side of the frame drawn around a recorded area, in the colour of something running now.
struct RecordEdge
{
    using wnd: Wnd
}

impl IWnd for RecordEdge
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        evt.paintContext.painter.fillRect(.clientRect(), .themeColors().live)
    }
}
