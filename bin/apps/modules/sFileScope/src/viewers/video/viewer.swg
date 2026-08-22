#global internal

using Core, Pixel, Gui, Video

private const VideoGlyphSize = 18.0
private const VideoCommandWidth = 350.0

// How far ahead of the picture on screen the playback clock may ask the decoder to go.
//
// An inter-coded picture is decoded from the one before it, so a target further ahead skips no
// work at all: it piles the cost of every picture in between onto a single step. That step lets
// the clock run further ahead, which asks for a target further still, and a stream the machine
// cannot quite sustain collapses within seconds into one picture every second or two. One is the
// only value that presents every picture the decoder is paid to produce.
private const VideoCatchUpLimit = 1'u64

// How far behind the clock playback is allowed to fall before it gives up and jumps.
//
// Walking one picture at a time keeps motion smooth, but on a stream the machine cannot sustain
// it also falls behind for as long as it plays. Past this much, playback skips to the next sync
// frame, which is the one place a jump costs a single decoded picture rather than the decode of
// every picture in between.
private const VideoResyncSeconds = 2.0

// How far past the clock a resync jump may land.
//
// A stream whose sync frames are seconds apart would turn a resync into a scene change; past
// this bound the player keeps walking below speed instead of teleporting.
private const VideoResyncMaxJumpSeconds = 15.0

internal struct VideoViewer
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:   *Wnd
        playButton: *IconButton
        stopButton: *IconButton
        timeline:   *Slider
        frameLabel: *Label
        imageView:  *ImageView
    }

    // The stream is decoded one frame at a time and never held in memory, so a video of any
    // size opens on its header alone and plays with a single decoded frame resident.
    video: Reader

    // Two decoded pictures alternate: the front one is what the renderer uploads, the back one
    // is what the worker decodes into, so the next decode starts while the previous picture is
    // still being published.
    frames:    [2] Image
    frameBack: u32

    // Exactly one decode owns `video` and `frame` at a time. The GUI thread only publishes a
    // completed frame, and repeated seeks replace `requestedFrame` instead of building a queue.
    decodeJob:       Jobs.Job
    decodeError:     #null any
    decodeFrame:     u64
    requestedFrame:  u64
    decodeScheduled: bool
    frameRequested:  bool
    hasFrame:        bool

    timer:         #null *Timer
    clock:         Time.Stopwatch
    elapsed:       f64
    frameIndex:    u64
    playing:       bool
    details:       String
    reportFailure: #null ViewerReportFailure
}

internal impl VideoViewer
{
    mtd frameSeconds(index: u64)->f64
    {
        return cast(f64) index * cast(f64) .video.frameRate().denominator() / cast(f64) .video.frameRate().numerator()
    }

    mtd currentSeconds()->f64
    {
        if !.playing do
            return .elapsed
        return .elapsed + cast(f64) .clock.elapsedMicroseconds() / 1_000_000.0
    }

    mtd refreshTransport()
    {
        .playButton.setIcon(.theme().icon(.playing ? .Pause : .Play, VideoGlyphSize))
        .playButton.toolTip = .playing ? videoStrings().ui_TipPause : videoStrings().ui_TipPlay
        .playButton.enable(.hasFrame)
        .stopButton.enable(.hasFrame and (.frameIndex != 0 or .playing))
        .timeline.setValueWithoutGesture(cast(f32) .frameIndex)
        .frameLabel.setText(Format.toString("% / %", .frameIndex + 1, .video.frameCount()))
    }

    mtd runDecode()
    {
        catch .video.decodeFrameInto(&.frames[.frameBack], .decodeFrame) as decodeError
        .decodeError = decodeError
    }

