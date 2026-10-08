#global internal
#global namespace Viewers.Film

using Core, Pixel, Gui, Video, Audio

// Describes the movie player to the host.
//
// It offers itself for every container the video module can read, so a demuxer added there reaches
// the player without a list to update here.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "video"
        .staticName   = "Video"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Video)
        .create       = &createViewer
        .smokeFixture = "glint-aac-mjpeg.mp4"
    }

    for format in Reader.decodableFormats() do
        result.addSelectors(format.extensions)
    return result
}

private
{
    const SeekSeconds  = 10.0
    const CommandWidth = 1080.0
    const NoSubtitle   = Swag.U32.Max

    // The playback rates the settings menu offers. XAudio2 creates every voice with the default
    // maximum frequency ratio of two, so 2x is the fastest rate the sound can follow.
    const PlaybackRates: [7] f64 = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    // How far behind the clock playback is allowed to fall before it gives up and jumps.
    //
    // Showing every decoded picture keeps motion smooth, but on a stream the machine cannot sustain
    // it also falls behind for as long as it plays. Past this much, playback skips to the next sync
    // frame, which is the one place a jump costs a single decoded picture rather than the decode of
    // every picture in between.
    const ResyncSeconds = 2.0

    // How far the picture may drift from the sound before the timeline is pulled back onto it.
    //
    // The sound is the master clock, but reading its position on every tick and following it exactly
    // would jitter the presentation by the size of one output buffer. Playback therefore runs its own
    // clock and only re-anchors it when the two have actually separated.
    const AudioDriftSeconds = 0.1
    const BackdropColors    = "view_Bk 0xFF000000"

    // How far past the clock a resync jump may land.
    //
    // A stream whose sync frames are seconds apart would turn a resync into a scene change; past
    // this bound the player keeps walking below speed instead of teleporting.
    const ResyncMaxJumpSeconds = 15.0

    // How many pictures the queue holds again before the clock restarts after a jump.
    //
    // A decoder that has just restarted on a key picture has nothing in hand, and starting the
    // clock on the first one it produces asks it for real time from a standing start: it falls
    // behind within the second and jumps again, which is a stutter that feeds itself. Waiting for a
    // few pictures costs a fraction of a second once and buys a queue to play out of.
    const RebufferPictures = 4'u64

    // How much memory the decoded run-ahead may hold, and how many pictures it may hold at all.
    //
    // A frame-threaded decoder delivers pictures in runs separated by the cost of one key picture,
    // which at 4K is well over a hundred milliseconds. The queue exists to cover exactly that gap,
    // so it is sized in bytes: a 4K stream gets the few pictures that cover it, and a small stream
    // gets a deeper one for the same memory.
    const PrefetchBytes = 64 * 1024 * 1024'u64
    const PrefetchMax   = 12'u64
    const PrefetchMin   = 2'u64

    // Names the absence of a queue slot.
    const NoSlot = Swag.U32.Max

    // What the opening worker publishes in `openState`: still running, opened, or failed.
    const OpenRunning   = 0'u32
    const OpenSucceeded = 1'u32
    const OpenFailed    = 2'u32
}

// Returns the decoded-picture count that fits the run-ahead budget.
func prefetchSlotCount(width, height: s32, planar: bool)->u32
{
    let bytes = cast(u64, width) * cast(u64, height) * (planar ? 3 : 6) / 2
    let count = bytes ? PrefetchBytes / bytes : PrefetchMax
    return cast(u32, Math.clamp(count, PrefetchMin, PrefetchMax))
}

// Returns the queue depth required after a seek without exceeding the available slots.
func rebufferPictureCount(slotCount: u32)->u64 => Math.min(RebufferPictures, cast(u64, slotCount))

// Reports whether the samples indexed so far reach the movie time `seconds`.
func soundCovers(sound: const *SoundFile, seconds: f64)->bool
{
    let local = seconds - sound.timelineStartSeconds()
    if local < 0 do
        return false
    let wanted = cast(u64, Math.ceil(local * cast(f64, sound.sampleRateHz())))
    return wanted < sound.sampleFrameCount()
}

// Returns the sample frame that plays at the movie time `seconds`, counted from the sound's own timeline start.
func soundSample(sound: const *SoundFile, seconds: f64)->u64
{
    let local = Math.max(seconds - sound.timelineStartSeconds(), 0)
    return cast(u64, Math.round(local * cast(f64, sound.sampleRateHz())))
}

