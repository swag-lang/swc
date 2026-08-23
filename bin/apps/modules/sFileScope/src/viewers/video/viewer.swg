#global internal

using Core, Pixel, Gui, Video, Audio

private const VideoGlyphSize = 18.0
private const VideoCommandWidth = 350.0

// How far behind the clock playback is allowed to fall before it gives up and jumps.
//
// Showing every decoded picture keeps motion smooth, but on a stream the machine cannot sustain
// it also falls behind for as long as it plays. Past this much, playback skips to the next sync
// frame, which is the one place a jump costs a single decoded picture rather than the decode of
// every picture in between.
private const VideoResyncSeconds = 2.0

// How far the picture may drift from the sound before the timeline is pulled back onto it.
//
// The sound is the master clock, but reading its position on every tick and following it exactly
// would jitter the presentation by the size of one output buffer. Playback therefore runs its own
// clock and only re-anchors it when the two have actually separated.
private const VideoAudioDriftSeconds = 0.1

// How far past the clock a resync jump may land.
//
// A stream whose sync frames are seconds apart would turn a resync into a scene change; past
// this bound the player keeps walking below speed instead of teleporting.
private const VideoResyncMaxJumpSeconds = 15.0

// How much memory the decoded run-ahead may hold, and how many pictures it may hold at all.
//
// A frame-threaded decoder delivers pictures in runs separated by the cost of one key picture,
// which at 4K is well over a hundred milliseconds. The queue exists to cover exactly that gap,
// so it is sized in bytes: a 4K stream gets the few pictures that cover it, and a small stream
// gets a deeper one for the same memory.
private const VideoPrefetchBytes = 128 * 1024 * 1024'u64
private const VideoPrefetchMax = 12'u64
private const VideoPrefetchMin = 2'u64

// Names the absence of a queue slot.
private const VideoNoSlot = Swag.U32.Max

