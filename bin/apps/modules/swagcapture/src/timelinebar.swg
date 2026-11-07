using Core, Pixel

// The timeline of a timed capture, on a floating panel under the canvas: play and pause, the time
// at the playhead against the length, and a track the playhead is dragged along. A picture has
// none.
const TimelineHeight    = 40.0      // Logical height of the bar.
const TimelinePadding   = 8.0       // Air inside the bar.
const TimelineButton    = 28.0      // Side of the play command.
const TimelineTextWidth = 104.0     // Room for the time reading.
const TimelineGap       = 8.0       // Air between the bar and the hint line.

struct TimelineBar
{
    using wnd: Wnd

    late main:       *MainWnd
    late panel:      *FloatingPanel     // The floating ground the bar stands on, placed by the main window.
    late playButton: *IconButton
    playTimer:       *Gui.Timer?
    playStart:       u64     // Monotonic time playback started, in microseconds.
    playFrom:        u64     // Capture time playback started from, in microseconds.
    isDragging:      bool
    dragEdge:        TimelineEdge     // The end of the kept part being dragged, if any.
    dragFromIn:      u64     // Kept part when the drag of an end started, restored for its undo.
    dragFromOut:     u64
}

// What a press on the track drags.
enum TimelineEdge
{
    None      // The playhead.
    Start     // The start of the kept part.
    End       // The end of the kept part.
}

// Distance at which a press takes an end of the kept part rather than the playhead.
const TimelineEdgeReach = 6.0

impl IWnd for TimelineBar
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let capture = .capture()
        if not capture or not capture.frames do
            return

        let painter = evt.paintContext.painter
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let client  = .clientRect()
        painter.setParams(.Antialiased)

        // The time at the playhead, with tenths, against the length of the capture.
        let frames = capture.frames
        let time   = frames.timeOf(capture.playhead)
        var text   = Capture.clockText(time, tenths: true)
        text += " / "
        text += Capture.clockText(frames.endTime)
        let font  = .theme().createDefaultFontFs(metrics.defaultFontSize - 1)
        let textX = TimelinePadding + TimelineButton + TimelinePadding
        painter.drawString(textX, font.opticalLineTop(client.vertCenter()), text, font, colors.softText)

        // The track, the part already played in Arc, and the playhead. The parts trimmed away keep
        // the ground of the track and lose the Arc; brackets mark the kept part.
        let track  = .trackRect()
        let played = .trackX(time)
        let keepL  = .trackX(capture.trimStart())
        let keepR  = .trackX(capture.trimEnd())
        painter.fillRoundRect({track.x, track.vertCenter() - 2, track.width, 4}, 2, 2, colors.raised)
        if played > keepL do
            painter.fillRoundRect({keepL, track.vertCenter() - 2, Math.min(played, keepR) - keepL, 4}, 2, 2, colors.arc)
        if capture.isTrimmed()
        {
            painter.fillRect({keepL - 1, track.y + 9, 2, track.height - 18}, colors.arc)
            painter.fillRect({keepL - 1, track.y + 9, 5, 2}, colors.arc)
            painter.fillRect({keepL - 1, track.bottom() - 11, 5, 2}, colors.arc)
            painter.fillRect({keepR - 1, track.y + 9, 2, track.height - 18}, colors.arc)
            painter.fillRect({keepR - 4, track.y + 9, 5, 2}, colors.arc)
            painter.fillRect({keepR - 4, track.bottom() - 11, 5, 2}, colors.arc)
        }

        painter.fillRoundRect({played - 1.5, track.y + 6, 3, track.height - 12}, 1.5, 1.5, colors.text)

        // The time span of the first selected form, under the track.
        if not capture.selection.isEmpty()
        {
            let form: *BaseForm = capture.forms[capture.selection[0]]
            let span   = Math.max(frames.endTime, 1'u64)
            let finish = form.timeEnd ? form.timeEnd : frames.endTime
            let left   = track.x + track.width * cast(f32, form.timeStart) / cast(f32, span)
            let right  = track.x + track.width * cast(f32, finish) / cast(f32, span)
            painter.fillRoundRect({left, track.vertCenter() + 7, Math.max(right - left, 3), 3}, 1.5, 1.5, colors.arc)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let position = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Pressed where evt.button == .Left and .trackRect().contains(position):
            .isDragging = true
            .dragEdge   = .edgeAt(position.x)
            if let capture = .capture()
            {
                .dragFromIn  = capture.timeline.inPoint
                .dragFromOut = capture.timeline.outPoint
            }

            .captureMouse()
            .drag(position.x)

        case .Move where .isDragging:
            .drag(position.x)

        case .Released where .isDragging:
            .isDragging = false
            .releaseMouse()
            .endEdgeDrag()
        }
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .playTimer do
            return

        let capture = .capture()
        if not capture or not capture.frames
        {
            .stop()
            return
        }

        // Playback loops over the kept part, as the exported animation does.
        let frames = capture.frames
        var time   = .playFrom + (Time.monotonicMicroseconds() - .playStart)
        if time >= capture.trimEnd() or time < capture.trimStart()
        {
            .playFrom  = capture.trimStart()
            .playStart = Time.monotonicMicroseconds()
            time       = .playFrom
        }

        let frame = frames.frameAt(time)
        if frame != capture.playhead
        {
            catch capture.showFrame(frame)
            .invalidate()
        }
    }
}