// Menu identifiers of the audio track, playback speed, and subtitle track choices.
private func audioTrackCommand(index: u32)->String => Format.toString("scope.video.audioTrack.%", index)

private func playbackRateCommand(index: u32)->String => Format.toString("scope.video.player.speed.%", index)

private func subtitleTrackCommand(sidecar: bool, index: u32)->String => Format.toString(sidecar ? "scope.video.subtitle.sidecar.%" : "scope.video.subtitle.embedded.%", index)

// Names one selectable playback rate; the source rate keeps its word rather than a number.
private func playbackRateText(rate: f64)->String => rate == 1 ? texts().ui_PlayerSpeedNormal : Format.toString("%×", rate)

// One decoded picture of the run-ahead queue.
//
// A codec reconstructs planar 4:2:0 and the renderer converts where it draws, so a queued picture
// is the planes themselves. That is both the cheaper decode and the smaller queue: three planes
// are half the bytes of the packed picture they would have become.
struct Slot
{
    planes: PlanarFrame
    image:  Image     // Used only by a stream whose codec does not reconstruct planes.
    index:  u64
}

// Plays a movie with its sound and subtitle tracks, decoding pictures ahead of the clock on a worker thread.
#[Swag.NoCopy]
struct Panel
{
    using wnd: Wnd

    late
    {
        commands:        *Wnd
        playButton:      *IconButton
        stopButton:      *IconButton
        backwardButton:  *IconButton
        forwardButton:   *IconButton
        timeline:        *Slider
        timeLabel:       *Label
        speedButton:     *IconButton
        playModeButton:  *Viewer.PlaybackButton
        audioButton:     *IconButton
        subtitleButton:  *IconButton
        muteButton:      *IconButton
        volumeSlider:    *Slider
        imageView:       *ImageView
        subtitleOverlay: *SubtitleOverlay
        information:     *MediaInfoPanel
    }

    seekOverlay: *SeekOverlay?

    // Opening and decoding run on the same persistent worker, preserving codec allocator and
    // thread affinity. `openState` holds one of the `Open` states.
    openFileName:         String
    pendingVideo:         Reader
    openFailure:          String
    openState:            u32
    openFinished:         bool
    informationReady:     bool
    informationFrames:    u64
    informationAudio:     u32
    informationSubtitles: u32

    // Opening retains bounded metadata while progressive indexes and payloads stay in the file.
    video:               Reader
    planar:              bool     // The codec hands its pictures over without converting them.
    audio:               const *SoundFile?
    voice:               *Voice?
    audioTrackIndex:     u32
    audioEngineAcquired: bool
    subtitleSource:      SubtitleSource
    subtitleTrackIndex:  u32 = NoSubtitle
    subtitleReady:       bool
    subtitleLastSeconds: f64 = -1
    subtitleNextChange:  f64

    // Decoded pictures waiting for their turn on screen.
    //
    // A frame-threaded decoder does not deliver one picture every so many milliseconds: it
    // delivers a run of them and then spends a hundred milliseconds or more on the next key
    // picture, which arrives once a second and blocks every picture that predicts from it.
    // Presenting straight off the decoder therefore stutters even when the average rate is
    // several times what the clock asks for. The run-ahead absorbs that: the decoder fills the
    // queue while it is fast and the clock drains it while the key picture is being decoded.
    slots:     Array'Slot
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
    //
    // Both sides of this queue mutate it. Fixed storage keeps a decoder thread from reallocating
    // an array owned by the GUI allocator when the queue grows from two entries to four.
    ready:       StaticArray'(u32, PrefetchMax)
    freeSlots:   StaticArray'(u32, PrefetchMax)
    nextDecode:  u64     // Frame the producer takes next.
    produceFrom: u64     // Frame the producer was last aimed at.
    inFlight:    u32     // Pictures being decoded right now.
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

    timer:            *Timer?
    clock:            Time.Stopwatch
    elapsed:          f64
    frameIndex:       u64
    playing:          bool
    autoPlayPending:  bool = true
    muted:            bool
    playbackRate:     f64  = 1
    volume:           f32  = 1
    details:          String
    metadataReady:    bool
    audioReady:       bool
    timelineReady:    bool
    timelineChanging: bool
    services:         Viewer.HostServices
    retireRequested:  bool
    retired:          bool