// One decoded picture of the run-ahead queue.
internal struct VideoSlot
{
    image: Image
    index: u64
}

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

    // The stream is read through its own header alone, so a video of any size opens instantly.
    video:               Reader
    audio:               #null const *SoundFile
    voice:               #null *Voice
    audioEngineAcquired: bool

    // Decoded pictures waiting for their turn on screen.
    //
    // A frame-threaded decoder does not deliver one picture every so many milliseconds: it
    // delivers a run of them and then spends a hundred milliseconds or more on the next key
    // picture, which arrives once a second and blocks every picture that predicts from it.
    // Presenting straight off the decoder therefore stutters even when the average rate is
    // several times what the clock asks for. The run-ahead absorbs that: the decoder fills the
    // queue while it is fast and the clock drains it while the key picture is being decoded.
    slots:     Array'VideoSlot
    slotCount: u32

    // Exactly one decode owns `video` and one free slot at a time. It runs on a persistent Swag
    // thread instead of occupying a scheduler worker: the codec can therefore give all global
    // workers to entropy parsing, reconstruction, filtering, and color conversion.
    decodeThread: Threading.Thread
    decodeWake:   Sync.Event
    queueLock:    Sync.Mutex

    // Queue state, all read and written under `queueLock`.
    ready:       Array'u32     // Slots holding a decoded picture, in ascending frame order.
    freeSlots:   Array'u32
    nextDecode:  u64           // Frame the producer takes next.
    produceFrom: u64           // Frame the producer was last aimed at.
    inFlight:    u32           // Whether a picture is being decoded right now.
    generation:  u32           // Bumped by every reposition, so a stale result is dropped.
    failureText: String
    hasFailure:  bool

    // Last position read from the sound. Playback re-anchors on it only when it moves, so a
    // stalled output device cannot stop the picture.
    audioClockLast: f64 = -1

    awaitingFrame:        bool
    anchorPending:        bool     // The next published picture re-anchors the playback clock on itself.
    hasFrame:             bool
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
        return .elapsed + cast(f64) .clock.elapsedMicroseconds() / 1_000_000.0
    }

    // Pulls the playback timeline back onto the sound whenever the two have separated.
    //
    // The sound is the master clock: a picture is presented at the time the output device has
    // reached, and the sound timeline is never moved to conceal video decode latency. What the
    // player must not do is *become* that position. A device that reports the same position twice
    // is a clock that has stopped — an output that never consumes what it was given reports zero
    // forever — and a player reading it directly would hold one picture on screen for good.
    // Playback therefore keeps its own clock and lets the sound correct it, which also removes
    // the jitter of following a position that only moves once per output buffer.
    mtd followAudioClock()
    {
        if !.playing or !.voice do
            return

        let position = .voice!.playbackPositionSeconds()
        if position == .audioClockLast do
            return

        .audioClockLast = position
        if Math.abs(position - .currentSeconds()) <= VideoAudioDriftSeconds do
            return

        .elapsed = position
        .clock.restart()
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

    // Sizes the run-ahead queue from the picture size.
    //
    // The queue has to cover the longest gap the decoder can leave, which is one key picture,
    // and every slot costs a whole frame of memory. Bounding it by bytes rather than by count
    // gives a small stream a deep queue and a 4K stream one that still covers that gap.
    mtd prepareSlots()
    {
        let bytes = cast(u64) .video.width() * cast(u64) .video.height() * 3
        var count = bytes ? VideoPrefetchBytes / bytes : cast(u64) VideoPrefetchMax
        count = Math.clamp(count, cast(u64) VideoPrefetchMin, cast(u64) VideoPrefetchMax)

        .slotCount = cast(u32) count
        .slots.resize(count)
        .freeSlots.clear()
        for index in count do
            .freeSlots.add(cast(u32) index)
    }

    // Aims the producer at `index`, dropping everything it had already decoded past it.
    //
    // A reposition that is still waiting for its own picture is not repeated: a starved queue
    // asks for the same sync frame on every tick, and restarting the decoder each time would
    // never let it fill.
    mtd repositionTo(index: u64)
    {
        Sync.scopedLock(&.queueLock)
        if .anchorPending and .produceFrom == index and !.hasFailure do
            return

        for slot in .ready do
            .freeSlots.add(slot)
        .ready.clear()
        .nextDecode    = index
        .produceFrom   = index
        .generation    += 1
        .hasFailure    = false
        .awaitingFrame = true
        .anchorPending = true
    }

    // Decodes one queued picture, and reports whether the producer can immediately do more.
    mtd produceOne()->bool
    {
        var slot       = 0'u32
        var index      = 0'u64
        var generation = 0'u32
        {
            Sync.scopedLock(&.queueLock)
            if .hasFailure or !.freeSlots.count do
                return false
            if .nextDecode >= .video.frameCount() do
                return false

            // A paused viewer wants the picture it is parked on and nothing more.
            if !.playing and (.ready.count != 0 or .inFlight != 0 or .nextDecode != .produceFrom) do
                return false

            slot = .freeSlots[.freeSlots.count - 1]
            .freeSlots.removeBack()
            index       = .nextDecode
            generation  = .generation
            .nextDecode += 1
            .inFlight   += 1
        }

        catch .video.decodeFrameInto(&.slots[cast(u64) slot].image, index) as decodeError

        Sync.scopedLock(&.queueLock)
        .inFlight -= 1
        if generation != .generation
        {
            .freeSlots.add(slot)
            return true
        }

        if decodeError != null
        {
            .failureText = Errors.message(decodeError)
            .hasFailure  = true
            .freeSlots.add(slot)
            return false
        }

        .slots[cast(u64) slot].index = index
        .ready.add(slot)
        return true
    }

    // Runs the producer until it can make no further progress.
    mtd produceUntilBlocked()
    {
        while .produceOne()
        {
        }
    }

    // Publishes the oldest queued picture, and reports whether one reached the screen.
    //
    // Every decoded picture is presented rather than dropped. The decoder is asked only for the
    // pictures playback intends to show, so a queued one is never obsolete, and presenting them
    // in order is what keeps motion smooth when the clock has run ahead.
    mtd publishHead()->bool
    {
        // App tests deliberately do not start global worker threads. Preserve their
        // deterministic behavior while the shipped application always produces in background.
        if Jobs.isSynchronous() do
            .produceUntilBlocked()

        var chosen = VideoNoSlot
        var failure: String
        {
            Sync.scopedLock(&.queueLock)
            if .ready.count
            {
                chosen = .ready[0]
                .ready.removeAt(0)
            }
            elif .hasFailure
            {
                failure     = .failureText
                .hasFailure = false
            }
        }

        if failure.length
        {
            .resumeAudioAfterSeek = false
            if .voice
            {
                .elapsed = .voice!.playbackPositionSeconds()
                catch .voice!.pause()
            }

            .playing       = false
            .awaitingFrame = false
            .clock.reset()
            if .reportFailure do
                .reportFailure!(me, failure.toString())
            return false
        }

        if chosen == VideoNoSlot do
            return false

        .frameIndex    = .slots[cast(u64) chosen].index
        .hasFrame      = true
        .awaitingFrame = false
        if .anchorPending
        {
            // A jump moved the producer, so the silent clock follows the picture that came back
            // rather than the position it asked for. Sound is the master clock when there is
            // one, and its timeline is never moved to conceal video decode latency.
            .anchorPending = false
            if .playing and !.voice
            {
                .elapsed = .frameSeconds(.frameIndex)
                .clock.restart()
            }
        }

        .imageView.exchangeImage(&.slots[cast(u64) chosen].image)
        {
            Sync.scopedLock(&.queueLock)
            .freeSlots.add(chosen)
        }

        .decodeWake.signal()
        .refreshTransport()

        // A transport seek holds the audio clock until its target picture is on screen. This
        // avoids showing the previous picture while sound has already jumped to the new time.
        if .resumeAudioAfterSeek do
            .resumeAudio()
        return true
    }

    // Positions playback on one picture and asks the producer for it.
    mtd showFrame(index: u64)->bool
    {
        if index >= .video.frameCount() do
            return false
        if .hasFrame and !.awaitingFrame and index == .frameIndex do
            return true
        .repositionTo(index)
        .decodeWake.signal()
        discard .publishHead()
        return true
    }

    mtd seekFrame(index: u64)
    {
        if !.video.frameCount() do
            return
        let target      = Math.min(index, .video.frameCount() - 1)
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
                .playing              = false
                catch .voice!.pause()
                if .reportFailure do
                    .reportFailure!(me, Errors.message(seekError))
                return
            }

            if resumeAudio
            {
                if .frameIndex != target do
                    .resumeAudioAfterSeek = true
                else do
                    .resumeAudio()
            }
        }

        .audioClockLast = -1
        if .playing do
            .clock.restart()
    }

    mtd togglePlayback()
    {
        if !.video.frameCount() or !.hasFrame do
            return
        if .playing
        {
            .resumeAudioAfterSeek = false
            .elapsed              = .currentSeconds()
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

            .audioClockLast = -1
            .clock.restart()
            .playing = true
            .decodeWake.signal()
        }

        .refreshTransport()
    }

    mtd stopPlayback()
    {
        if !.video.frameCount() do
            return
        .playing              = false
        .resumeAudioAfterSeek = false
        .elapsed              = 0
        .clock.reset()
        if .voice do
            catch .voice!.stop()
        discard .showFrame(0)
        .refreshTransport()
    }

    // Returns the picture the playback clock is currently on.
    mtd clockFrame()->u64
    {
        return .video.frameAtTime(.currentSeconds())
    }

    // Advances presentation by at most one picture, and decides when to give up and skip.
    //
    // Presentation follows the run-ahead queue: a picture is shown once the clock reaches it,
    // and every decoded picture is shown. Only a starved queue means the decoder is not
    // keeping up, and only a queue starved for whole seconds is worth answering with a jump to
    // the next sync frame — the one target that costs a single decoded picture rather than the
    // decode of everything in between.
    mtd updatePlayback()
    {
        if !.playing
        {
            discard .publishHead()
            return
        }

        .followAudioClock()

        var head  = 0'u64
        var empty = true
        {
            Sync.scopedLock(&.queueLock)
            if .ready.count
            {
                head  = .slots[cast(u64) .ready[0]].index
                empty = false
            }
        }

        let clock = .clockFrame()
        if !empty
        {
            // Nothing is dropped, so the clock only gates when the next picture is due.
            if .anchorPending or head <= clock do
                discard .publishHead()
            return
        }

        if clock >= .video.frameCount() and .frameIndex + 1 >= .video.frameCount()
        {
            .playing              = false
            .resumeAudioAfterSeek = false
            .elapsed              = .video.durationInSeconds()
            .clock.reset()
            if .voice do
                catch .voice!.pause()
            .refreshTransport()
            return
        }

        // A jump already asked for has not produced its picture yet. Waiting for it is not
        // falling behind, and asking for another one would restart the whole decoder over and
        // over while its pipeline fills.
        if .anchorPending do
            return

        // The queue is empty: the decoder is behind. Past the resync bound, skip to the next
        // sync frame instead of walking pictures the viewer will never catch up with.
        let rate      = .video.frameRate()
        let resyncLag = cast(u64) (rate.framesPerSecond() * VideoResyncSeconds)
        if clock < .frameIndex + resyncLag do
            return

        let sync = .video.syncFrameAt(clock)
        let cap  = cast(u64) (rate.framesPerSecond() * VideoResyncMaxJumpSeconds)
        if sync >= .video.frameCount() or sync - clock > cap do
            return

        .repositionTo(sync)
        .decodeWake.signal()
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
        result.prepareSlots()
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
            result.decodeThread.init(&runVideoViewerDecode, result, priority: .BelowNormal)
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

// Keeps the run-ahead queue as full as the viewer currently wants it.
private func runVideoViewerDecode(thread: Threading.Thread)
{
    let view = cast(*VideoViewer) thread.userParam!
    while !thread.requestEnd
    {
        view.decodeWake.wait()
        while !thread.requestEnd and view.produceOne()
        {
        }
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
        return !videoView.hasFrame and videoView.awaitingFrame
    }
}
