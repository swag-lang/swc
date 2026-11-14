using Core, Pixel, Audio, Video

// The timeline of a timed capture, on a floating panel under the canvas: play and pause, the time
// at the playhead against the length, and a track the playhead is dragged along. A picture has
// none.
const TimelineHeight    = 40.0      // Logical height of the bar.
const TimelinePadding   = 8.0       // Air inside the bar.
const TimelineButton    = 28.0      // Side of the play command.
const TimelineTextWidth = 104.0     // Room for the time reading.
const TimelineGap       = 8.0       // Air between the bar and the hint line.
const TimelineThumbnails = 6        // Fixed decoding budget for the visible passage.
const TimelineVideoSlots = 5         // Five 4K YUV420 pictures stay below 64 MiB.

struct TimelineVideoSlot
{
    index:  u64
    planes: PlanarFrame
}

struct TimelineBar
{
    using wnd: Wnd

    late main:       *MainWnd
    late panel:      *FloatingPanel     // The floating ground the bar stands on, placed by the main window.
    late playButton: *IconButton
    playTimer:       *Gui.Timer?
    seekTimer:       *Gui.Timer?
    playStart:       u64     // Monotonic time playback started, in microseconds.
    playFrom:        u64     // Capture time playback started from, in microseconds.
    audioReader:     *Video.Reader?
    audioVoices:     [2] (*Voice?)
    audioVoiceCount: u32
    audioPath:       String
    ownsAudioEngine: bool
    audioClockLast:   f64 = -1
    isDragging:      bool
    dragEdge:        TimelineEdge     // The selected form edge being dragged, if any.
    dragFromStart:   u64     // Selected form's span when its end is dragged.
    dragFromEnd:     u64
    viewStart:       u64     // First time visible on the track.
    zoom:            f32 = 1 // One shows the whole recording.
    viewCapture:     *Capture?
    thumbReader:     *TimedReader?
    thumbTextures:   [TimelineThumbnails] Texture
    thumbStart:      u64
    thumbSpan:       u64
    thumbsReady:     bool
    videoSlots:      [TimelineVideoSlots] TimelineVideoSlot
    videoReady:      StaticArray'(u32, TimelineVideoSlots)
    videoFree:       StaticArray'(u32, TimelineVideoSlots)
    videoLock:       Swag.Mutex
    videoWake:       Sync.Event
    videoReleased:   Sync.Event
    videoTask:       Swag.Task
    videoExecutor:   Swag.Executor
    videoPath:       String
    videoGeneration: u32
    videoFrom:       u64
    videoNext:       u64
    videoCount:      u64
    videoActive:     bool
    videoFailed:     bool
    videoBusy:       bool
    videoBusySlot:   u32
    videoReleaseRequested: bool
}

// What a press on the track drags.
enum TimelineEdge
{
    None      // The playhead.
    FormStart // The selected form's first visible time.
    FormEnd   // The selected form's end.
}

// Distance at which a press takes a selected form edge rather than the playhead.
const TimelineEdgeReach = 6.0

impl IWnd for TimelineBar
{
    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .stopTimer(&.seekTimer)
        if .videoTask.isPending()
        {
            .videoTask.cancel()
            .videoWake.signal()
            .videoTask.wait()
            .videoExecutor.close()
            .videoWake.release()
            .videoReleased.release()
        }
        .disposeAudio()
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

        // The kept part sits on a compact rail. Its bounds mark the trim, while the playhead
        // shows progress through it; the recording outside it stays visibly muted.
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
        let railHeight = track.height * 0.15
        let railRadius = railHeight * 0.5
        let railY      = track.y + track.height * 0.5
        painter.fillRoundRect({track.x, railY - railRadius, track.width, railHeight}, railRadius, railRadius, colors.raised)
        let shownLeft  = Math.max(keepL, track.x)
        let shownRight = Math.min(Math.min(played, keepR), track.right())
        if shownRight > shownLeft do
            painter.fillRoundRect({shownLeft, railY - railRadius, shownRight - shownLeft, railHeight}, railRadius, railRadius, colors.arc)
        if capture.isTrimmed()
        {
            let shade      = colors.disabled.withAlpha(72)
            let beforeEnd  = Math.clamp(keepL, track.x, track.right())
            let afterStart = Math.clamp(keepR, track.x, track.right())
            if beforeEnd > track.x do
                painter.fillRoundRect({track.x, railY - railRadius, beforeEnd - track.x, railHeight}, railRadius, railRadius, shade)
            if afterStart < track.right() do
                painter.fillRoundRect({afterStart, railY - railRadius, track.right() - afterStart, railHeight}, railRadius, railRadius, shade)
        }