    // Pixel column the timeline thumb was last pushed to, so a value that would not move it is
    // not pushed at all.
    timelinePixel: s32 = -1
}

private impl Panel
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
            catch .voice.stop()
            .voice.destroy()
            .voice = null
        }

        if .audioEngineAcquired
        {
            Sound.releaseEngine()
            .audioEngineAcquired = false
        }

        .pendingVideo.close()
        .video.close()
        .retired = true
    }

    // Requests teardown, and reports whether deferred GUI destruction may release this view.
    mtd retire()->bool
    {
        if .retired do
            return true
        if not .retireRequested
        {
            .retireRequested = true
            .stopTimer(&.timer)

            // A voice borrows its SoundFile from the reader. Release it before the decoder
            // thread closes that reader in the background.
            if .voice
            {
                catch .voice.stop()
                .voice.destroy()
                .voice = null
                .audio = null
            }

            if .audioEngineAcquired
            {
                Sound.releaseEngine()
                .audioEngineAcquired = false
            }

            if .decodeThread.isValid()
            {
                .video.requestCancel()
                .decodeThread.safeForceEnd()
                .decodeWake.signal()
            }
        }

        if .decodeThread.isValid() and not .decodeThread.isDone() do
            return false
        .finishRetire()
        return true
    }

    // Tears the view down for window destruction, which, unlike file selection, may wait for the decoder thread.
    mtd retireBlocking()
    {
        discard .retire()
        .finishRetire()
    }

    mtd retranslate()
    {
        .playButton.toolTip     = .playing ? texts().ui_TipPause : texts().ui_TipPlay
        .stopButton.toolTip     = texts().ui_TipStop
        .backwardButton.toolTip = texts().ui_TipBackward
        .forwardButton.toolTip  = texts().ui_TipForward
        .timeline.toolTip       = texts().ui_TipSeek
        .muteButton.toolTip     = texts().ui_TipMute
        .volumeSlider.toolTip   = texts().ui_TipVolume

        .audioButton.toolTip    = texts().ui_TipAudio
        .subtitleButton.toolTip = texts().ui_TipSubtitles
        .speedButton.toolTip    = texts().ui_TipPlaybackSpeed

        .refreshDetails()
    }
}

impl Panel
{
    mtd frameSeconds(index: u64)->f64 => .video.frameTimestamp(index)

    // Reports whether the file is still opening or a requested picture has not reached the screen.
    mtd isLoading()->bool => not .openFinished or .awaitingFrame

    // Reports whether the host should cover the view: no picture has been shown yet, or a requested one is still decoding.
    mtd needsLoadingOverlay()->bool => not .hasFrame or .awaitingFrame

    // Returns the playback position in source seconds.
    mtd currentSeconds()->f64
    {
        if not .playing do
            return .elapsed
        return .elapsed + cast(f64, .clock.elapsedMicroseconds()) / 1_000_000.0 * .playbackRate
    }

    // Changes the playback rate while keeping the current position and time labels in source time.
    //
    // The silent clock and the sound scale together: the voice consumes source samples at this
    // ratio, so the position it reports keeps advancing in source seconds and the ordinary drift
    // correction stays valid. Pitch follows the rate, since the voice resamples without preserving it.
    mtd setPlaybackRate(rate: f64)
    {
        if rate == .playbackRate do
            return

        // Re-anchor first, so the time already spent on the old rate is not replayed at the new one.
        .elapsed = .currentSeconds()
        if .playing do
            .clock.restart()
        .playbackRate = rate

        // A backend that refuses the ratio keeps playing at 1x, and the audio clock then simply
        // keeps correcting the picture back onto the sound.
        if .voice do
            catch .voice.setFrequencyRatio(cast(f32, rate))
        .refreshDetails()
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
        if not .playing or not .voice or .audioRangePending or .resumeAudioAfterSeek do
            return

        let position = .audio!.timelineStartSeconds() + .voice.playbackPositionSeconds()
        if position == .audioClockLast do
            return

        .audioClockLast = position
        if Math.abs(position - .currentSeconds()) <= AudioDriftSeconds do
            return

        .elapsed = position
        .clock.restart()
    }

