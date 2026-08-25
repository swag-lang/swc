#global internal

using Core, Pixel, Gui, Video, Audio

private const VideoGlyphSize = 18.0
private const VideoSeekSeconds = 10.0
private const VideoSeekOverlaySize = Math.Point{136, 88}
private const VideoSeekOverlayLifetime: Time.Duration = 650'ms

// Briefly reports a relative timeline jump over the picture itself.
//
// The tile is painted from the active theme rather than from the movie palette, so it remains
// legible over both bright and dark frames. Presentation transforms move the complete sign in
// the direction of travel without disturbing layout or hit testing.
internal struct VideoSeekOverlay
{
    using wnd: Wnd

    #[Swag.Late]
    commands:     *ViewerCommandBar
    backwardIcon: Icon
    forwardIcon:  Icon
    text:         String
    direction:    s32
    fontReady:    bool
    timer:        #null *Timer
    offsetAni:    AnimationHandle
    scaleAni:     AnimationHandle
    opacityAni:   AnimationHandle
}

private impl IWnd for VideoSeekOverlay
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let rect    = .clientRect()
        let theme   = .theme()
        let colors  = .themeColors()
        let ink     = colors.text

        theme.drawSubRect(painter, rect, &theme.rects.selectionBox_Bk, colors.wnd_Bk.withAlphaF32(0.94))

        let icon     = .direction < 0 ? .backwardIcon : .forwardIcon
        let font     = .font().regular!
        let textSize = Painter.measureString(.text.toString(), font)
        let gap      = 8'f32
        let width    = icon.sizeX + gap + textSize.width
        let iconX    = Math.floor(rect.horzCenter() - width * 0.5)
        let iconY    = Math.floor(rect.vertCenter() - icon.sizeY * 0.5)
        let textX    = iconX + icon.sizeX + gap
        let textY    = Math.floor(rect.vertCenter() - font.height * 0.5)

        icon.paint(painter, iconX, iconY, ink)
        painter.drawString(textX, textY, .text.toString(), font, ink)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .timer
        {
            evt.accepted = false
            return
        }

        .removeTimer(evt.timer)
        .timer = null
        .hide()
        .resetPresentation()
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        if .timer do
            .removeTimer(.timer!)
    }
}

internal impl VideoSeekOverlay
{
    func create(parent: *Wnd, commands: *ViewerCommandBar)->*VideoSeekOverlay
    {
        let result = Wnd.create'VideoSeekOverlay(parent, "sFileScope.video.seek", {0, 0, VideoSeekOverlaySize.x, VideoSeekOverlaySize.y})
        result.wndFlags |= WndFlags.TopMost | WndFlags.Disabled
        result.commands = commands
        result.hide()
        return result
    }

    // Restarts the feedback for one signed jump in seconds.
    mtd showSeek(seconds: f64)
    {
        if seconds == 0 do
            return

        let animator = &.app().animator
        if animator.isActive(.offsetAni) do
            animator.cancel(.offsetAni)
        if animator.isActive(.scaleAni) do
            animator.cancel(.scaleAni)
        if animator.isActive(.opacityAni) do
            animator.cancel(.opacityAni)
        if .timer do
            .removeTimer(.timer!)

        .direction = seconds < 0 ? -1 : 1
        .text      = Format.toString(seconds < 0 ? "-%" : "+%", cast(u64) Math.round(Math.abs(seconds)))
        if !.fontReady
        {
            .style.setFont(.theme().createDefaultFont(24, .Bold), .Regular)
            .fontReady = true
        }

        if .direction < 0 and !.backwardIcon.isValid() do
            .backwardIcon = .commands.icon(.SeekBackward, 30)
        if .direction > 0 and !.forwardIcon.isValid() do
            .forwardIcon = .commands.icon(.SeekForward, 30)
        let rect = .parent!.clientRect()
        let size = .preferredSize
        .setPosition({Math.floor((rect.width - size.x) * 0.5), Math.floor((rect.height - size.y) * 0.5), size.x, size.y}, computeLayout: false)
        .resetPresentation()
        .show()
        .bringToFront()
        .timer = .addTimer(VideoSeekOverlayLifetime)

        // Reduced motion keeps the information but removes its travel and zoom.
        if .app().isReducedMotion() do
            return

        let direction = cast(f32) .direction
        .setPresentationOffset({-10 * direction, 0})
        .setPresentationScale({0.9, 0.9})

        var travel: AnimationOptions
        travel.duration = 600'ms
        travel.easing   = .EaseOut
        .offsetAni      = animator.animatePoint(me, AnimationChannel.from("sFileScope.VideoSeek.Offset"), {-10 * direction, 0}, {14 * direction, 0}, func(wnd, value) { wnd.setPresentationOffset(value); }, travel)

        var scale: AnimationOptions
        scale.duration = 180'ms
        scale.easing   = .EaseOut
        .scaleAni      = animator.animatePoint(me, AnimationChannel.from("sFileScope.VideoSeek.Scale"), {0.9, 0.9}, {1, 1}, func(wnd, value) { wnd.setPresentationScale(value); }, scale)

        var fade: AnimationOptions
        fade.delay    = 350'ms
        fade.duration = 250'ms
        fade.easing   = .EaseIn
        .opacityAni   = animator.animateF32(me, AnimationChannel.from("sFileScope.VideoSeek.Opacity"), 1, 0, func(wnd, value) { wnd.setPresentationOpacity(value); }, fade)
    }
}

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
private const VideoBackdropColors = "view_Bk 0xFF000000"

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