    // Publishes a worker result on the GUI thread. A seek received during the decode starts only
    // its most recent target, so scrubbing cannot leave minutes of obsolete work queued behind it.
    mtd finishDecode()->bool
    {
        if !.decodeScheduled or !Jobs.isDone(&.decodeJob) do
            return false

        .decodeScheduled = false
        if .decodeError != null
        {
            .playing = false
            .clock.reset()
            if .reportFailure do
                .reportFailure!(me, Errors.message(.decodeError))
            return false
        }

        .frameIndex = .decodeFrame
        .hasFrame   = true

        // Chain the next due decode before publishing: the upload of this picture and the decode
        // of the next one then overlap instead of alternating. The chained decode writes the
        // other picture buffer, so the upload reads stable pixels.
        let published = .frameBack
        .frameBack = 1 - .frameBack
        if .playing and !.frameRequested and !Jobs.isSynchronous()
        {
            let due = .playbackTarget()
            if due != .frameIndex and due < .video.frameCount() do
                discard .startDecode(due)
        }

        .imageView.updateImage(&.frames[published])
        .refreshTransport()

        if .frameRequested
        {
            let requested = .requestedFrame
            .frameRequested = false
            if requested != .frameIndex do
                return .startDecode(requested)
        }

        return true
    }

    mtd startDecode(index: u64)->bool
    {
        .decodeFrame      = index
        .decodeError      = null
        .decodeScheduled  = true
        .decodeJob.lambda = &runVideoViewerDecode
        .decodeJob.data   = me
        Jobs.schedule(&.decodeJob)

        // App tests deliberately do not start global worker threads. Preserve their deterministic
        // behavior while the shipped application always takes the asynchronous branch.
        if Jobs.isSynchronous()
        {
            Jobs.wait(&.decodeJob)
            return .finishDecode()
        }

        return true
    }

    mtd showFrame(index: u64)->bool
    {
        if index >= .video.frameCount() do
            return false

        if .decodeScheduled
        {
            .requestedFrame = index
            .frameRequested = true
            return true
        }

        if .hasFrame and index == .frameIndex do
            return true
        return .startDecode(index)
    }

    mtd seekFrame(index: u64)
    {
        if !.video.frameCount() do
            return
        let target = Math.min(index, .video.frameCount() - 1)
        if !.showFrame(target) do
            return
        .elapsed = .frameSeconds(target)
        if .playing do
            .clock.restart()
    }

    mtd togglePlayback()
    {
        if !.video.frameCount() or !.hasFrame do
            return
        if .playing
        {
            .elapsed = .currentSeconds()
            .clock.reset()
            .playing = false
        }
        else
        {
            if .frameIndex + 1 >= .video.frameCount()
            {
                .elapsed = 0
                discard .showFrame(0)
            }

            .clock.restart()
            .playing = true
        }

        .refreshTransport()
    }

    mtd stopPlayback()
    {
        if !.video.frameCount() do
            return
        .playing = false
        .elapsed = 0
        .clock.reset()
        discard .showFrame(0)
        .refreshTransport()
    }

    // Returns the picture the playback clock asks for next, bounded by the catch-up policy,
    // and re-anchors the clock when the policy decides to skip forward.
    //
    // The result can point past the end of the stream, which the caller turns into a stop.
    //
    // Presentation follows the clock for as long as the decoder keeps up. Once it does not,
    // walking one picture at a time shows every picture the decode pays for, rather than
    // spending that same second of work reaching a distant target and discarding everything
    // decoded on the way. And once the walk has fallen whole seconds behind, playback skips to
    // the next sync frame — the one target a jump reaches for the price of a single decoded
    // picture — and restarts the clock there.
    mtd playbackTarget()->u64
    {
        let rate   = .video.frameRate()
        let target = cast(u64) (.currentSeconds() * cast(f64) rate.numerator() / cast(f64) rate.denominator())
        if target >= .video.frameCount() do
            return target
        if target <= .frameIndex + VideoCatchUpLimit do
            return target

        let resyncLag = cast(u64) (rate.framesPerSecond() * VideoResyncSeconds)
        if target - .frameIndex < resyncLag do
            return .frameIndex + VideoCatchUpLimit

        let sync = .video.syncFrameAt(target)
        let cap  = cast(u64) (rate.framesPerSecond() * VideoResyncMaxJumpSeconds)
        if sync < .video.frameCount() and sync - target <= cap
        {
            .elapsed = .frameSeconds(sync)
            .clock.restart()
            return sync
        }

        return .frameIndex + VideoCatchUpLimit
    }