    // Starts the sound at the current position and takes the clock from it. Waits instead while the
    // decoded audio does not cover that position, and reports a failure when the device cannot seek
    // or play.
    mtd resumeAudio()
    {
        if not .voice or not .audio
        {
            .resumeAudioAfterSeek = false
            return
        }

        if not soundCovers(.audio, .currentSeconds())
        {
            .audioRangePending = true
            return
        }

        if .resumeAudioAfterSeek
        {
            let sample = soundSample(.audio, .currentSeconds())
            catch .voice.seekSampleFrame(sample) as seekError
            if seekError != null
            {
                .resumeAudioAfterSeek = false
                .playing = false
                .audioRangePending    = false
                catch .voice.pause()
                .services.failed(me, Errors.message(seekError))
                return
            }
        }

        .resumeAudioAfterSeek = false
        .audioRangePending    = false
        catch .voice.play() as playError
        if playError != null
        {
            .playing = false
            .refreshTransport()
            .services.failed(me, Errors.message(playError))
            return
        }

        .audioClockLast = .audio.timelineStartSeconds() + .voice.playbackPositionSeconds()
        .elapsed        = .audioClockLast
        .clock.restart()
    }

    mtd refreshTransport()
    {
        .playButton.setIcon(.theme().icon(.playing ? .Pause : .Play, themeActionIconSize(.themeMetrics())))
        .playButton.toolTip = .playing ? texts().ui_TipPause : texts().ui_TipPlay
        .playButton.enable(.hasFrame)
        .stopButton.enable(.hasFrame and (.frameIndex != 0 or .playing))
        .refreshTime()
    }

    // Updates the time label and the timeline thumb. The thumb moves only by whole pixels and never
    // while the user drags it.
    mtd refreshTime()
    {
        let duration = cast(f64, .video.durationInSeconds())
        let seconds  = Math.clamp(.currentSeconds(), 0, duration)

        // Push the thumb only where it would actually move. A timeline is a couple of thousand
        // pixels at most and a recording is hours long, so one pixel of travel is seconds of
        // playback: pushed on every tick the slider invalidates a hundred times a second for a
        // position nobody can tell apart. What that costs is not the slider — it is that the
        // repainted region then spans from the command bar to the picture, so the surface repaints
        // its whole hierarchy and chrome instead of the one view that changed.
        if not .timelineChanging
        {
            let width = .timeline.position.width
            if duration <= 0 or width <= 0
            {
                .timeline.setValueWithoutGesture(cast(f32, seconds))
            }
            else
            {
                let pixel = cast(s32, (seconds / duration * cast(f64, width)))
                if pixel != .timelinePixel
                {
                    .timelinePixel = pixel
                    .timeline.setValueWithoutGesture(cast(f32, seconds))
                }
            }
        }

        .timeLabel.setText(Viewer.timeRangeText(seconds, duration))
    }

    mtd seekSeconds(seconds: f64)
    {
        let duration = cast(f64, .video.durationInSeconds())
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
        if not .seekOverlay do
            .seekOverlay = SeekOverlay.create(me)
        .seekOverlay.showSeek(seconds)
    }

    mtd setMuted(muted: bool)
    {
        .muted = muted
        .muteButton.setChecked(muted)
        .muteButton.setIcon(.theme().icon(muted ? .VolumeMute : .Volume, themeActionIconSize(.themeMetrics())))
        if .voice do
            catch .voice.setVolume(muted ? 0 : .volume)
    }

    mtd setVolume(volume: f32)
    {
        .volume = Math.clamp(volume, 0, 1)
        if .voice and not .muted do
            catch .voice.setVolume(.volume)
    }
}

private impl IWnd for Panel
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        switch evt.kind
        {
        case .LanguageChanged: .retranslate()
        case .ThemeChanged:    .subtitleOverlay.applySettings()
        default: evt.accepted = false
        }
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .timer
        {
            evt.accepted = false
            return
        }

        .updatePlayback()
        if not .isPendingDestroy
        {
            .finishSubtitles()
            .refreshTime()
            .refreshSubtitle()
        }
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
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
        case .Left:                   .seekRelative(-SeekSeconds)
        case .Right:                  .seekRelative(SeekSeconds)
        case .M, .VolumeMute:         .setMuted(not .muted)
        case .MediaStop:              .stopPlayback()
        default:                      evt.accepted = false
        }
    }
}