        for bound in [keepL, keepR] where bound >= track.x and bound <= track.right()
        {
            let boundWidth = railHeight / 3
            painter.fillRoundRect({bound - boundWidth * 0.5, railY - railHeight, boundWidth, railHeight * 2},
                                  boundWidth * 0.5, boundWidth * 0.5, colors.arc)
        }
        if played >= track.x and played <= track.right()
        {
            let playheadWidth = railHeight / 3
            painter.fillRoundRect({played - playheadWidth * 0.5, track.y + track.height * 0.15,
                                   playheadWidth, track.height * 0.5}, playheadWidth * 0.5,
                                  playheadWidth * 0.5, colors.text)
        }

        // A selected form gets its own centered lane: a soft Arc segment with a fine Arc edge,
        // distinct from the filled playback rail above it.
        if not capture.selection.isEmpty()
        {
            let form: *BaseForm = capture.forms[capture.selection[0]]
            let finish = form.timeEnd ? form.timeEnd : frames.endTime
            let left   = Math.max(.trackX(form.timeStart), track.x)
            let right  = Math.min(.trackX(finish), track.right())
            if right > left
            {
                let laneY      = track.y + track.height * 0.8
                let laneHeight = track.height * 0.05
                let spanHeight = track.height * 0.2
                let spanWidth  = Math.min(Math.max(right - left, spanHeight), track.width)
                let spanLeft   = Math.clamp((left + right - spanWidth) * 0.5, track.x, track.right() - spanWidth)
                let lane: Math.Rectangle = {x: track.x, y: laneY - laneHeight * 0.5,
                                            width: track.width, height: laneHeight}
                let span: Math.Rectangle = {x: spanLeft, y: laneY - spanHeight * 0.5,
                                            width: spanWidth, height: spanHeight}
                painter.fillRoundRect(lane, laneHeight * 0.5, laneHeight * 0.5, colors.raised)
                painter.fillRoundRect(span, spanHeight * 0.5, spanHeight * 0.5, colors.selection)
                painter.drawRoundRect(span, spanHeight * 0.5, spanHeight * 0.5, colors.arc, metrics.separator_HairlineSize)
            }
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let position = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Pressed where evt.button == .Right:
            .showActions(evt.surfacePos)
            evt.accepted = true

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
        if evt.timer == .seekTimer
        {
            let capture = .capture()
            if not capture or not capture.frames or .videoDecodeFailed()
            {
                .stopTimer(&.seekTimer)
                return
            }
            if .presentVideoFrame(capture, .videoFrom)
            {
                .stopTimer(&.seekTimer)
                .revealTime(capture.frames.timeOf(capture.playhead))
                .invalidate()
            }
            return
        }
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
        if capture.media == .Video and not Swag.jit()
        {
            if .videoDecodeFailed()
            {
                .stop()
                .main.reportFailure(appStrings().msg_RecordingPlaybackFailed, Capture.clockText(.playFrom, tenths: true))
                return
            }
            if not .playStart
            {
                if not .videoBuffered() do
                    return
                catch .startAudio(.playFrom)
                .playStart = Time.monotonicMicroseconds()
            }
        }

        let now = Time.monotonicMicroseconds()
        var time = .playFrom + (now - .playStart)
        if .audioVoiceCount and .audioVoices[0] and .audioReader
        {
            let sound = unwrap .audioReader.audioTrack(0)
            let voice = unwrap .audioVoices[0]
            let seconds = sound.timelineStartSeconds() + voice.playbackPositionSeconds()
            // An ended or stalled audio cursor cannot stop the video clock. Only a new,
            // audible position corrects drift; the monotonic clock advances between buffers.
            if seconds >= 0 and seconds != .audioClockLast and
               voice.playbackSampleFrame() < sound.sampleFrameCount()
            {
                .audioClockLast = seconds
                let audioTime = cast(u64, seconds * 1_000_000)
                if Math.abs(cast(f64, audioTime) - cast(f64, time)) > 80_000
                {
                    .playFrom = audioTime
                    .playStart = now
                    time = audioTime
                }
            }
        }

        if time >= capture.trimEnd() or time < capture.trimStart()
        {
            .playFrom  = capture.trimStart()
            time       = .playFrom
            if capture.media == .Video and not Swag.jit()
            {
                .stopAudio()
                .requestVideoFrames(capture, frames.frameAt(time))
                .playStart = 0
                return
            }
            catch .startAudio(time)
            .playStart = Time.monotonicMicroseconds()
        }

        let frame = frames.frameAt(time)
        if capture.media == .Video and not Swag.jit()
        {
            if .presentVideoFrame(capture, frame)
            {
                .revealTime(frames.timeOf(capture.playhead))
                .invalidate()
            }
            return
        }
        if frame != capture.playhead
        {
            catch capture.showPlaybackFrame(frame)
            {
                .stop()
                .main.reportFailure(appStrings().msg_RecordingPlaybackFailed, Capture.clockText(time, tenths: true))
                return
            }
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
            .toolTip         = appStrings().tip_TimelineContext
        }

        with result.playButton = IconButton.create(result, result.theme().icon(.Play), {TimelinePadding, (TimelineHeight - TimelineButton) * 0.5, TimelineButton, TimelineButton}, flags: .Flat)
        {
            .toolTip    = appStrings().tip_PlayAnimation
            .sigPressed += func|bar = result|(_) { bar.togglePlay() }
        }

        if not Swag.jit()
        {
            result.videoWake.init()
            result.videoReleased.init()
            result.videoExecutor.start()
            result.videoTask.submit(func|bar = result|() { runTimelineVideoDecoder(bar) },
                                    result.taskNotifier(&result.videoTask), executor: &result.videoExecutor)
        }

        return result
    }