func videoSoundCovers(sound: const *SoundFile, seconds: f64)->bool
{
    let local = seconds - sound.timelineStartSeconds()
    if local < 0 do
        return false
    let wanted = cast(u64) Math.ceil(local * cast(f64) sound.sampleRateHz())
    return wanted < sound.sampleFrameCount()
}

func videoSoundSample(sound: const *SoundFile, seconds: f64)->u64
{
    let local = Math.max(seconds - sound.timelineStartSeconds(), 0)
    return cast(u64) Math.round(local * cast(f64) sound.sampleRateHz())
}

private func videoAudioTrackCommand(index: u32)->String
{
    return Format.toString("sFileScope.video.audioTrack.%", index)
}

// One decoded picture of the run-ahead queue.
//
// A codec reconstructs planar 4:2:0 and the renderer converts where it draws, so a queued picture
// is the planes themselves. That is both the cheaper decode and the smaller queue: three planes
// are half the bytes of the packed picture they would have become.
internal struct VideoSlot
{
    planes: PlanarFrame
    image:  Image     // Used only by a stream whose codec does not reconstruct planes.
    index:  u64
}

internal struct VideoViewer
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:       *ViewerCommandBar
        playButton:     *IconButton
        stopButton:     *IconButton
        backwardButton: *IconButton
        forwardButton:  *IconButton
        timeline:       *Slider
        timeLabel:      *Label
        audioButton:    *IconButton
        muteButton:     *IconButton
        volumeSlider:   *Slider
        imageView:      *ImageView
    }

    seekOverlay: #null *VideoSeekOverlay

    // Opening and decoding run on the same persistent worker, preserving codec allocator and
    // thread affinity. `openState` is zero while opening, one on success and two on failure.
    openFileName: String
    pendingVideo: Reader
    openFailure:  String
    openState:    u32
    openFinished: bool

    // Opening retains bounded metadata while progressive indexes and payloads stay in the file.
    video:               Reader
    planar:              bool     // The codec hands its pictures over without converting them.
    audio:               #null const *SoundFile
    voice:               #null *Voice
    audioTrackIndex:     u32
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
    //
    // `ready` holds the slots that carry a decoded picture, oldest first. The order *is* the
    // queue, so taking from the front has to preserve it, which is what `removeAtOrdered` is for:
    // the unstable remove swaps the newest picture to the front, and the ones it steps over are
    // then never taken at all. Playback still looks sequential when that happens, because the
    // front keeps advancing by one — what is lost is the run-ahead itself, which silently shrinks
    // to two pictures however many slots are reported full.
    ready:       Array'u32
    freeSlots:   Array'u32
    nextDecode:  u64     // Frame the producer takes next.
    produceFrom: u64     // Frame the producer was last aimed at.
    inFlight:    u32     // Whether a picture is being decoded right now.
    generation:  u32     // Bumped by every reposition, so a stale result is dropped.
    failureText: String
    hasFailure:  bool

    // Last position read from the sound. Playback re-anchors on it only when it moves, so a
    // stalled output device cannot stop the picture.
    audioClockLast: f64 = -1

    awaitingFrame:        bool
    anchorPending:        bool     // The next published picture re-anchors the playback clock on itself.
    hasFrame:             bool
    resumeAudioAfterSeek: bool
    audioRangePending:    bool     // The progressive sound index does not reach the picture yet.

    timer:                #null *Timer
    clock:                Time.Stopwatch
    elapsed:              f64
    frameIndex:           u64
    playing:              bool
    muted:                bool
    volume = 1'f32
    details:              String
    metadataReady:        bool
    audioReady:           bool
    timelineReady:        bool
    timelineChanging:     bool
    reportDetails:        #null ViewerReportDetails
    reportFailure:        #null ViewerReportFailure
    reportLoadingChanged: #null ViewerReportLoadingChanged
    retireRequested:      bool
    retired:              bool

    // Pixel column the timeline thumb was last pushed to, so a value that would not move it is
    // not pushed at all.
    timelinePixel: s32 = -1
}