    mtd updatePlayback()
    {
        discard .finishDecode()
        if !.playing do
            return
        if .decodeScheduled do
            return

        let target = .playbackTarget()
        if target >= .video.frameCount()
        {
            .playing = false
            .elapsed = .video.durationInSeconds()
            .clock.reset()
            discard .showFrame(.video.frameCount() - 1)
            .refreshTransport()
            return
        }

        if target == .frameIndex do
            return

        if !.showFrame(target)
        {
            .playing = false
            .clock.reset()
            .refreshTransport()
            return
        }
    }
}

private impl IWnd for VideoViewer
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .timer
        {
            evt.accepted = false
            return
        }

        .updatePlayback()
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        if .timer
        {
            .removeTimer(.timer!)
            .timer = null
        }

        if .decodeScheduled
        {
            Jobs.wait(&.decodeJob)
            .decodeScheduled = false
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed and evt.key == .Space do
            .togglePlayback()
        else do
            evt.accepted = false
    }
}

private impl VideoViewer
{
    func create(contentParent, commandParent: *Wnd, fileName: string, reportFailure: #null ViewerReportFailure = null)->*VideoViewer fail
    {
        registerVideoStrings(contentParent.app())
        var video  = try Reader.open(fileName)
        let result = Wnd.create'VideoViewer(contentParent, "sFileScope.video")
        result.backgroundStyle = .View
        result.reportFailure   = reportFailure

        with result.commands = Wnd.create'Wnd(commandParent, {0, 0, VideoCommandWidth, 36})
        {
            .backgroundStyle = .Window
        }

        with result.playButton = IconButton.create(result.commands, result.theme().icon(.Play, VideoGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = videoStrings().ui_TipPlay
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.togglePlayback()
            }
        }

        with result.stopButton = IconButton.create(result.commands, result.theme().icon(.Stop, VideoGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = videoStrings().ui_TipStop
            .enable(false)
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.stopPlayback()
            }
        }

        with result.timeline = Slider.create(result.commands, {0, 0, 180, 36})
        {
            .dockStyle = .Left
            .margin    = {8, 1, 8, 1}
            .toolTip   = videoStrings().ui_TipSeek

            // A drag may cross hundreds of frames. Decode its final position once instead of
            // serially decoding every intermediate value queued by the pointer movement.
            .sigEndChange += func|view = result|(slider)
            {
                view.seekFrame(cast(u64) Math.round(slider.value()))
            }
        }

        with result.frameLabel = Label.create(result.commands, "", {0, 0, 74, 36}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .setTextAlignment(.Right, .Center)
        }

        result.imageView           = ImageView.create(result)
        result.imageView.dockStyle = .Center

        result.video = #move video
        result.refreshTransport()

        // A stream whose format cannot report a frame count still plays, but it cannot be
        // seeked through a timeline that has no end to point at.
        let lastFrame = result.video.frameCount() ? result.video.frameCount() - 1 : 0
        result.timeline.setBounds(0, cast(f32) lastFrame, 1)
        result.timeline.enable(lastFrame != 0)
        result.details = Format.toString(videoStrings().ui_Details, result.video.width(), result.video.height(), videoFrameCountText(result.video.frameCount()), result.video.frameRate().framesPerSecond(), result.video.durationInSeconds())
        result.timer   = result.addTimer(10'ms)
        result.applyLayout()
        result.setInitialFocus(result.playButton)
        discard result.showFrame(0)
        return result
    }
}

private func runVideoViewerDecode(data: #null *void)
{
    (cast(*VideoViewer) data!).runDecode()
}

private func loadVideoViewer(contentParent, commandParent: *Wnd, fileName: string, reportFailure: #null ViewerReportFailure)->#null *VideoViewer fail => try VideoViewer.create(contentParent, commandParent, fileName, reportFailure)

// Creates the integrated video playback view.
func createVideoViewer(request: const *ViewerRequest, result: *ViewerResult)
{
    let view = catch loadVideoViewer(request.contentParent, request.commandParent, request.fileName, request.reportFailure) as decodeError
    if decodeError != null
    {
        result.failureReason = Errors.message(decodeError)
        return
    }

    result.view      = view
    result.commands  = view!.commands
    result.details   = view!.details
    result.isLoading = func(wnd)->bool
    {
        let videoView = cast(*VideoViewer) wnd
        return !videoView.hasFrame and videoView.decodeScheduled
    }
}