    // Opens the timeline commands at the pointer that requested its context menu.
    mtd showActions(surfacePos: Math.Point)
    {
        let main = .main
        with let menu = MenuCtrl.createPopup(main, owner: main)
        {
            .addItem(ActionTimeline.Play)
            .addItem(ActionTimeline.PrevFrame)
            .addItem(ActionTimeline.NextFrame)
            .addSeparator()
            .addItem(ActionTimeline.TrimStart)
            .addItem(ActionTimeline.TrimEnd)
            .addItem(ActionTimeline.KeepAll)
            .addSeparator()
            .addItem(ActionTimeline.ShowFrom)
            .addItem(ActionTimeline.ShowUntil)
            .addItem(ActionTimeline.ShowAlways)
        }

        menu.updateState()
        discard menu.doModal(surfacePos, PopupPosition.TopLeft, autoDestroy: true)
    }

    // Returns the capture the bar shows the time of.
    mtd capture()->*Capture?
    {
        let current = .main.getCapture()
        if current != .viewCapture
        {
            if .viewCapture
            {
                .stop(materialize: false)
                .disposeAudio()
            }
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
            let reader = catch TimedReader.open(Capture.mediaPathOf(capture.file, capture.media), capture.media) { return; }
            .thumbReader = Memory.new'TimedReader()
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
            .stop(materialize: false)
            return
        }

        let capture = .capture()
        if not capture or not capture.frames do
            return

        let frame = .seekTimer ? .videoFrom : capture.playhead
        .playFrom = capture.frames.timeOf(frame)
        if capture.media == .Video and not Swag.jit()
        {
            .stopTimer(&.seekTimer)
            .requestVideoFrames(capture, frame)
            .playStart = 0
        }
        else
        {
            catch .startAudio(.playFrom)
            .playStart = Time.monotonicMicroseconds()
        }
        .playTimer = .addTimer(Time.Duration.fromSeconds(1.0 / 60))
        .playButton.setIcon(.theme().icon(.Pause))
        .playButton.toolTip = appStrings().tip_PauseAnimation
    }

    // Stops playback, leaving the playhead where it is.
    mtd stop(materialize = true)
    {
        .stopTimer(&.playTimer)
        .stopTimer(&.seekTimer)
        .stopAudio()
        .stopVideoFrames()
        let capture = .main.getCapture()
        if materialize and capture and capture == .viewCapture and capture.playbackPlanar do
            catch capture.showFrame(capture.playhead)
        .playButton.setIcon(.theme().icon(.Play))
        .playButton.toolTip = appStrings().tip_PlayAnimation
    }