private impl VideoViewer
{
    // Finishes teardown after the decoder thread has stopped touching the reader and frame queue.
    mtd finishRetire()
    {
        if .retired do
            return

        if .decodeThread.isValid() do
            .decodeThread.wait()
        if .decodeWake.isValid() do
            .decodeWake.release()

        // GUI destruction is deferred until the replacement has a picture to present. Release
        // the run-ahead queue now, but leave the displayed image alive so the content does not
        // flash to its background between two movies.
        .slots.clear()
        .ready.clear()
        .freeSlots.clear()

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

        .pendingVideo.close()
        .video.close()
        .retired = true
    }

    // Requests teardown and reports when deferred GUI destruction may release this view.
    mtd retire()->bool
    {
        if .retired do
            return true
        if !.retireRequested
        {
            .retireRequested = true
            if .timer
            {
                .removeTimer(.timer!)
                .timer = null
            }

            // A voice borrows its SoundFile from the reader. Release it before the decoder
            // thread closes that reader in the background.
            if .voice
            {
                catch .voice!.stop()
                .voice!.destroy()
                .voice = null
                .audio = null
            }

            if .audioEngineAcquired
            {
                releaseSoundEngine()
                .audioEngineAcquired = false
            }

            if .decodeThread.isValid()
            {
                .video.requestCancel()
                .decodeThread.safeForceEnd()
                .decodeWake.signal()
            }
        }

        if .decodeThread.isValid() and !.decodeThread.isDone() do
            return false
        .finishRetire()
        return true
    }

    // Window destruction is the terminal fallback; unlike file selection it may wait.
    mtd retireBlocking()
    {
        discard .retire()
        .finishRetire()
    }

    mtd retranslate()
    {
        .playButton.toolTip     = .playing ? videoStrings().ui_TipPause : videoStrings().ui_TipPlay
        .stopButton.toolTip     = videoStrings().ui_TipStop
        .backwardButton.toolTip = videoStrings().ui_TipBackward
        .forwardButton.toolTip  = videoStrings().ui_TipForward
        .timeline.toolTip       = videoStrings().ui_TipSeek
        .muteButton.toolTip     = videoStrings().ui_TipMute
        .volumeSlider.toolTip   = videoStrings().ui_TipVolume

        .audioButton.toolTip = videoStrings().ui_TipAudio

        .refreshDetails()
    }
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
        if !.playing or !.voice or .audioRangePending or .resumeAudioAfterSeek do
            return

        let position = .audio!.timelineStartSeconds() + .voice!.playbackPositionSeconds()
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
        if !.voice or !.audio do
            return
        if !videoSoundCovers(.audio!, .currentSeconds())
        {
            .audioRangePending = true
            return
        }

        .audioRangePending = false
        catch .voice!.play() as playError
        if playError != null
        {
            .playing = false
            .refreshTransport()
            if .reportFailure do
                .reportFailure!(me, Errors.message(playError))
            return
        }

