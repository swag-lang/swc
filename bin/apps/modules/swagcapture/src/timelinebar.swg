using Core, Pixel

// The timeline of a timed capture, on a floating panel under the canvas: play and pause, the time
// at the playhead against the length, and a track the playhead is dragged along. A picture has
// none.
const TimelineHeight    = 40.0      // Logical height of the bar.
const TimelinePadding   = 8.0       // Air inside the bar.
const TimelineButton    = 28.0      // Side of the play command.
const TimelineTextWidth = 104.0     // Room for the time reading.
const TimelineGap       = 8.0       // Air between the bar and the hint line.
const TimelineThumbnails = 6        // Fixed decoding budget for the visible passage.

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
    dragFromStart:   u64     // Selected form's span when its end is dragged.
    dragFromEnd:     u64
    viewStart:       u64     // First time visible on the track.
    zoom:            f32 = 1 // One shows the whole recording.
    viewCapture:     *Capture?
    thumbReader:     *Frames.Reader?
    thumbTextures:   [TimelineThumbnails] Texture
    thumbStart:      u64
    thumbSpan:       u64
    thumbsReady:     bool
}

// What a press on the track drags.
enum TimelineEdge
{
    None      // The playhead.
    Start     // The start of the kept part.
    End       // The end of the kept part.
    FormStart // The selected form's first visible time.
    FormEnd   // The selected form's end.
}

// Distance at which a press takes an end of the kept part rather than the playhead.
const TimelineEdgeReach = 6.0

