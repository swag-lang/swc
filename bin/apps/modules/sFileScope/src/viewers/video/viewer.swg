#global internal

using Core, Pixel, Gui, Video, Audio

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
    video:               Reader
    audio:               #null const *SoundFile
    voice:               #null *Voice
    audioEngineAcquired: bool

    // Two decoded pictures alternate: the front one is what the renderer uploads, the back one
    // is what the worker decodes into, so the next decode starts while the previous picture is
    // still being published.
    frames:    [2] Image
    frameBack: u32

    // Exactly one decode owns `video` and the back frame at a time. It runs on a persistent Swag
    // thread instead of occupying a scheduler worker: the codec can therefore give all global
    // workers to entropy parsing, reconstruction, filtering, and color conversion. The GUI
    // thread only publishes a completed frame, and repeated seeks replace `requestedFrame`
    // instead of building a queue.
    decodeThread:    Threading.Thread
    decodeWake:      Sync.Event
    decodeDone:      u32
    decodeError:     #null any
    decodeFrame:     u64
    requestedFrame:  u64
    decodeScheduled: bool
    frameRequested:      bool
    hasFrame:            bool
    resumeAudioAfterSeek: bool

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
        return .video.frameTimestamp(index)
    }

    mtd currentSeconds()->f64
    {
        if !.playing do
            return .elapsed
        if .voice do
            return .voice!.playbackPositionSeconds()
        return .elapsed + cast(f64) .clock.elapsedMicroseconds() / 1_000_000.0
    }

    mtd resumeAudio()
    {
        .resumeAudioAfterSeek = false
        if !.voice do
            return
        catch .voice!.play() as playError
        if playError != null
        {
            .playing = false
            .refreshTransport()
            if .reportFailure do
                .reportFailure!(me, Errors.message(playError))
        }
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
        if !.decodeScheduled or Atomic.get(&.decodeDone) == 0 do
            return false

        .decodeScheduled = false
        if .decodeError != null
        {
            .resumeAudioAfterSeek = false
            if .voice
            {
                .elapsed = .voice!.playbackPositionSeconds()
                catch .voice!.pause()
            }

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

        // A transport seek holds the audio clock until its target picture is on screen. This
        // avoids showing the previous picture while sound has already jumped to the new time.
        if .resumeAudioAfterSeek do
            .resumeAudio()

        return true
    }

    mtd startDecode(index: u64)->bool
    {
        .decodeFrame     = index
        .decodeError     = null
        .decodeScheduled = true

        // App tests deliberately do not start global worker threads. Preserve their deterministic
        // behavior while the shipped application always takes the asynchronous branch.
        if Jobs.isSynchronous()
        {
            .runDecode()
            Atomic.exchange(&.decodeDone, 1)
            return .finishDecode()
        }

        Atomic.exchange(&.decodeDone, 0)
        .decodeWake.signal()
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
        let resumeAudio = .playing and .voice != null
        .resumeAudioAfterSeek = false
        if resumeAudio do
            catch .voice!.pause()
        if !.showFrame(target) do
            return
        .elapsed = .frameSeconds(target)
        if .voice
        {
            let sample = cast(u64) Math.round(.elapsed * cast(f64) .audio!.sampleRateHz())
            catch .voice!.seekSampleFrame(sample) as seekError
            if seekError != null
            {
                .resumeAudioAfterSeek = false
                .playing = false
                catch .voice!.pause()
                if .reportFailure do
                    .reportFailure!(me, Errors.message(seekError))
                return
            }

            if resumeAudio
            {
                if .decodeScheduled or .frameIndex != target do
                    .resumeAudioAfterSeek = true
                else do
                    .resumeAudio()
            }
        }
        elif .playing do
            .clock.restart()
    }

    mtd togglePlayback()
    {
        if !.video.frameCount() or !.hasFrame do
            return
        if .playing
        {
            .resumeAudioAfterSeek = false
            .elapsed = .currentSeconds()
            if .voice do
                catch .voice!.pause()
            .clock.reset()
            .playing = false
        }
        else
        {
            if .frameIndex + 1 >= .video.frameCount()
            {
                .elapsed = 0
                discard .showFrame(0)
                if .voice do
                    catch .voice!.seekSampleFrame(0)
            }

            if .voice
            {
                catch .voice!.play() as playError
                if playError != null
                {
                    if .reportFailure do
                        .reportFailure!(me, Errors.message(playError))
                    return
                }
            }
            else do
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
        .resumeAudioAfterSeek = false
        .elapsed = 0
        .clock.reset()
        if .voice do
            catch .voice!.stop()
        discard .showFrame(0)
        .refreshTransport()
    }

    // Returns the picture the playback clock asks for next, bounded by the catch-up policy.
    //
    // The result can point past the end of the stream, which the caller turns into a stop.
    //
    // Presentation follows the clock for as long as the decoder keeps up. Once it does not,
    // walking one picture at a time shows every picture the decode pays for, rather than
    // spending that same second of work reaching a distant target and discarding everything
    // decoded on the way. And once the walk has fallen whole seconds behind, playback skips to
    // the next sync frame — the one target a jump reaches for the price of a single decoded
    // picture. Silent playback moves its fallback clock to that clean point; an audio-master
    // timeline keeps advancing unchanged and drops only obsolete pictures.
    mtd playbackTarget()->u64
    {
        let rate   = .video.frameRate()
        let target = .video.frameAtTime(.currentSeconds())
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
            // Audio is the master clock. A late picture jumps to a clean decode point, but the
            // sound timeline is never moved to conceal video decode latency.
            if !.voice
            {
                .elapsed = .frameSeconds(sync)
                .clock.restart()
            }

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
            .resumeAudioAfterSeek = false
            .elapsed = .video.durationInSeconds()
            .clock.reset()
            if .voice do
                catch .voice!.pause()
            discard .showFrame(.video.frameCount() - 1)
            .refreshTransport()
            return
        }

        if target == .frameIndex do
            return

        if !.showFrame(target)
        {
            .playing = false
            .resumeAudioAfterSeek = false
            .clock.reset()
            if .voice do
                catch .voice!.pause()
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

        if .decodeThread.isValid()
        {
            .decodeThread.safeForceEnd()
            .decodeWake.signal()
            .decodeThread.wait()
            .decodeWake.release()
        }

        if .voice
        {
            catch .voice!.stop()
            .voice!.destroy()
            .voice = null
        }

        if .audioEngineAcquired
        {
            releaseSoundEngine()
            .audioEngineAcquired = false
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
        defer #fail
        {
            if result.voice
            {
                catch result.voice!.stop()
                result.voice!.destroy()
                result.voice = null
            }

            if result.audioEngineAcquired
            {
                releaseSoundEngine()
                result.audioEngineAcquired = false
            }
        }

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
        if result.video.audioTrackCount()
        {
            if !acquireSoundEngine() do
                fail UnsupportedFormatError{"cannot create the audio engine for video playback"}
            result.audioEngineAcquired = true
            result.audio               = result.video.audioTrack(0)
            result.voice               = Voice.create(result.audio!)
        }

        if !Jobs.isSynchronous()
        {
            result.decodeWake.init()
            result.decodeThread.init(&runVideoViewerDecode, result)
            result.decodeThread.start()
        }

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

private func runVideoViewerDecode(thread: Threading.Thread)
{
    let view = cast(*VideoViewer) thread.userParam!
    while !thread.requestEnd
    {
        view.decodeWake.wait()
        if thread.requestEnd do
            break

        view.runDecode()
        Atomic.exchange(&view.decodeDone, 1)
    }
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