private impl Panel
{
    // Refreshes the snapshot when progressive indexing discovers stream or track properties.
    mtd refreshInformation()
    {
        if not .video.isOpen() do
            return
        let frames    = .video.frameCount()
        let audio     = .video.audioTrackCount()
        let subtitles = .video.subtitleTrackCount()
        if .informationReady and frames == .informationFrames and audio == .informationAudio and subtitles == .informationSubtitles do
            return
        .informationReady     = true
        .informationFrames    = frames
        .informationAudio     = audio
        .informationSubtitles = subtitles

        var data: MediaInfoData
        data.add(.Video, group: true)
        data.add(.Format, .video.streamFormat().name)
        data.add(.Dimensions, Format.toString("% × % px", .video.width(), .video.height()))
        data.add(.DisplaySize, Format.toString("% × % px", .video.displayWidth(), .video.displayHeight()))
        let rate = .video.frameRate()
        data.add(.FrameRate, Format.toString("% fps", rate.framesPerSecond()))
        if frames do
            data.add(.Frames, Format.toString("%", frames))
        if .video.durationInSeconds() > 0 do
            data.add(.Duration, Viewer.durationText(.video.durationInSeconds()))
        data.add(.Audio, Format.toString("%", audio))
        data.add(.Subtitles, Format.toString("%", subtitles))
        for index in audio
        {
            let track = .video.audioTrack(index)
            if not track do
                continue
            data.add(.Audio, Format.toString("%", index + 1), group: true)
            if track.displayName().count do
                data.add(.Name, track.displayName())
            if track.language().count do
                data.add(.Language, track.language())
            data.add(.Encoding, Format.toString("%", track.sampleEncoding()))
            data.add(.SampleRate, Format.toString("% Hz", track.sampleRateHz()))
            data.add(.Channels, Format.toString("%", track.numChannels()))
        }

        for index in subtitles
        {
            let track = .video.subtitleTrack(index)
            if not track do
                continue
            data.add(.Subtitles, Format.toString("%", index + 1), group: true)
            if not track.name.isEmpty() do
                data.add(.Name, track.name)
            if not track.language.isEmpty() do
                data.add(.Language, track.language)
            data.add(.Format, Format.toString("%", track.format))
        }

        .information.publish(&data)
    }

    // Rebuilds the host summary in the active language and reports it.
    mtd refreshDetails()
    {
        .details = Format.toString(texts().ui_Details, .video.width(), .video.height(), frameCountText(.video.frameCount()), .video.frameRate().framesPerSecond(), Viewer.durationText(.video.durationInSeconds()))
        if .audio do
            .details = Format.toString("% · %", .details, audioDetailsText(.audio))

        // An adjusted rate is part of what the reader is watching, so the summary declares it.
        if .playbackRate != 1 do
            .details = Format.toString("% · %", .details, playbackRateText(.playbackRate))
        .services.showDetails(me, .details)
    }

    // Publishes the reader opened by the background worker and starts picture production.
    //
    // This method runs only on the GUI timer, so no window or audio object is ever touched off-thread.
    mtd completeOpen() fail
    {
        if .openFinished do
            return

        let state = Atomic.get(&.openState)
        if state == OpenRunning do
            return
        if state == OpenFailed
        {
            // Failure exits the worker. Join only after termination, so reporting the error can
            // retire the view without ever turning this poll into a wait.
            if .decodeThread.isValid() and not .decodeThread.isDone() do
                return
            if .decodeThread.isValid() do
                .decodeThread.wait()
        }

        .openFinished = true
        if not .openFailure.isEmpty() do
            fail InvalidFormatError{Errors.mkString(.openFailure)}

        .video  = #move .pendingVideo
        .planar = .video.hasPlanarFrames()
        loadSidecars(.openFileName, &.subtitleOverlay.sidecars)
        .prepareSlots()

        // A stream whose samples are not square is stored with fewer columns than it is shown
        // with; the view stretches the picture back to the shape it was mastered in.
        .imageView.setDisplaySize(.video.displayWidth(), .video.displayHeight())
        try .finishMetadata()

        .refreshTransport()
        .refreshDetails()
        discard .showFrame(0)
        .services.loadingChanged(me)
    }