impl IWnd for TimelineBar
{
    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .clearThumbnails()
    }

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
        if .zoom > 1 do
            .prepareThumbnails(capture)
        for texture, slot in .thumbTextures where .zoom > 1 and texture.isValid()
        {
            let width = track.width / TimelineThumbnails
            painter.drawTexture({track.x + slot * width + 2, track.y + 2,
                                 Math.max(width - 4, 1), 12}, texture)
            painter.fillRect({track.x + (slot + 0.5) * width, track.vertCenter() - 4, 1, 8}, colors.faintText)
        }
        let played = .trackX(time)
        let keepL  = .trackX(capture.trimStart())
        let keepR  = .trackX(capture.trimEnd())
        painter.fillRoundRect({track.x, track.vertCenter() - 2, track.width, 4}, 2, 2, colors.raised)
        let shownLeft  = Math.max(keepL, track.x)
        let shownRight = Math.min(Math.min(played, keepR), track.right())
        if shownRight > shownLeft do
            painter.fillRoundRect({shownLeft, track.vertCenter() - 2, shownRight - shownLeft, 4}, 2, 2, colors.arc)
        if capture.isTrimmed()
        {
            if keepL >= track.x and keepL <= track.right()
            {
                painter.fillRect({keepL - 1, track.y + 9, 2, track.height - 18}, colors.arc)
                painter.fillRect({keepL - 1, track.y + 9, 5, 2}, colors.arc)
                painter.fillRect({keepL - 1, track.bottom() - 11, 5, 2}, colors.arc)
            }
            if keepR >= track.x and keepR <= track.right()
            {
                painter.fillRect({keepR - 1, track.y + 9, 2, track.height - 18}, colors.arc)
                painter.fillRect({keepR - 4, track.y + 9, 5, 2}, colors.arc)
                painter.fillRect({keepR - 4, track.bottom() - 11, 5, 2}, colors.arc)
            }
        }

        if played >= track.x and played <= track.right() do
            painter.fillRoundRect({played - 1.5, track.y + 6, 3, track.height - 12}, 1.5, 1.5, colors.text)

        // The time span of the first selected form, under the track.
        if not capture.selection.isEmpty()
        {
            let form: *BaseForm = capture.forms[capture.selection[0]]
            let finish = form.timeEnd ? form.timeEnd : frames.endTime
            let left   = Math.max(.trackX(form.timeStart), track.x)
            let right  = Math.min(.trackX(finish), track.right())
            if right > left
            {
                painter.fillRoundRect({left, track.vertCenter() + 7, Math.max(right - left, 3), 3}, 1.5, 1.5, colors.arc)
                if left > track.x do
                    painter.fillRect({left - 1, track.vertCenter() + 4, 2, 9}, colors.arc)
                if right < track.right() do
                    painter.fillRect({right - 1, track.vertCenter() + 4, 2, 9}, colors.arc)
            }
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let position = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Wheel where .trackRect().contains(position):
            if evt.modifiers & .Shift
            {
                .pan(evt.delta.y > 0 ? -0.2 : 0.2)
            }
            else
            {
                .zoomAt(position.x, evt.delta.y > 0 ? 1.5 : 1.0 / 1.5)
            }

        case .Pressed where evt.button == .Left and .trackRect().contains(position):
            .isDragging = true
            .dragEdge   = .edgeAt(position.x, position.y)
            if let capture = .capture()
            {
                .dragFromIn  = capture.timeline.inPoint
                .dragFromOut = capture.timeline.outPoint
                if capture.selection.count == 1
                {
                    let form: *BaseForm = capture.forms[capture.selection[0]]
                    .dragFromStart = form.timeStart
                    .dragFromEnd   = form.timeEnd
                }
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
            .revealTime(frames.timeOf(frame))
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
    mtd capture()->*Capture?
    {
        let current = .main.getCapture()
        if current != .viewCapture
        {
            .clearThumbnails()
            .viewCapture = current
            .viewStart   = 0
            .zoom        = 1
        }
        return current
    }

    // Disposes the six visible thumbnails and their independent decoder.
    private mtd clearThumbnails()
    {
        for &texture in .thumbTextures
        {
            if texture[].isValid() do
                .app().renderer.removeTexture(texture)
        }
        if .thumbReader do
            Memory.delete(.thumbReader)
        .thumbReader = null
        .thumbsReady = false
    }

    // Decodes only six points in the current visible time range. The separate reader does not
    // disturb the canvas playhead, and cached textures survive paints until the range changes.
    private mtd prepareThumbnails(capture: *Capture)
    {
        let span = .visibleDuration()
        if .thumbsReady and .thumbStart == .viewStart and .thumbSpan == span do
            return
        if not .thumbReader
        {
            let reader = catch Frames.Reader.open(Capture.mediaPathOf(capture.file)) { return; }
            .thumbReader = Memory.new'Frames.Reader()
            .thumbReader[] = #move reader
        }
        for &texture in .thumbTextures
        {
            if texture[].isValid() do
                .app().renderer.removeTexture(texture)
        }
        let frames = .thumbReader
        for slot in TimelineThumbnails
        {
            let at = .viewStart + span * (2 * slot + 1) / (2 * TimelineThumbnails)
            let frame = frames.frameAt(Math.min(at, capture.timeline.duration - 1))
            let picture = catch frames.read(frame) { continue; }
            let image = picture[].resized(48, 12, .Bilinear)
            .thumbTextures[slot] = .app().renderer.addImage(image)
        }
        .thumbStart = .viewStart
        .thumbSpan = span
        .thumbsReady = true
    }

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

    // Returns the duration visible on the track, in microseconds.
    mtd visibleDuration()->u64
    {
        let capture = unwrap .capture()
        return Math.max(cast(u64, cast(f64, capture.timeline.duration) / .zoom), 1'u64)
    }

    // Returns where `time`, in microseconds, lies on the track, in local coordinates.
    mtd trackX(time: u64)->f32
    {
        let track   = .trackRect()
        let offset  = cast(f64, time) - cast(f64, .viewStart)
        return track.x + track.width * cast(f32, offset / cast(f64, .visibleDuration()))
    }

    // Returns the time at `x`, in local coordinates on the track, in microseconds.
    mtd timeAt(x: f32)->u64
    {
        let track   = .trackRect()
        let ratio   = Math.clamp((x - track.x) / Math.max(track.width, 1), 0, 1)
        return .viewStart + cast(u64, cast(f64, ratio) * cast(f64, .visibleDuration()))
    }

    // Zooms around the time under `x`, keeping that time under the pointer.
    mtd zoomAt(x, factor: f32)
    {
        let capture = .capture()
        if not capture or not capture.frames do
            return
        let anchor = .timeAt(x)
        let track  = .trackRect()
        let ratio  = Math.clamp((x - track.x) / Math.max(track.width, 1), 0, 1)
        .zoom = Math.clamp(.zoom * factor, 1, 1024)
        let span  = .visibleDuration()
        let shift = cast(u64, cast(f64, ratio) * cast(f64, span))
        .viewStart = anchor > shift ? anchor - shift : 0
        .viewStart = Math.min(.viewStart, capture.timeline.duration - span)
        .invalidate()
    }

    // Moves the visible range by a fraction of its duration.
    mtd pan(fraction: f32)
    {
        let capture = .capture()
        if not capture or not capture.frames do
            return
        let span   = .visibleDuration()
        let change = cast(s64, cast(f64, span) * fraction)
        .viewStart = cast(u64, Math.clamp(cast(s64, .viewStart) + change,
                                          0, cast(s64, capture.timeline.duration - span)))
        .invalidate()
    }

    // Follows playback only after the playhead leaves the visible range.
    mtd revealTime(time: u64)
    {
        let capture = .capture()
        if not capture or .zoom <= 1 do
            return
        let span = .visibleDuration()
        if time < .viewStart or time > .viewStart + span
        {
            .viewStart = Math.min(time > span / 2 ? time - span / 2 : 0,
                                  capture.timeline.duration - span)
        }
    }

    // Returns the end of the kept part a press at `x` takes, or none for the playhead.
    mtd edgeAt(x, y: f32)->TimelineEdge
    {
        let capture = unwrap .capture()
        let track = .trackRect()
        if capture.selection.count == 1 and y >= track.vertCenter() + 4
        {
            let form: *BaseForm = capture.forms[capture.selection[0]]
            let finish = form.timeEnd ? form.timeEnd : capture.timeline.duration
            let left   = .trackX(form.timeStart)
            let right  = .trackX(finish)
            if left >= track.x and left <= track.right() and Math.abs(x - left) <= TimelineEdgeReach do
                return .FormStart
            if right >= track.x and right <= track.right() and Math.abs(x - right) <= TimelineEdgeReach do
                return .FormEnd
        }
        if Math.abs(x - .trackX(capture.trimStart())) <= TimelineEdgeReach and
           .trackX(capture.trimStart()) >= track.x and .trackX(capture.trimStart()) <= track.right() do
            return .Start
        if Math.abs(x - .trackX(capture.trimEnd())) <= TimelineEdgeReach and
           .trackX(capture.trimEnd()) >= track.x and .trackX(capture.trimEnd()) <= track.right() do
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

        case .FormStart:
            let form: *BaseForm = capture.forms[capture.selection[0]]
            let finish = form.timeEnd ? form.timeEnd : capture.timeline.duration
            form.timeStart = Math.min(.timeAt(x), finish - 1)

        case .FormEnd:
            let form: *BaseForm = capture.forms[capture.selection[0]]
            let finish = Math.max(.timeAt(x), form.timeStart + 1)
            form.timeEnd = finish >= capture.timeline.duration ? 0 : finish
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

        if edge == .FormStart or edge == .FormEnd
        {
            if capture.selection.count != 1 do
                return
            let form: *BaseForm = capture.forms[capture.selection[0]]
            let chosen = edge == .FormStart ? form.timeStart : form.timeEnd
            let old    = edge == .FormStart ? .dragFromStart : .dragFromEnd
            if chosen == old do
                return
            form.timeStart = .dragFromStart
            form.timeEnd   = .dragFromEnd
            capture.setSelectionSpanAt(edge == .FormStart, chosen ? chosen : capture.timeline.duration)
            .invalidate()
            return
        }

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
        let frame  = frames.frameAt(.timeAt(x))
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
        var textWidth = TimelineTextWidth
        let capture = .capture()
        if capture and capture.frames
        {
            let duration = capture.timeline.duration
            var longest  = Capture.clockText(duration, tenths: true)
            longest += " / "
            longest += Capture.clockText(duration)
            let font     = .theme().createDefaultFontFs(.themeMetrics().defaultFontSize - 1)
            textWidth = Math.max(textWidth, Painter.measureString(longest, font).width + TimelinePadding)
        }
        let left = TimelinePadding + TimelineButton + TimelinePadding + textWidth
        return {left, client.y, Math.max(client.width - left - TimelinePadding - 6, 0), client.height}
    }
}
