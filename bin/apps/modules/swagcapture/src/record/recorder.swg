using Core, Pixel, Video

const RecordCountdown          = 3_000_000'u64      // Wait before the first frame when the option asks for it, in microseconds.
const VideoCaptureFramesPerSecond = 30'u32

// Thickness of the frame drawn around the recorded area, in logical units, and the air between
// the frame and the area: the frame stands outside, so it never appears in the frames.
const RecordFrameWidth = 5.0
const RecordFrameGap   = 1.0

// Where a recording stands.
enum RecorderState
{
    Counting     // Waiting for the countdown to end before the first frame.
    Recording
    Paused
    Stopped       // Ended by the reader or by its limit: the frames become a capture.
    Cancelled     // Abandoned: nothing is kept.
    Preparing    // The chosen area is visible on the live desktop, awaiting Record.
}

// The recording in progress, ended by the command that started it.
var g_Recorder: *Recorder?

// One recording of a screen area into the frame file of a new capture.
//
// Video reads the screen on its own thread and hands pictures to a bounded encoder queue;
// animation grabs on the interface thread and uses one writer task at a time. Late slots are
// counted, and held pictures preserve video timing. Both paths bound memory when encoding or
// storage falls behind.
struct Recorder
{
    late main:   *MainWnd
    target:      CaptureTarget
    area:        Math.Rectangle     // Recorded area, in physical virtual-desktop pixels.
    source:      ScreenFrameSource
    storedWidth: s32
    storedHeight: s32
    cadence:     u64           // Microseconds between attempted frames.
    file:        String             // Capture the frames belong to.
    writer:      Frames.Writer
    video:       VideoCaptureSession
    videoProducer: VideoCaptureProducer
    videoAudio:  *VideoRecordingAudio?
    videoMode:   bool
    screenSelection: bool // The preparation bar can choose a monitor or all screens.
    screenIndex: u64      // Selected monitor, or U64.Max for all screens.
    state:       RecorderState
    startsAt:    u64           // Monotonic time the countdown ends.
    clock:       RecordingClock // Session time shared by future video and audio tracks.
    nextFrame:   u64           // Recorded time of the next frame to grab.
    task:        Swag.Task     // Writes `pending` to the file.
    pending:     Image
    pendingTime: u64
    writeFailed: bool     // Set by the task when the file could not be written.
    recordError: Swag.Error // Retains a video or sound failure until the capture command reports it.
    dropped:     u32      // Frames not recorded because the previous one was still being written.
    hud:         *RecordHud?
    limit:       u64      // Longest recording, in microseconds; zero records until stopped.
    ownsEscape:  bool     // Escape is registered as the cancel hotkey of this recording.
    ownsStop:    bool     // Ctrl Shift F10 stops a full-screen recording from any window.
    pausedForTarget: bool // The attached window is temporarily not visible.
    recordRequested: bool // The preparation pill has asked to start the video.
    nextTargetCheck: u64
    edges:       Array'(*Surface)     // The frame around the area.
}

impl Recorder
{
    // Records `area`, in physical virtual-desktop pixels, until the reader stops, cancels or the
    // limit is reached. Returns the new animation capture, or null when nothing was kept.
    func record(main: *MainWnd, area: Math.Rectangle)->*Capture? fail
        => try record(main, CaptureTarget.create(area, 0))