        .audioClockLast = .audio!.timelineStartSeconds() + .voice!.playbackPositionSeconds()
        .elapsed        = .audioClockLast
        .clock.restart()
    }

    mtd refreshTransport()
    {
        .playButton.setIcon(.theme().icon(.playing ? .Pause : .Play, VideoGlyphSize))
        .playButton.toolTip = .playing ? videoStrings().ui_TipPause : videoStrings().ui_TipPlay
        .playButton.enable(.hasFrame)
        .stopButton.enable(.hasFrame and (.frameIndex != 0 or .playing))
        .refreshTime()
    }

    mtd refreshTime()
    {
        let duration = cast(f64) .video.durationInSeconds()
        let seconds  = Math.clamp(.currentSeconds(), 0, duration)

        // Push the thumb only where it would actually move. A timeline is a couple of thousand
        // pixels at most and a recording is hours long, so one pixel of travel is seconds of
        // playback: pushed on every tick the slider invalidates a hundred times a second for a
        // position nobody can tell apart. What that costs is not the slider — it is that the
        // repainted region then spans from the command bar to the picture, so the surface repaints
        // its whole hierarchy and chrome instead of the one view that changed.
        if !.timelineChanging
        {
            let width = .timeline.position.width
            if duration <= 0 or width <= 0
            {
                .timeline.setValueWithoutGesture(cast(f32) seconds)
            }
            else
            {
                let pixel = cast(s32) (seconds / duration * cast(f64) width)
                if pixel != .timelinePixel
                {
                    .timelinePixel = pixel
                    .timeline.setValueWithoutGesture(cast(f32) seconds)
                }
            }
        }

        .timeLabel.setText(mediaTimeRangeText(seconds, duration))
    }

    mtd seekSeconds(seconds: f64)
    {
        let duration = cast(f64) .video.durationInSeconds()
        let target   = Math.clamp(seconds, 0, duration)
        .seekFrame(.video.frameAtTime(target))
    }

    mtd seekRelative(seconds: f64)
    {
        .seekSeconds(.currentSeconds() + seconds)
        .showSeekFeedback(seconds)
    }

    mtd showSeekFeedback(seconds: f64)
    {
        if !.seekOverlay do
            .seekOverlay = VideoSeekOverlay.create(me, .commands)
        .seekOverlay!.showSeek(seconds)
    }

    mtd setMuted(muted: bool)
    {
        .muted = muted
        .muteButton.setChecked(muted)
        .muteButton.setIcon(.commands.icon(muted ? .VolumeMute : .Volume, VideoGlyphSize))
        if .voice do
            catch .voice!.setVolume(muted ? 0 : .volume)
    }

    mtd setVolume(volume: f32)
    {
        .volume = Math.clamp(volume, 0, 1)
        if .voice and !.muted do
            catch .voice!.setVolume(.volume)
    }

    // Replaces the active sound track without disturbing picture transport state.
    //
    // The new voice is fully positioned and configured before the old one is released, so an
    // unsupported track cannot turn a playing video silent halfway through the operation.
    mtd selectAudioTrack(index: u32) fail
    {
        if index >= .video.audioTrackCount() do
            fail BadParameterError{"video audio-track index exceeds the track count"}

        let sound = .video.audioTrack(index)!
        if .voice and index == .audioTrackIndex and .audio == sound do
            return
        let position      = .currentSeconds()
        let wasPlaying    = .playing
        let coversRange   = videoSoundCovers(sound, position)
        let shouldPlay    = wasPlaying and coversRange and !.resumeAudioAfterSeek
        let restoreOld    = wasPlaying and .voice != null and !.audioRangePending and !.resumeAudioAfterSeek
        let newVoice      = Voice.create(sound)!
        let oldVoice      = .voice
        var restoreNeeded = restoreOld
        defer #fail
        {
            newVoice.destroy()
            if restoreNeeded do
                catch oldVoice!.play()
        }

        newVoice.setVolume(.muted ? 0 : .volume)
        if coversRange do
            newVoice.seekSampleFrame(videoSoundSample(sound, position))
        if oldVoice do
            oldVoice!.pause()
        if shouldPlay do
            newVoice.play()

        restoreNeeded = false
        if oldVoice
        {
            catch oldVoice!.stop()
            oldVoice!.destroy()
        }

        .audio             = sound
        .voice             = newVoice
        .audioTrackIndex   = index
        .audioRangePending = !coversRange
        .audioClockLast    = -1
        if shouldPlay
        {
            .elapsed = position
            .clock.restart()
        }

        .refreshDetails()
    }

    // Offers the available sound tracks without reserving label width in the transport bar.
    mtd showAudioTrackMenu()
    {
        let menu = MenuCtrl.createPopup(.audioButton, owner: me)
        var commands: Array'String
        commands.reserve(.video.audioTrackCount())
        for index in .video.audioTrackCount()
        {
            let sound = .video.audioTrack(index)!
            commands.add(videoAudioTrackCommand(index))
            menu.addItem(videoAudioTrackText(index, sound), commands[index].toString(), checked: index == .audioTrackIndex)
        }

        let rect   = .audioButton.surfaceRect()
        let chosen = menu.doModal({rect.horzCenter(), rect.y}, .AnchorBottomCenter, autoDestroy: true)
        if !chosen do
            return

        for index in .video.audioTrackCount() where chosen! == commands[index].toString()
        {
            catch .selectAudioTrack(index) as trackError
            if trackError != null and .reportFailure do
                .reportFailure!(me, Errors.message(trackError))
            return
        }
    }

    // Sizes the run-ahead queue from the picture size.
    //
    // The queue has to cover the longest gap the decoder can leave, which is one key picture,
    // and every slot costs a whole frame of memory. Bounding it by bytes rather than by count
    // gives a small stream a deep queue and a 4K stream one that still covers that gap.
    mtd prepareSlots()
    {
        // A planar picture costs half of what the packed one would, so the same budget buys twice
        // the run-ahead on exactly the streams whose key pictures are the most expensive.
        let bytes = cast(u64) .video.width() * cast(u64) .video.height() * (.planar ? 3 : 6) / 2
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
        var notify: bool
        {
            Sync.scopedLock(&.queueLock)
            if .anchorPending and .produceFrom == index and !.hasFailure do
                return

            notify = .hasFrame and !.awaitingFrame
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

        if notify and .reportLoadingChanged do
            .reportLoadingChanged!(me)
    }

    // Decodes one picture into a slot, and answers with the error the stream raised, if any.
    //
    // A codec that reconstructs planes hands them over as they are; one that does not produces the
    // packed picture itself. Only the queue knows which of the two a slot holds.
    private mtd decodeIntoSlot(slot: u32, index: u64)->#null any
    {
        if .planar
        {
            catch .video.decodeFramePlanesInto(&.slots[cast(u64) slot].planes, index) as planarError
            return planarError
        }

        catch .video.decodeFrameInto(&.slots[cast(u64) slot].image, index) as packedError
        return packedError
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
            let count = .video.frameCount()
            if count and .nextDecode >= count do
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

        let decodeError = .decodeIntoSlot(slot, index)

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
        while .produceOne() {}
    }

    // Publishes the queued picture the clock is on, and reports whether one reached the screen.
    //
    // Every decoded picture is presented while playback keeps up: the decoder is asked only for
    // the pictures playback intends to show, so a queued one is never obsolete, and presenting
    // them in order is what keeps motion smooth when the clock has run ahead.
    //
    // Past that, one picture per call is a ceiling, and the caller is the event loop of the
    // application: one turn of that loop presents the window, which costs tens of milliseconds
    // whenever the compositor is busy. A stream asking for more pictures than the loop turns
    // would then fall behind by the difference for as long as it plays — silently, since the
    // queue stays full and nothing looks starved. `catchUpTo` names the last picture the clock
    // has reached: everything before it is released unshown, so the picture stays on the clock
    // and the loss is bounded to pictures whose time has already gone.
    mtd publishHead(catchUpTo: u64 = 0, catchUp = false)->bool
    {
        var chosen = VideoNoSlot
        var failure: String
        {
            Sync.scopedLock(&.queueLock)
            if .ready.count
            {
                while catchUp and .ready.count > 1 and .slots[cast(u64) .ready[1]].index <= catchUpTo
                {
                    .freeSlots.add(.ready[0])
                    .ready.removeAtOrdered(0)
                }

                chosen = .ready[0]
                .ready.removeAtOrdered(0)
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
                .elapsed = .audio!.timelineStartSeconds() + .voice!.playbackPositionSeconds()
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

        let notifyLoading = .awaitingFrame
        .frameIndex    = .slots[cast(u64) chosen].index
        .hasFrame      = true
        .awaitingFrame = false
        catch .finishMetadata() as metadataError
        if metadataError != null and .reportFailure
        {
            .reportFailure!(me, Errors.message(metadataError))
            return false
        }

        if .anchorPending
        {
            // A jump moved the producer, so the silent clock follows the picture that came back
            // rather than the position it asked for. Sound is the master clock when there is
            // one, and its timeline is never moved to conceal video decode latency.
            .anchorPending = false
            if .playing
            {
                .elapsed = .frameSeconds(.frameIndex)
                if !.voice do
                    .clock.restart()
            }
        }

        if .planar
        {
            let picture = .slots[cast(u64) chosen].planes.view()
            .imageView.updateVideoFrame(&picture)
        }
        else
        {
            .imageView.exchangeImage(&.slots[cast(u64) chosen].image)
        }

        {
            Sync.scopedLock(&.queueLock)
            .freeSlots.add(chosen)
        }

        .decodeWake.signal()
        .refreshTransport()
        if notifyLoading and .reportLoadingChanged do
            .reportLoadingChanged!(me)

        // A transport seek holds the audio clock until its target picture is on screen. This
        // avoids showing the previous picture while sound has already jumped to the new time.
        if .resumeAudioAfterSeek do
            .resumeAudio()
        return true
    }

    // Positions playback on one picture and asks the producer for it.
    mtd showFrame(index: u64)->bool
    {
        let count = .video.frameCount()
        if count and index >= count do
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
        let count = .video.frameCount()
        if !count and .video.durationInSeconds() <= 0 do
            return
        let target      = count ? Math.min(index, count - 1) : index
        let resumeAudio = .playing and .voice != null
        .resumeAudioAfterSeek = resumeAudio
        if resumeAudio do
            catch .voice!.pause()
        if .playing do
            .clock.reset()
        .elapsed = .frameSeconds(target)

        // Position sound before publishing a picture that may already be queued. Otherwise an
        // immediate publish can resume the old sample position and leave the clocks separated.
        if .voice and .audio
        {
            let coversRange = videoSoundCovers(.audio!, .elapsed)
            .audioRangePending = !coversRange
            if coversRange
            {
                let sample = videoSoundSample(.audio!, .elapsed)
                catch .voice!.seekSampleFrame(sample) as seekError
                if seekError != null
                {
                    .resumeAudioAfterSeek = false
                    .playing              = false
                    .audioRangePending    = false
                    catch .voice!.pause()
                    if .reportFailure do
                        .reportFailure!(me, Errors.message(seekError))
                    return
                }
            }
        }

        if !.showFrame(target) do
            return
        .refreshTransport()
        if .resumeAudioAfterSeek and .frameIndex == target do
            .resumeAudio()

        .audioClockLast = -1
    }

    mtd togglePlayback()
    {
        if !.hasFrame do
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
            let count = .video.frameCount()
            if count and .frameIndex + 1 >= count
            {
                .elapsed = 0
                discard .showFrame(0)
                if .voice do
                    catch .voice!.seekSampleFrame(0)
            }

            .audioClockLast = -1
            .clock.restart()
            .playing = true
            .resumeAudio()
            if !.playing do
                return
            .decodeWake.signal()
        }

        .refreshTransport()
    }

    mtd stopPlayback()
    {
        if !.hasFrame do
            return
        .playing              = false
        .resumeAudioAfterSeek = false
        .audioRangePending    = false
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
        if !.openFinished
        {
            catch .completeOpen() as openError
            if openError != null and .reportFailure do
                .reportFailure!(me, Errors.message(openError))
            return
        }

        if !.video.isOpen() do
            return

        catch .finishMetadata() as metadataError
        if metadataError != null and .reportFailure
        {
            .reportFailure!(me, Errors.message(metadataError))
            return
        }

        if !.playing
        {
            discard .publishHead()
            return
        }

        .followAudioClock()
        if .audioRangePending and .audio and videoSoundCovers(.audio!, .currentSeconds()) do
            .resumeAudio()

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
            // While playback keeps up the clock only gates when the next picture is due; past
            // that it also decides how many of the queued ones are already too late to show.
            if .anchorPending or head <= clock do
                discard .publishHead(clock, !.anchorPending)
            return
        }

        let count = .video.frameCount()
        if count and clock >= count and .frameIndex + 1 >= count
        {
            .playing              = false
            .resumeAudioAfterSeek = false
            .audioRangePending    = false
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
        if (count and sync >= count) or sync - clock > cap do
            return

        .repositionTo(sync)
        .decodeWake.signal()
    }
}

private impl IWnd for VideoViewer
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .timer
        {
            evt.accepted = false
            return
        }

        .updatePlayback()
        if !.isPendingDestroy do
            .refreshTime()
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        .retireBlocking()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed or evt.modifiers != .None
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .Space, .MediaPlayPause: .togglePlayback()
        case .Left:                   .seekRelative(-VideoSeekSeconds)
        case .Right:                  .seekRelative(VideoSeekSeconds)
        case .M, .VolumeMute:         .setMuted(!.muted)
        case .MediaStop:              .stopPlayback()
        default:                      evt.accepted = false
        }
    }
}