    // Applies what progressive indexing has discovered so far to the information panel, the timeline, the summary, and the sound.
    mtd finishMetadata() fail
    {
        .refreshInformation()
        let duration = .video.durationInSeconds()
        let rate     = .video.frameRate().framesPerSecond()
        let step     = rate > 0 ? 1 / rate : 0.01
        let count    = .video.frameCount()
        if not .timelineReady
        {
            if duration > 0 do
                .timeline.setBounds(0, duration, cast(f32, Math.min(step, duration / 100)))
            .timeline.enable(duration > 0 and (not count or count > 1))
            .timelineReady = true
        }

        if not .metadataReady and count
        {
            .metadataReady = true
            if duration > 0 do
                .timeline.setBounds(0, duration, cast(f32, Math.min(step, duration / 100)))
            .timeline.enable(duration > 0 and count > 1)
            .refreshDetails()
        }

        let audioCount = .video.audioTrackCount()
        if not .audioReady and audioCount
        {
            .audioReady = true
            .audioButton.enable(audioCount > 1)
            .muteButton.enable(true)
            .volumeSlider.enable(true)
            if not Sound.acquireEngine() do
                fail UnsupportedFormatError{texts().err_AudioEngine}
            .audioEngineAcquired = true
            try .selectAudioTrack(0)
        }
        elif .audioReady
        {
            let sound = .video.audioTrack(.audioTrackIndex)
            if sound and sound != .audio do
                try .selectAudioTrack(.audioTrackIndex)
        }
    }

    mtd finishSubtitles()
    {
        if .subtitleReady or not .video.isOpen() do
            return
        let subtitleCount = .video.subtitleTrackCount()
        if not subtitleCount and .subtitleOverlay.sidecars.isEmpty() do
            return

        .subtitleReady = true
        .subtitleButton.enable(true)
        .subtitleSource      = .subtitleOverlay.sidecars.isEmpty() ? .Embedded : .Sidecar
        .subtitleTrackIndex  = 0
        .subtitleLastSeconds = -1
    }

    // Creates the transport in the command group: transport and seek buttons with the clock on the
    // left, the rate, play-mode, track, and sound controls on the right, and the timeline between.
    mtd createTransportBar(playback: Viewer.PlaybackApi)
    {
        let buttonSize    = themeActionButtonSize(.themeMetrics())
        let dropDownWidth = themeDropDownButtonWidth(.themeMetrics())

        with .playButton = Viewer.createActionButton(.commands, .Play)
        {
            .dockStyle = .Left
            .toolTip   = texts().ui_TipPlay
            .enable(false)
            .sigPressed += func|view = me|(_) { view.togglePlayback() }
        }

        with .stopButton = Viewer.createActionButton(.commands, .Stop)
        {
            .dockStyle = .Left
            .margin.x  = 4
            .toolTip   = texts().ui_TipStop
            .enable(false)
            .sigPressed += func|view = me|(_) { view.stopPlayback() }
        }

        with .backwardButton = Viewer.createActionButton(.commands, .SeekBackward)
        {
            .dockStyle = .Left

            // Play/stop drive the transport and the two relative seeks move it: two families,
            // one block of air between them.
            .margin.x   = 16
            .toolTip    = texts().ui_TipBackward
            .sigPressed += func|view = me|(_) { view.seekRelative(-SeekSeconds) }
        }

        with .forwardButton = Viewer.createActionButton(.commands, .SeekForward)
        {
            .dockStyle  = .Left
            .margin.x   = 4
            .toolTip    = texts().ui_TipForward
            .sigPressed += func|view = me|(_) { view.seekRelative(SeekSeconds) }
        }

        with .timeLabel = Label.create(.commands, "", {0, 0, 112, 36}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .margin    = {8, 0, 8, 0}
            .setTextAlignment(.Right, .Center)
        }

        with .speedButton = Viewer.createActionDropDown(.commands, .PlaybackSpeed)
        {
            .dockStyle = .Right
            .margin.x  = 4
            .toolTip   = texts().ui_TipPlaybackSpeed
            .setArrowPosition(.RightUpward)
            .sigPressed += func|view = me|(_) { view.showPlaybackSpeedMenu() }
        }

        with .playModeButton = Viewer.PlaybackButton.create(.commands, me, playback)
        {
            .dockStyle = .Right
            .margin.x  = 4
        }

        with .audioButton = Viewer.createActionDropDown(.commands, .AudioTracks)
        {
            .dockStyle = .Right
            .toolTip   = texts().ui_TipAudio
            .setArrowPosition(.RightUpward)
            .enable(false)
            .sigPressed += func|view = me|(_) { view.showAudioTrackMenu() }
        }

        with .subtitleButton = IconButton.create(.commands, {}, {0, 0, dropDownWidth, buttonSize}, flags: .CenterContent)
        {
            .dockStyle = .Right
            .margin.x  = 4
            .toolTip   = texts().ui_TipSubtitles
            .setText("CC")
            .setArrowPosition(.RightUpward)
            .style.setFont(me.theme().createDefaultFont(10, .Bold), .Regular)
            .enable(false)
            .sigPressed += func|view = me|(_) { view.showSubtitleMenu() }
        }

        with .volumeSlider = Slider.create(.commands, {0, 0, 96, 36})
        {
            .dockStyle = .Right
            .margin    = {0, 1, 4, 1}
            .toolTip   = texts().ui_TipVolume
            .setBounds(0, 1, 0.05)
            .setValueWithoutGesture(1)
            .enable(false)
            .sigChanged += func|view = me|(slider) { view.setVolume(slider.value()) }
        }

        with .muteButton = Viewer.createActionButton(.commands, .Volume, .Toggle)
        {
            .dockStyle = .Right
            .margin.x  = 4
            .toolTip   = texts().ui_TipMute
            .setCheckIndicator(.Frame)
            .enable(false)
            .sigCheckedChanged += func|view = me|(button) { view.setMuted(button.isChecked) }
        }

        with .timeline = Slider.create(.commands, {0, 0, 0, 36})
        {
            .dockStyle = .Center
            .margin    = {8, 1, 8, 1}
            .toolTip   = texts().ui_TipSeek
            .enable(false)

            // A drag may cross hundreds of frames. Decode its final position once instead of
            // serially decoding every intermediate value queued by the pointer movement.
            .sigStartChange += func|view = me|(_)
            {
                view.timelineChanging = true
            }

            .sigEndChange += func|view = me|(slider)
            {
                view.timelineChanging = false
                view.seekSeconds(slider.value())
            }
        }
    }