    // Records a fixed area or one attached to a live window.
    func record(main: *MainWnd, target: CaptureTarget)->*Capture? fail
    {
        Swag.assert(not g_Recorder)

        // The recorder is reached by the command that stops it, from the frames run below.
        let recorder = Memory.new'Recorder()
        defer Memory.delete(recorder)
        recorder.main    = main
        recorder.target  = target
        recorder.area    = target.area
        recorder.source  = try ScreenFrameSource.create(main.captureOptions.captureCursor,
                                                         cast(s32, target.area.x), cast(s32, target.area.y),
                                                         cast(s32, target.area.width), cast(s32, target.area.height))
        recorder.file    = Library.newFileName()
        recorder.limit   = cast(u64, Math.clamp(main.captureOptions.recordMaxSeconds, 1, 60)) * 1_000_000
        recorder.cadence = 1_000_000 / main.captureOptions.recordRate.framesPerSecond()

        let maxSide = Math.clamp(main.captureOptions.recordMaxDimension, 320, 3840)
        let scale   = Math.min(1'f32, cast(f32, maxSide) / Math.max(target.area.width, target.area.height))
        recorder.storedWidth  = Math.max(1, cast(s32, target.area.width * scale))
        recorder.storedHeight = Math.max(1, cast(s32, target.area.height * scale))
        recorder.writer = try Frames.Writer.create(Capture.mediaPathOf(recorder.file), recorder.storedWidth, recorder.storedHeight, .BGRA8)
        defer #fail discard catch File.delete(Capture.mediaPathOf(recorder.file))

        g_Recorder = recorder
        defer g_Recorder = null

        recorder.showChrome()
        defer recorder.hideChrome()

        let now = Time.monotonicMicroseconds()
        if main.captureOptions.recordCountdown
        {
            recorder.state    = .Counting
            recorder.startsAt = now + RecordCountdown
        }
        else
        {
            recorder.state = .Recording
            recorder.clock.startAt(now)
        }

        while recorder.state == .Counting or recorder.state == .Recording or recorder.state == .Paused
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

        if recorder.dropped do
            main.confirm(Format.toString(appStrings().ui_DroppedFrames, recorder.dropped))

        return result
    }

    // Records the selected area to an MP4 beside a new editable capture document.
    func recordVideo(main: *MainWnd, target: CaptureTarget, prepare: bool = false,
                     screenSelection = false, screenIndex: u64 = 0)->*Capture? fail
    {
        Swag.assert(not g_Recorder)
        var fileToDiscard: String
        defer
        {
            if not fileToDiscard.isEmpty() do
                discard catch File.delete(fileToDiscard)
        }
        let recorder = Memory.new'Recorder()
        defer Memory.delete(recorder)
        defer
        {
            if recorder.videoAudio
            {
                recorder.videoAudio.close()
                Memory.delete(recorder.videoAudio)
                recorder.videoAudio = null
            }
        }
        recorder.main      = main
        recorder.target    = target
        recorder.area      = target.area
        recorder.videoMode = true
        recorder.screenSelection = screenSelection
        recorder.screenIndex = screenIndex
        recorder.file = Library.newFileName()
        fileToDiscard = Capture.mediaPathOf(recorder.file, .Video)
        recorder.limit = 0

        // H.264 needs even dimensions. The selection stays anchored at its chosen origin.
        recorder.area.width  = Math.floor(recorder.area.width / 2) * 2
        recorder.area.height = Math.floor(recorder.area.height / 2) * 2
        if recorder.area.width < 2 or recorder.area.height < 2 do
            fail Errors.InvalidFormatError{}

        g_Recorder = recorder
        defer g_Recorder = null
        defer recorder.hideChrome()
        defer recorder.videoProducer.close()

        // Only the narrow frame and its controls remain over the live desktop. The reader
        // can use the chosen window and start when it is ready.
        if prepare
        {
            recorder.state = .Preparing
            recorder.showChrome()
            while recorder.state == .Preparing and not recorder.recordRequested do
                g_App.runFrame()
            if recorder.state == .Cancelled do
                return null

            recorder.hud?.surface?.destroy()
            recorder.hud = null
            if recorder.screenSelection do
                recorder.clearEdges()
        }

        let options = &main.captureOptions
        let configs = VideoRecordingAudio.configs(options.recordMicrophone, options.recordSystemSound)
        let rows = cast(u32, (cast(s32, recorder.area.height) + 15) / 16)
        let slices = Math.min(Math.max(Swag.workerCount(), 1'u32), 4'u32, rows)
        recorder.video = try VideoCaptureSession.create(fileToDiscard, recorder.area,
                                                        try FrameRate.create(VideoCaptureFramesPerSecond, 1),
                                                        options.captureCursor, configs.toSlice(), sliceCount: slices)
        try recorder.video.startEncoder()

        if not prepare do
            recorder.showChrome()

        let now = Time.monotonicMicroseconds()
        if options.recordCountdown
        {
            recorder.state    = .Counting
            recorder.startsAt = now + RecordCountdown
        }
        else
        {
            recorder.state = .Recording
            recorder.clock.startAt(now)
        }

        if prepare and not g_App.surfaces.isEmpty()
        {
            let chrome = recorder.chromeGeometry()
            recorder.hud = RecordHud.open(recorder, chrome.outer, chrome.scale)
            if let surface = recorder.hud?.surface do
                excludeCaptureChrome(surface)
            recorder.hideOverlappingVideoHud()
        }

        while recorder.state == .Counting or recorder.state == .Recording or recorder.state == .Paused
        {
            g_App.runFrame()
            recorder.advance()
        }

        recorder.videoProducer.close()
        if recorder.state != .Cancelled and not recorder.video.stoppedForLowStorage() do
            try recorder.videoProducer.raiseError()
        if recorder.videoAudio do
            try recorder.videoAudio.finish()
        if recorder.state == .Cancelled do
            return null
        if recorder.writeFailed
        {
            try recorder.recordError.raise()
            fail Errors.InvalidFormatError{}
        }
        if not recorder.video.frameCount()
        {
            if recorder.video.stoppedForLowStorage() do
                main.confirm(appStrings().msg_VideoStoppedForStorage)
            return null
        }
        try recorder.video.end()
        with let result = Memory.new'Capture()
        {
            .file = String.from(recorder.file)
            try .adoptVideo()
            .setScreenSource(g_CaptureWindow.application, g_CaptureWindow.executable,
                             g_CaptureWindow.title, g_CaptureWindow.className)
        }
        fileToDiscard.clear()
        main.confirmSaved(Capture.mediaPathOf(recorder.file, .Video))
        if recorder.video.stoppedForLowStorage() do
            main.confirm(appStrings().msg_VideoStoppedForStorage)
        if recorder.video.missedFrameSlotCount() do
            main.confirm(Format.toString(appStrings().ui_DroppedFrames,
                                         recorder.video.missedFrameSlotCount()))
        return result
    }

    // Returns the time recorded so far, pauses excluded, in microseconds.
    mtd const elapsed()->u64
        => .clock.elapsedAt(Time.monotonicMicroseconds())

    // Returns the time left before the first frame, in microseconds; zero once the recording runs.
    mtd const countdownLeft()->u64
    {
        if .state != .Counting do
            return 0
        let now = Time.monotonicMicroseconds()
        return .startsAt > now ? .startsAt - now : 0
    }

    // Suspends the recording; the time spent paused is not recorded.
    mtd pause()
    {
        if .videoMode do
            return
        if .state != .Recording do
            return
        .clock.pauseAt(Time.monotonicMicroseconds())
        .state = .Paused
        .hud?.refresh()
    }

    // Continues a paused recording.
    mtd resume()
    {
        if .videoMode do
            return
        if .state != .Paused do
            return
        .clock.resumeAt(Time.monotonicMicroseconds())
        .state = .Recording
        .hud?.refresh()
    }

    // Ends the recording and keeps it.
    mtd stop()
    {
        if .state == .Preparing
        {
            .recordRequested = true
            return
        }

        // Nothing was recorded during the countdown: there is nothing to keep.
        if .state == .Counting
        {
            .state = .Cancelled
            return
        }

        if .state != .Recording and .state != .Paused do
            return
        .clock.pauseAt(Time.monotonicMicroseconds())
        .state = .Stopped
    }

    // Ends the recording and keeps nothing.
    mtd cancel()
    {
        .state = .Cancelled
    }

    // Changes the screen while the live recording is waiting for Record.
    mtd selectScreen(index: u64)
    {
        if .state != .Preparing or not .screenSelection or
           (index != Swag.U64.Max and index >= .main.monitors.count) do
            return

        let bounds = screenBounds(.main, index)
        let width  = Math.floor(bounds.width / 2) * 2
        let height = Math.floor(bounds.height / 2) * 2
        if width < 2 or height < 2 do
            return

        .screenIndex = index
        .area = {bounds.x, bounds.y, width, height}
        .target = CaptureTarget.create(.area, 0)
        .moveChrome()
        .hud?.refreshScreenChoice()
    }

    // The all-screens choice covers the virtual desktop's physical bounding rectangle.
    private func screenBounds(main: *MainWnd, index: u64)->Math.Rectangle
    {
        if index != Swag.U64.Max do
            return main.monitors[index].physicalBounds

        Swag.assert(main.monitors.count > 0)
        var left = Swag.F32.Max
        var top = Swag.F32.Max
        var right = -Swag.F32.Max
        var bottom = -Swag.F32.Max
        for monitor in main.monitors
        {
            let rect = monitor.physicalBounds
            left   = Math.min(left, rect.x)
            top    = Math.min(top, rect.y)
            right  = Math.max(right, rect.right())
            bottom = Math.max(bottom, rect.bottom())
        }
        return {left, top, right - left, bottom - top}
    }

    // Names the selected recording source in the HUD.
    mtd captureLabel()->String
    {
        if .screenSelection
        {
            let index = .screenIndex
            if index == Swag.U64.Max do
                return String.from(appStrings().ui_AimAllScreens)
            return Format.toString(appStrings().ui_AimScreen, index + 1)
        }
        return String.from(captureTargetLabel())
    }

    // Grabs the next frame when its time has come, and ends the recording at its limit.
    private mtd advance()
    {
        .hud?.refresh()
        if .state == .Counting and Time.monotonicMicroseconds() >= .startsAt
        {
            .state = .Recording
            .clock.startAt(Time.monotonicMicroseconds())
        }

        if .target.window and Time.monotonicMicroseconds() >= .nextTargetCheck
        {
            .nextTargetCheck = Time.monotonicMicroseconds() + 50_000
            let resolved = .target.resolve()
            if not resolved.exists
            {
                .stop()
                return
            }
            if not resolved.visible
            {
                if .state == .Recording
                {
                    .pause()
                    .pausedForTarget = true
                    if .videoMode do
                        .videoProducer.setPaused(true)
                }
                return
            }
            if .pausedForTarget
            {
                .pausedForTarget = false
                .resume()
                if .videoMode do
                    .videoProducer.setPaused(false)
            }
            if resolved.area.x != .area.x or resolved.area.y != .area.y
            {
                .area = resolved.area
                if .videoMode
                {
                    if .videoProducer.worker.isValid() do
                        .videoProducer.setPosition(cast(s32, .area.x), cast(s32, .area.y))
                    else
                    {
                        .video.source.x = cast(s32, .area.x)
                        .video.source.y = cast(s32, .area.y)
                    }
                }
                else
                {
                    .source.x = cast(s32, .area.x)
                    .source.y = cast(s32, .area.y)
                }
                .moveChrome()
            }
        }

        if .state != .Recording do
            return

        if .videoMode
        {
            catch .advanceVideo()
            {
                .writeFailed = true
                .recordError.capture(Swag.err)
                .stop()
            }
            return
        }

        let time = .elapsed()
        if .limit and time >= .limit
        {
            .clock.recorded = .limit
            .clock.running  = false
            .state = .Stopped
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
        let interval = .cadence
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

        catch .grabFrame()
        {
            .dropped += 1
            catch .source.reopen()
            return
        }

        .pendingTime = time
        .task.submit(func|recorder = me|()
        {
            if recorder.pending.width != recorder.storedWidth or recorder.pending.height != recorder.storedHeight do
                recorder.pending.resize(recorder.storedWidth, recorder.storedHeight, .Bilinear)
            catch recorder.writer.add(recorder.pending, recorder.pendingTime) do
                recorder.writeFailed = true
        })
    }

    // Reads one video slot and transfers both enabled sound sources into their MP4 tracks.
    private mtd advanceVideo() fail
    {
        if not .videoProducer.worker.isValid()
        {
            try .videoProducer.start(&.video, VideoCaptureFramesPerSecond)
            while not .videoProducer.hasOrigin() and not .videoProducer.hasFailed() do
                Threading.Thread.sleep(1'ms)
        }
        if .videoProducer.hasFailed()
        {
            .stop()
            return
        }
        .dropped = cast(u32, Math.min(.videoProducer.missedFrameSlotCount(), cast(u64, Swag.U32.Max)))
        if not .videoAudio and .videoProducer.hasOrigin() and
           (.main.captureOptions.recordMicrophone or .main.captureOptions.recordSystemSound)
        {
            .videoAudio = Memory.new'VideoRecordingAudio()
            try .videoAudio.start(&.video, .main.captureOptions.recordMicrophone,
                                   .main.captureOptions.recordSystemSound)
        }
        if .videoAudio do
            try .videoAudio.pump()
        .hud?.refresh()
    }

    // Reuses the screen source except when an X11 control overlaps the root area. In that case
    // the control is briefly unmapped for the read; Windows hides it through display affinity.
    private mtd grabFrame() fail
    {
        #static if #os == Swag.TargetOs.Linux
        {
            let chrome = .hud?.surface
            if chrome and chrome.position.intersects(.area)
            {
                .pending = try captureRecordingFrame(.main.captureOptions.captureCursor, .area,
                                                     chrome, .source.x, .source.y,
                                                     .source.width, .source.height)
                return
            }
        }
        try .source.grabInto(&.pending)
    }

    // Returns the frame geometry outside the current area, in physical screen pixels.
    private mtd chromeGeometry()->{outer: Math.Rectangle, thick: f32, scale: f32}
    {
        let scale = Env.monitorForPoint({.area.horzCenter(), .area.vertCenter()}).scaleFactor
        let thick = Math.ceil(RecordFrameWidth * scale)
        if .state == .Preparing and .screenSelection do
            return {.area, thick, scale}
        let gap   = Math.ceil(RecordFrameGap * scale)
        let side  = gap + thick
        return {{.area.x - side, .area.y - side,
                 .area.width + 2 * side, .area.height + 2 * side}, thick, scale}
    }

    // Shows the frame around the area and the recording pill beside it.
    private mtd showChrome()
    {
        // A headless host makes its drawable by hand, outside the application's native surfaces.
        if g_App.surfaces.isEmpty() do
            return

        let {outer, thick, scale} = .chromeGeometry()
        .addEdge({outer.x, outer.y, outer.width, thick})
        .addEdge({outer.x, outer.bottom() - thick, outer.width, thick})
        .addEdge({outer.x, outer.y + thick, thick, outer.height - 2 * thick})
        .addEdge({outer.right() - thick, outer.y + thick, thick, outer.height - 2 * thick})

        .hud = RecordHud.open(me, outer, scale)
        if .state != .Preparing do
            .hideOverlappingVideoHud()
        if let hud = .hud
        {
            if let surface = hud.surface do
                excludeCaptureChrome(surface)
        }

        // The selection overlay is gone. Give keyboard input back to the recorded window;
        // only the border strips and the controls remain above it.
        #static if #os == Swag.TargetOs.Windows
        {
            if .target.window do
                discard Win32.SetForegroundWindow(cast(Win32.HWND, .target.window))
        }

        // Escape abandons the recording from any application, for as long as it runs only.
        catch g_App.registerHotKey(.None, .Escape, ActionCapture.CancelRecording, .main)
        .ownsEscape = true
        if .videoMode
        {
            catch g_App.registerHotKey(.CtrlShift, .F10, ActionCapture.RecordVideo, .main)
            .ownsStop = true
        }
    }

    // Keeps the preparation action visible, then leaves an overlapping X11 control out of
    // the recorded pixels. The tray and Ctrl Shift F10 can stop the video afterwards.
    private mtd hideOverlappingVideoHud()
    {
        #static if #os == Swag.TargetOs.Linux
        {
            if .videoMode and .hud and .hud.surface and .hud.surface.position.intersects(.area)
            {
                .hud.surface.destroy()
                .hud = null
            }
        }
    }

    // Keeps the frame and controls beside an attached area when its window moves.
    private mtd moveChrome()
    {
        if .edges.count != 4 do
            return
        let {outer, thick, scale} = .chromeGeometry()
        let rects = [Math.Rectangle{outer.x, outer.y, outer.width, thick},
                     Math.Rectangle{outer.x, outer.bottom() - thick, outer.width, thick},
                     Math.Rectangle{outer.x, outer.y + thick, thick, outer.height - 2 * thick},
                     Math.Rectangle{outer.right() - thick, outer.y + thick, thick, outer.height - 2 * thick}]
        for edge, index in .edges do
            edge[].setPosition(rects[index])
        .hud?.follow(outer, scale)
    }

    // Removes the frame and the pill.
    private mtd hideChrome()
    {
        if .ownsEscape do
            discard g_App.unregisterHotKey(.None, .Escape)
        .ownsEscape = false
        if .ownsStop do
            discard g_App.unregisterHotKey(.CtrlShift, .F10)
        .ownsStop = false

        .clearEdges()
        .hud?.surface?.destroy()
        .hud = null
    }

    private mtd clearEdges()
    {
        for edge in .edges do
            edge[].destroy()
        .edges.clear()
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

        // A side of the frame is a few pixels thick: no default minimum size may widen it.
        surface.minSize = {}
        surface.setView(edge)
        surface.setPosition(rect)
        surface.show()
        excludeCaptureChrome(surface)
        .edges.add(surface)
    }
}

// One side of the frame drawn around a recorded area, in the colour of a recording.
struct RecordEdge
{
    using wnd: Wnd
}

impl IWnd for RecordEdge
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let rect = .clientRect()
        painter.fillRect(rect, .themeColors().critical)
        painter.drawRect(rect, .themeColors().text, .themeMetrics().separator_HairlineSize)
    }
}