impl TimelineBar
{
    func create(main: *MainWnd, parent: *Wnd)->*TimelineBar
    {
        with let panel = FloatingPanel.create(parent)
        {
            .padding = {}
        }

        with let result = Wnd.create'TimelineBar(panel)
        {
            .main            = main
            .panel           = panel
            .backgroundStyle = .Transparent
            .dockStyle       = .Center
        }

        with result.playButton = IconButton.create(result, result.theme().icon(.Play), {TimelinePadding, (TimelineHeight - TimelineButton) * 0.5, TimelineButton, TimelineButton}, flags: .Flat)
        {
            .toolTip    = appStrings().tip_PlayAnimation
            .sigPressed += func|bar = result|(_) { bar.togglePlay() }
        }

        return result
    }

    // Returns the capture the bar shows the time of.
    mtd capture()->*Capture? => .main.getCapture()

    // Returns whether the animation is playing.
    mtd const isPlaying()->bool => .playTimer != null

    // Plays the animation from the playhead, or stops it.
    mtd togglePlay()
    {
        if .isPlaying()
        {
            .stop()
            return
        }

        let capture = .capture()
        if not capture or not capture.frames do
            return

        .playFrom  = capture.frames.timeOf(capture.playhead)
        .playStart = Time.monotonicMicroseconds()
        .playTimer = .addTimer(Time.Duration.fromSeconds(1.0 / 60))
        .playButton.setIcon(.theme().icon(.Pause))
        .playButton.toolTip = appStrings().tip_PauseAnimation
    }

    // Stops playback, leaving the playhead where it is.
    mtd stop()
    {
        .stopTimer(&.playTimer)
        .playButton.setIcon(.theme().icon(.Play))
        .playButton.toolTip = appStrings().tip_PlayAnimation
    }

    // Returns where `time`, in microseconds, lies on the track, in local coordinates.
    mtd trackX(time: u64)->f32
    {
        let capture = unwrap .capture()
        let track   = .trackRect()
        let length  = Math.max(capture.timeline.duration, 1'u64)
        return track.x + track.width * cast(f32, Math.min(time, length)) / cast(f32, length)
    }

    // Returns the time at `x`, in local coordinates on the track, in microseconds.
    mtd timeAt(x: f32)->u64
    {
        let capture = unwrap .capture()
        let track   = .trackRect()
        let ratio   = Math.clamp((x - track.x) / Math.max(track.width, 1), 0, 1)
        return cast(u64, ratio * cast(f32, capture.timeline.duration))
    }

    // Returns the end of the kept part a press at `x` takes, or none for the playhead.
    mtd edgeAt(x: f32)->TimelineEdge
    {
        let capture = unwrap .capture()
        if Math.abs(x - .trackX(capture.trimStart())) <= TimelineEdgeReach do
            return .Start
        if Math.abs(x - .trackX(capture.trimEnd())) <= TimelineEdgeReach do
            return .End
        return .None
    }

    // Follows a drag on the track at `x`: an end of the kept part, or the playhead.
    mtd drag(x: f32)
    {
        let capture = .capture()
        if not capture or not capture.frames do
            return

        // The ends follow the pointer without leaving an undo step at each move; the release
        // makes the whole drag one step.
        switch .dragEdge
        {
        case .None:
            .seek(x)
            return

        case .Start:
            capture.timeline.inPoint = Math.min(.timeAt(x), capture.trimEnd())

        case .End:
            let finish = Math.max(.timeAt(x), capture.trimStart() + 1)
            capture.timeline.outPoint = finish >= capture.timeline.duration ? 0 : finish
        }

        .invalidate()
    }

    // Ends the drag of an end of the kept part as one undoable edit.
    mtd endEdgeDrag()
    {
        let edge = .dragEdge
        .dragEdge = .None
        let capture = .capture()
        if edge == .None or not capture do
            return

        let keptIn  = capture.timeline.inPoint
        let keptOut = capture.timeline.outPoint
        capture.timeline.inPoint  = .dragFromIn
        capture.timeline.outPoint = .dragFromOut
        capture.setTrim(keptIn, keptOut)
        .invalidate()
    }

    // Moves the playhead to the frame shown at `x`, in local coordinates on the track.
    mtd seek(x: f32)
    {
        let capture = .capture()
        if not capture or not capture.frames do
            return

        let frames = capture.frames
        let track  = .trackRect()
        let ratio  = Math.clamp((x - track.x) / Math.max(track.width, 1), 0, 1)
        let frame  = frames.frameAt(cast(u64, ratio * cast(f32, frames.endTime)))
        catch capture.showFrame(frame)
        if .isPlaying()
        {
            .playFrom  = frames.timeOf(frame)
            .playStart = Time.monotonicMicroseconds()
        }

        .invalidate()
    }

    // Returns where the track lies, in local coordinates.
    mtd trackRect()->Math.Rectangle
    {
        let client = .clientRect()
        let left   = TimelinePadding + TimelineButton + TimelinePadding + TimelineTextWidth
        return {left, client.y, Math.max(client.width - left - TimelinePadding - 6, 0), client.height}
    }
}