private impl VideoViewer
{
    mtd refreshDetails()
    {
        let duration = .video.durationInSeconds()
        .details = Format.toString(videoStrings().ui_Details, .video.width(), .video.height(), videoFrameCountText(.video.frameCount()), .video.frameRate().framesPerSecond(), mediaDurationText(duration))
        if .audio do
            .details = Format.toString("% · %", .details.toString(), videoAudioDetailsText(.audio!).toString())
        if .reportDetails do
            .reportDetails!(me, .details.toString())
    }

    // Publishes the reader opened by the background worker and starts picture production. This
    // method runs only on the GUI timer, so no window or audio object is ever touched off-thread.
    mtd completeOpen() fail
    {
        if .openFinished do
            return

        let state = Atomic.get(&.openState)
        if !state do
            return
        if state == 2
        {
            // Failure exits the worker. Join only after termination, so reporting the error can
            // retire the view without ever turning this poll into a wait.
            if .decodeThread.isValid() and !.decodeThread.isDone() do
                return
            if .decodeThread.isValid() do
                .decodeThread.wait()
        }

        .openFinished = true
        if .openFailure.length do
            fail InvalidFormatError{Errors.mkString(.openFailure.toString())}

        .video  = #move .pendingVideo
        .planar = .video.hasPlanarFrames()
        .prepareSlots()
        try .finishMetadata()

        .refreshTransport()
        .refreshDetails()
        discard .showFrame(0)
        if .reportLoadingChanged do
            .reportLoadingChanged!(me)
    }