    // Opens the source MP4 lazily and plays its audio tracks alongside the decoded frames.
    // The reader owns the SoundFiles borrowed by the voices, so both stay alive for this bar's life.
    private mtd startAudio(time: u64) fail
    {
        .audioClockLast = -1
        let capture = .capture()
        if not capture or capture.media != .Video do
            return

        let path = Capture.mediaPathOf(capture.file, .Video)
        if .audioReader and not Path.equals(.audioPath, path) do
            .disposeAudio()

        if not .audioReader
        {
            var reader = try Video.Reader.open(path)
            if not reader.audioTrackCount() do
                return

            let stored = Memory.new'Video.Reader()
            stored[] = #move reader
            .audioReader = stored
            .audioPath = path
        }

        let reader = .audioReader
        if not reader or not reader.audioTrackCount() do
            return

        if not Audio.isEngineCreated()
        {
            try Audio.createEngine()
            .ownsAudioEngine = true
        }

        if not .audioVoiceCount
        {
            .audioVoiceCount = cast(u32, Math.min(reader.audioTrackCount(), .audioVoices.count))
            for index in .audioVoiceCount
            {
                let sound = unwrap reader.audioTrack(index)
                .audioVoices[index] = try Voice.create(sound)
            }
        }

        for index in .audioVoiceCount
        {
            let sound = unwrap reader.audioTrack(index)
            let seconds = cast(f64, time) / 1_000_000 - sound.timelineStartSeconds()
            let sample = seconds > 0 ? cast(u64, seconds * cast(f64, sound.sampleRateHz())) : 0
            let voice = .audioVoices[index]
            if voice
            {
                try voice.seekSampleFrame(sample)
                try voice.play()
            }
        }
    }

    // Pauses audio while retaining the reader and voice for the next play command.
    private mtd stopAudio()
    {
        for index in .audioVoiceCount
        {
            let voice = .audioVoices[index]
            if voice do
                catch voice.pause()
        }
    }

    // Stops audio and closes the reader only when the timeline bar itself is destroyed.
    private mtd disposeAudio()
    {
        for index in .audioVoiceCount
        {
            let voice = .audioVoices[index]
            if voice
            {
                catch voice.stop()
                voice.destroy()
                .audioVoices[index] = null
            }
        }
        .audioVoiceCount = 0

        // Destroying an engine drains voices that borrow the reader's sound before the reader closes.
        if .ownsAudioEngine do
            Audio.destroyEngine()
        if .audioReader
        {
            .audioReader.close()
            Memory.delete(.audioReader)
            .audioReader = null
        }

        .ownsAudioEngine = false
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

    // Returns a selected form edge a press takes, or none for the playhead.
    mtd edgeAt(x, y: f32)->TimelineEdge
    {
        let capture = unwrap .capture()
        let track = .trackRect()
        if capture.selection.count == 1 and y >= track.y + track.height * 0.7
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
        return .None
    }

    // Follows a drag on the track at `x`: an end of the kept part, or the playhead.
    mtd drag(x: f32)
    {
        let capture = .capture()
        if not capture or not capture.frames do
            return

        // A form edge follows the pointer without leaving an undo step at each move; the release
        // makes the whole drag one step. Video trim bounds belong to the context menu.
        switch .dragEdge
        {
        case .None:
            .seek(x)
            return

        case .FormStart:
            let form: *BaseForm = capture.forms[capture.selection[0]]
            let finish = form.timeEnd ? form.timeEnd : capture.timeline.duration
            form.timeStart = Math.min(.timeAt(x), Math.min(finish, capture.timeline.duration) - 1)

        case .FormEnd:
            let form: *BaseForm = capture.forms[capture.selection[0]]
            let start  = Math.min(form.timeStart, capture.timeline.duration - 1)
            let finish = Math.min(Math.max(.timeAt(x), start + 1), capture.timeline.duration)
            form.timeStart = start
            form.timeEnd = finish >= capture.timeline.duration ? 0 : finish
        }

        .invalidate()
    }

    // Ends the drag of a selected form edge as one undoable edit.
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

    }

    // Moves the playhead to the frame shown at `x`, in local coordinates on the track.
    mtd seek(x: f32)
    {
        let capture = .capture()
        if not capture or not capture.frames do
            return

        let frames = capture.frames
        let frame  = frames.frameAt(.timeAt(x))
        if capture.media == .Video and not Swag.jit()
        {
            .requestVideoFrames(capture, frame)
            if .isPlaying()
            {
                .stopAudio()
                .playFrom  = frames.timeOf(frame)
                .playStart = 0
            }
            elif not .seekTimer do
                .seekTimer = .addTimer(10'ms)
            .invalidate()
            return
        }
        catch capture.showFrame(frame)
        if .isPlaying()
        {
            .playFrom = frames.timeOf(frame)
            if capture.media == .Video and not Swag.jit()
            {
                .stopAudio()
                .requestVideoFrames(capture, frame)
                .playStart = 0
            }
            else
            {
                catch .startAudio(.playFrom)
                .playStart = Time.monotonicMicroseconds()
            }
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