    // Builds the video panel: commands, media information, transport bar, picture view and subtitle
    // overlay, then starts the decode thread and the playback timer. Fails when the decode thread
    // cannot start.
    func create(host: Viewer.Host)->*Panel fail
    {
        let services = host.services()

        with let result = Wnd.create'Panel(host.contentParent(), "scope.video")
        {
            .backgroundStyle = .View
            .services        = services
        }

        result.commands    = host.createCommandGroup(CommandWidth)
        result.information = MediaInfoPanel.create(host)
        result.createTransportBar(services.playback)

        result.imageView = ImageView.create(result)
        result.imageView.dockStyle = .Center
        result.style.setStyleSheetColors(BackdropColors)
        result.imageView.style.setStyleSheetColors(BackdropColors)
        result.subtitleOverlay = SubtitleOverlay.create(result)

        result.refreshTransport()
        result.openFileName = host.fileName()

        // The sound device comes online while the file opens, so the first picture does not
        // wait for it; see [[Sound.warmEngine]].
        Sound.warmEngine()
        result.decodeWake.init()
        try result.decodeThread.init(&runViewerDecode, result, priority: .Normal)
        try result.decodeThread.start()
        result.timer = result.addTimer(10'ms)
        result.applyLayout()
        result.setInitialFocus(result.playButton)
        return result
    }
}

// Opens the container and keeps its run-ahead queue full on the same persistent thread.
//
// Keeping both phases on one runtime context avoids moving codec allocations between thread caches.
private func runViewerDecode(thread: Threading.Thread)
{
    let view  = cast(*Panel, thread.userParam!)
    var video = catch Reader.open(view.openFileName) as openError
    if openError != null
    {
        view.openFailure = Errors.message(openError)
        Atomic.exchange(&view.openState, OpenFailed)
        return
    }

    if thread.requestEnd
    {
        video.close()
        return
    }

    view.pendingVideo = #move video
    Atomic.exchange(&view.openState, OpenSucceeded)
    while not thread.requestEnd
    {
        view.decodeWake.wait()
        while not thread.requestEnd and view.produceOne() {}
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

// Creates the integrated video playback view and connects it to the host.
func createViewer(host: Viewer.Host)
{
    catch
    {
        let view = try Panel.create(host)
        host.attachView(view)
        host.setDetails(view.details)

        with var lifecycle: Viewer.LifecycleApi
        {
            .retire    = func|view|()->bool => view.retire()
            .isLoading = func|view|()->bool => view.isLoading()
            .needsLoadingOverlay = func|view|()->bool => view.needsLoadingOverlay()
        }

        host.setLifecycle(lifecycle)
    } as createError
    if createError != null do
        host.reject(Errors.message(createError))
}