    mtd finishMetadata() fail
    {
        let duration = .video.durationInSeconds()
        let rate     = .video.frameRate().framesPerSecond()
        let count    = .video.frameCount()
        if !.timelineReady
        {
            let step = rate > 0 ? 1 / rate : 0.01
            if duration > 0 do
                .timeline.setBounds(0, duration, cast(f32) Math.min(step, duration / 100))
            .timeline.enable(duration > 0 and (!count or count > 1))
            .timelineReady = true
        }

        if !.metadataReady and count
        {
            .metadataReady = true

            let step = rate > 0 ? 1 / rate : 0.01
            if duration > 0 do
                .timeline.setBounds(0, duration, cast(f32) Math.min(step, duration / 100))
            .timeline.enable(duration > 0 and count > 1)
            .refreshDetails()
        }

        let audioCount = .video.audioTrackCount()
        if !.audioReady and audioCount
        {
            .audioReady = true
            .audioButton.enable(audioCount > 1)
            .muteButton.enable(true)
            .volumeSlider.enable(true)
            if !acquireSoundEngine() do
                fail UnsupportedFormatError{"cannot create the audio engine for video playback"}
            .audioEngineAcquired = true
            .selectAudioTrack(0)
        }
        elif .audioReady
        {
            let sound = .video.audioTrack(.audioTrackIndex)
            if sound and sound != .audio do
                .selectAudioTrack(.audioTrackIndex)
        }
    }

    func create(contentParent, commandParent: *Wnd, fileName: string, reportDetails: #null ViewerReportDetails = null, reportFailure: #null ViewerReportFailure = null, reportLoadingChanged: #null ViewerReportLoadingChanged = null)->*VideoViewer fail
    {
        registerVideoStrings(contentParent.app())
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

        result.backgroundStyle      = .View
        result.reportDetails        = reportDetails
        result.reportFailure        = reportFailure
        result.reportLoadingChanged = reportLoadingChanged

        result.commands = ViewerCommandBar.create(commandParent, 0)

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
            .margin.x  = 4
            .toolTip   = videoStrings().ui_TipStop
            .enable(false)
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.stopPlayback()
            }
        }

        with result.backwardButton = IconButton.create(result.commands, result.commands.icon(.SeekBackward, VideoGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 4
            .toolTip    = videoStrings().ui_TipBackward
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.seekRelative(-VideoSeekSeconds)
            }
        }

        with result.forwardButton = IconButton.create(result.commands, result.commands.icon(.SeekForward, VideoGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 4
            .toolTip    = videoStrings().ui_TipForward
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.seekRelative(VideoSeekSeconds)
            }
        }

        with result.audioButton = IconButton.create(result.commands, result.commands.icon(.AudioTracks, VideoGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle = .Right
            .toolTip   = videoStrings().ui_TipAudio
            .enable(false)
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.showAudioTrackMenu()
            }
        }

        with result.volumeSlider = Slider.create(result.commands, {0, 0, 96, 36})
        {
            .dockStyle = .Right
            .margin    = {0, 1, 8, 1}
            .toolTip   = videoStrings().ui_TipVolume
            .setBounds(0, 1, 0.05)
            .setValueWithoutGesture(1)
            .enable(false)
            .sigChanged += func|view = result|(slider)
            {
                view.setVolume(slider.value())
            }
        }

        with result.muteButton = IconButton.create(result.commands, result.commands.icon(.Volume, VideoGlyphSize), {0, 0, 36, 36}, flags: .Toggle)
        {
            .dockStyle = .Right
            .margin.x  = 8
            .toolTip   = videoStrings().ui_TipMute
            .setCheckIndicator(.Frame)
            .enable(false)
            .sigCheckedChanged += func|view = result|(button)
            {
                view.setMuted(button.isChecked)
            }
        }

        with result.timeLabel = Label.create(result.commands, "", {0, 0, 112, 36}, null, .SecondaryText)
        {
            .dockStyle = .Right
            .margin.x  = 8
            .setTextAlignment(.Right, .Center)
        }

        with result.timeline = Slider.create(result.commands, {0, 0, 0, 36})
        {
            .dockStyle = .Center
            .margin    = {12, 1, 12, 1}
            .toolTip   = videoStrings().ui_TipSeek

            // A drag may cross hundreds of frames. Decode its final position once instead of
            // serially decoding every intermediate value queued by the pointer movement.
            .sigStartChange += func|view = result|(slider)
            {
                discard slider
                view.timelineChanging = true
            }
            .sigEndChange += func|view = result|(slider)
            {
                view.timelineChanging = false
                view.seekSeconds(slider.value())
            }
        }

        result.imageView           = ImageView.create(result)
        result.imageView.dockStyle = .Center
        result.style.setStyleSheetColors(VideoBackdropColors)
        result.imageView.style.setStyleSheetColors(VideoBackdropColors)

        result.playButton.enable(false)
        result.timeline.enable(false)
        result.refreshTransport()
        result.openFileName = fileName
        result.decodeWake.init()
        try result.decodeThread.init(&runVideoViewerDecode, result, priority: .BelowNormal)
        try result.decodeThread.start()
        result.timer = result.addTimer(10'ms)
        result.applyLayout()
        result.setInitialFocus(result.playButton)
        return result
    }
}

// Opens the container and keeps its run-ahead queue full on the same persistent thread. Keeping
// both phases on one runtime context avoids moving codec allocations between thread caches.
private func runVideoViewerDecode(thread: Threading.Thread)
{
    let view  = cast(*VideoViewer) thread.userParam!
    var video = catch Reader.open(view.openFileName.toString()) as openError
    if openError != null
    {
        view.openFailure = Errors.message(openError)
        Atomic.exchange(&view.openState, 2)
        return
    }

    if thread.requestEnd
    {
        video.close()
        return
    }

    view.pendingVideo = #move video
    Atomic.exchange(&view.openState, 1)
    while !thread.requestEnd
    {
        view.decodeWake.wait()
        while !thread.requestEnd and view.produceOne() {}
    }

    // `Reader.close` joins codec-owned frame and indexing threads. It can take as long as a key
    // picture, so it belongs to this worker rather than the GUI retirement poll.
    view.slots.clear()
    view.ready.clear()
    view.freeSlots.clear()
    if view.openFinished do
        view.video.close()
    else do
        view.pendingVideo.close()
}

private func loadVideoViewer(contentParent, commandParent: *Wnd, fileName: string, reportDetails: #null ViewerReportDetails, reportFailure: #null ViewerReportFailure, reportLoadingChanged: #null ViewerReportLoadingChanged)->#null *VideoViewer fail => try VideoViewer.create(contentParent, commandParent, fileName, reportDetails, reportFailure, reportLoadingChanged)

// Creates the integrated video playback view.
func createVideoViewer(request: const *ViewerRequest, result: *ViewerResult)
{
    let view = catch loadVideoViewer(request.contentParent, request.commandParent, request.fileName, request.reportDetails, request.reportFailure, request.reportLoadingChanged) as decodeError
    if decodeError != null
    {
        result.failureReason = Errors.message(decodeError)
        return
    }

    result.view      = view
    result.commands  = view!.commands
    result.details   = view!.details
    result.retire    = func(wnd)->bool { return (cast(*VideoViewer) wnd).retire() }
    result.isLoading = func(wnd)->bool
    {
        let videoView = cast(*VideoViewer) wnd
        return !videoView.openFinished or videoView.awaitingFrame
    }
    result.needsLoadingOverlay = func(wnd)->bool { return !(cast(*VideoViewer) wnd).hasFrame }
}
