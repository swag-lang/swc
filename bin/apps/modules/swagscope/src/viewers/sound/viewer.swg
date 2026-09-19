#global internal

using Core, Pixel, Gui, Audio, Threading

// Describes the waveform player to the host.
//
// It offers itself for every extension the audio module can decode, so a codec added there reaches
// the player without a list to update here.
func soundViewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "sound"
        .staticName   = "Sound"
        .attach       = &registerSoundStrings
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32) ViewerIcons.Sound
        .create       = &createSoundViewer
        .smokeFixture = "pacman_beginning.wav"
    }

    let extensions = SoundFile.decodableExtensions()
    result.addSelectors(extensions.toSlice())
    return result
}

private const SoundSeekSeconds  = 10.0
private const SoundCommandWidth = 820.0

// Slices the payload is reduced to. It is read back one column of pixels at a time, so it only
// has to stay ahead of the widest plot a window can give it; past that the columns repeat.
private const WaveformPointCount = 4096'u64

// Air around the plot, and the band the time scale is read in.
private const WaveformInsetX      = 24.0
private const WaveformInsetY      = 32.0
private const WaveformScaleHeight = 26.0
private const WaveformTickHeight  = 5.0

// Loudness of a slice, in the two readings a level meter carries: the transient that clips and the
// body the ear hears. Drawing both is what separates a waveform from a silhouette.
struct WaveformPoint
{
    peak: f32     // Loudest absolute level of the slice.
    body: f32     // Mean absolute level of the slice.
}

private var g_SoundEngineUsers:      u32
private var g_SoundViewerOwnsEngine: bool

// Creation of the audio engine started ahead of the first voice, on a runtime worker.
private var g_SoundEngineWarmUp:  Swag.Task
private var g_SoundEngineWarming: bool

// Starts creating the audio engine without waiting for it.
//
// Opening the output device is the better part of a second, and a player that only asks for
// the engine once its first picture is ready to be shown adds that second to the wait for
// the picture. Starting it here lets the device come online while the file is being opened
// and its first picture decoded; [[acquireSoundEngine]] then joins the work instead of doing
// it. Call it from the GUI thread, which is the only one that acquires the engine.
func warmSoundEngine()
{
    if g_SoundEngineWarming or g_SoundEngineUsers or isEngineCreated() do
        return

    g_SoundEngineWarming = true
    g_SoundEngineWarmUp.submit(func()
    {
        discard catch createEngine()
    })
}

// Takes a reference on the shared audio engine, creating it on first use, and reports whether the engine is available.
//
// Call [[releaseSoundEngine]] once for every successful acquisition.
func acquireSoundEngine(kind = DriverKind.Default)->bool
{
    if g_SoundEngineUsers
    {
        g_SoundEngineUsers += 1
        return true
    }

    if g_SoundEngineWarming
    {
        g_SoundEngineWarmUp.wait()
        g_SoundEngineWarming = false
        if isEngineCreated() do
            g_SoundViewerOwnsEngine = true
    }

    if not isEngineCreated()
    {
        catch createEngine(kind) as createError
        if createError != null do
            return false
        g_SoundViewerOwnsEngine = true
    }

    g_SoundEngineUsers = 1
    return true
}

// Drops a reference taken by [[acquireSoundEngine]], destroying the engine with the last one when a viewer created it.
func releaseSoundEngine()
{
    if not g_SoundEngineUsers do
        return
    g_SoundEngineUsers -= 1
    if g_SoundEngineUsers or not g_SoundViewerOwnsEngine do
        return
    destroyEngine()
    g_SoundViewerOwnsEngine = false
}

// Reads the PCM sample at `offset` as a level between -1 and 1, or 0 for an encoding that is not PCM.
func soundSample(bytes: const [..] u8, offset: u64, encoding: SoundFileEncoding)->f32
{
    switch encoding
    {
    case .Pcm8:
        return (cast(f32) bytes[offset] - 128) / 128

    case .Pcm16:
        let raw = cast(u16) bytes[offset] | (cast(u16) bytes[offset + 1] << 8)
        return cast(f32) cast #bit (s16) raw / 32768

    case .Pcm24:
        var raw = cast(u32) bytes[offset] | (cast(u32) bytes[offset + 1] << 8) | (cast(u32) bytes[offset + 2] << 16)
        if raw & 0x00800000 do
            raw |= 0xFF000000
        return cast(f32) cast #bit (s32) raw / 8388608

    case .Pcm32:
        let raw = cast(u32) bytes[offset] | (cast(u32) bytes[offset + 1] << 8) | (cast(u32) bytes[offset + 2] << 16) | (cast(u32) bytes[offset + 3] << 24)
        return cast(f32) cast #bit (s32) raw / 2147483648

    case .Float32:
        let raw = cast(u32) bytes[offset] | (cast(u32) bytes[offset + 1] << 8) | (cast(u32) bytes[offset + 2] << 16) | (cast(u32) bytes[offset + 3] << 24)
        return Math.clamp(cast #bit (f32) raw, -1, 1)
    }

    return 0
}

// Reduces an interleaved PCM payload to at most [[WaveformPointCount]] points, mixing its channels.
func buildWaveform(bytes: const [..] u8, encoding: SoundFileEncoding, channels: u32)->Array'WaveformPoint
{
    var result: retval
    if not bytes.count or not channels do
        return result

    let bytesPerSample = encoding == .Pcm8 ? 1'u64 : (encoding == .Pcm16 ? 2 : (encoding == .Pcm24 ? 3 : 4))
    let bytesPerFrame  = bytesPerSample * channels
    let frameCount     = bytes.count / bytesPerFrame
    let pointCount     = Math.min(frameCount, WaveformPointCount)
    if not pointCount do
        return result
    result.resize(pointCount)

    for point in pointCount
    {
        let first = point * frameCount / pointCount
        let last  = Math.max((point + 1) * frameCount / pointCount, first + 1)
        var peak  = 0'f32
        var sum   = 0'f32
        for frame in first until last
        {
            var mixed = 0'f32
            for channel in channels
            {
                let offset = frame * bytesPerFrame + channel * bytesPerSample
                mixed += soundSample(bytes, offset, encoding)
            }

            mixed /= channels
            let level = Math.abs(mixed)
            peak = Math.max(peak, level)
            sum  += level
        }

        result[point] = {peak, sum / cast(f32) (last - first)}
    }

    return result
}

// Formats the length of a sound for the host summary: milliseconds below one second, seconds with two decimals from there on.
func soundDurationText(seconds: f32)->String
{
    if seconds < 1 do
        return Format.toString("% ms", cast(u32) Math.max(Math.round(seconds * 1000), 1))
    return Format.toString("%{f2} s", seconds)
}

// Plots the waveform of a sound above its time scale, the played part apart from the rest.
struct SoundWaveformView
{
    using wnd:  Wnd
    samples:    Array'WaveformPoint
    readyCount: u64     // Points the builder has published so far.
    duration:   f32
    progress:   f32     // Played fraction, from 0 to 1.
}

// Reduces successive interleaved PCM16 chunks without retaining their borrowed storage.
struct WaveformReducer
{
    points:       *Array'WaveformPoint
    frameCount:   u64
    pointCount:   u64
    channels:     u32
    frameOffset:  u64
    currentPoint: u64
    peak:         f32
    sum:          f64
    sampleCount:  u64
    readyCount:   u64
}

impl WaveformReducer
{
    mtd consume(samples: const [..] s16)
    {
        let frames = samples.count / .channels
        for frame in frames
        {
            let target = Math.min(.frameOffset * .pointCount / .frameCount, .pointCount - 1)
            if target != .currentPoint
            {
                .points[][.currentPoint] = {.peak, .sampleCount ? cast(f32) (.sum / cast(f64) .sampleCount) : 0}
                .readyCount   = .currentPoint + 1
                .currentPoint = target
                .peak         = 0
                .sum          = 0
                .sampleCount  = 0
            }

            var mixed = 0'f32
            for channel in .channels do
                mixed += cast(f32) samples[frame * .channels + channel] / 32768
            let level = Math.abs(mixed / .channels)
            .peak        = Math.max(.peak, level)
            .sum         += level
            .sampleCount += 1
            .frameOffset += 1
        }
    }

    mtd finish()
    {
        if not .sampleCount or .currentPoint >= .pointCount do
            return
        .points[][.currentPoint] = {.peak, cast(f32) (.sum / cast(f64) .sampleCount)}
        .readyCount = .currentPoint + 1
    }
}

// Returns the interval a time scale is graduated at, so the marks land on numbers a reader
// already thinks in rather than on an even division of whatever the duration happens to be.
func waveformTickStep(duration: f32, plotWidth: f32)->f32
{
    const Steps: [14] f32 = [0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]

    // One mark every 120 pixels or so keeps the scale readable at any width, and each label needs
    // the room its own digits take.
    let wanted = duration * 120 / Math.max(plotWidth, 1)
    for step in Steps where step >= wanted do
        return step
    return Steps[Steps.count - 1]
}

// Formats one graduation of the time scale, in the shortest spelling its step allows.
func waveformTickText(seconds, step: f32)->String
{
    if seconds >= 60
    {
        let minutes = cast(u32) (seconds / 60)
        let rest    = cast(u32) Math.round(seconds - cast(f32) minutes * 60)
        return Format.toString("%:%{02}", minutes, rest)
    }

    if step < 1 do
        return Format.toString("%{f2}", seconds)
    return Format.toString("%", cast(u32) Math.round(seconds))
}

private impl SoundWaveformView
{
    // Returns the band the wave is drawn in, above the band the time scale is read in.
    mtd const plotRect()->Math.Rectangle
    {
        let rect = .clientRect()
        return {rect.x + WaveformInsetX,
                rect.y + WaveformInsetY,
                Math.max(rect.width - 2 * WaveformInsetX, 1),
                Math.max(rect.height - 2 * WaveformInsetY - WaveformScaleHeight, 1)}
    }

    // Draws the graduated scale under the wave, skipping any mark whose label would touch the one
    // before it.
    mtd paintTimeScale(painter: *Painter, plot: Math.Rectangle)
    {
        if .duration <= 0 do
            return

        let font = .font().regular
        if not font do
            return

        let colors  = .themeColors()
        let step    = waveformTickStep(.duration, plot.width)
        let baseY   = plot.bottom()
        var written = plot.x - 1

        painter.drawLine(plot.x, baseY, plot.right(), baseY, colors.border, 1)

        var seconds = 0'f32
        while seconds <= .duration
        {
            let x = plot.x + plot.width * (seconds / .duration)
            painter.drawLine(x, baseY, x, baseY + WaveformTickHeight, colors.border, 1)

            // The last graduation is pulled back inside the plot rather than dropped: a scale that
            // stops naming its end reads as a scale that was cut off.
            let text  = waveformTickText(seconds, step)
            let width = Painter.measureString(text.toString(), font).width
            let left  = Math.min(x, plot.right() - width)
            if left > written
            {
                painter.drawString(left, baseY + WaveformTickHeight + 4, text.toString(), font, colors.label_TextFaint)
                written = left + width + 12
            }

            seconds += step
        }
    }
}

private impl IWnd for SoundWaveformView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let plot    = .plotRect()
        let center  = plot.vertCenter()

        painter.setParams(.Antialiased)
        .paintTimeScale(painter, plot)

        // The silence line is under the wave, and only shows where the wave has nothing to say.
        painter.drawLine(plot.x, center, plot.right(), center, colors.border, 1)
        if .samples.isEmpty() do
            return

        // The alternate theme tone gives the sound its own voice while the signature accent stays
        // reserved for the exact play position. Two opacities preserve transient and body detail.
        let alternate = .theme().palette.alternate.mark
        let playBody  = Color.lerp(colors.view_Bk, alternate, 0.92)
        let playPeak  = Color.lerp(colors.view_Bk, alternate, 0.58)
        let restBody  = Color.lerp(colors.view_Bk, alternate, 0.48)
        let restPeak  = Color.lerp(colors.view_Bk, alternate, 0.25)

        let columns = cast(u64) Math.max(plot.width, 1)

        // Pixel alignment keeps the progress boundary crisp instead of blending two adjacent
        // waveform columns into a soft vertical seam.
        let playHead = Math.round(Math.clamp(.progress, 0, 1) * plot.width)
        let scale    = plot.height * 0.5 - 1

        for column in columns
        {
            let first = column * .samples.count / columns
            let last  = Math.max((column + 1) * .samples.count / columns, first + 1)
            if first >= .readyCount do
                continue
            var peak = 0'f32
            var body = 0'f32
            for index in first until Math.min(last, .readyCount)
            {
                peak = Math.max(peak, .samples[index].peak)
                body = Math.max(body, .samples[index].body)
            }

            // A slice of near silence still gets its pixel: a wave broken into a comb reads as a
            // rendering fault rather than as a quiet passage.
            let peakHeight = Math.max(peak * scale, 0.5)
            let bodyHeight = Math.max(body * scale, 0.5)
            let played     = cast(f32) column < playHead
            let x          = plot.x + cast(f32) column

            painter.fillRect(x, center - peakHeight, 1, peakHeight * 2, played ? playPeak : restPeak)
            painter.fillRect(x, center - bodyHeight, 1, bodyHeight * 2, played ? playBody : restBody)
        }

        // The play head is a rule, and it runs into the scale so the time it is at can be read.
        if .progress > 0
        {
            let x = plot.x + playHead
            painter.drawLine(x, plot.y, x, plot.bottom() + WaveformTickHeight, colors.hilight, 1)
        }
    }
}

// Plays a sound file over its waveform, with the transport in the host's command bar.
struct SoundViewer
{
    using wnd: Wnd

    late
    {
        commands:       *Wnd
        playButton:     *IconButton
        stopButton:     *IconButton
        backwardButton: *IconButton
        forwardButton:  *IconButton
        timeline:       *Slider
        timeLabel:      *Label
        muteButton:     *IconButton
        volumeSlider:   *Slider
        waveform:       *SoundWaveformView
    }

    // Opening runs on a worker. `openState` is zero while opening, one on success and two on failure.
    sound:        SoundFile
    pendingSound: SoundFile
    openFileName: String
    openFailure:  String
    openThread:   Thread
    openState:    u32
    openFinished: bool

    waveformThread: Thread
    waveformLock:   Sync.Mutex
    waveformBuilt:  u64

    voice:       *Voice?
    timer:       *Timer?
    duration:    f32
    elapsed:     f32
    engineReady: bool
    playing:     bool
    muted:       bool
    volume = 1'f32

    retireRequested: bool
    retired:         bool

    details:              String
    reportDetails:        Viewer.ReportDetails?
    reportFailure:        Viewer.ReportFailure?
    reportLoadingChanged: Viewer.ReportLoadingChanged?
    reportFinished:       Viewer.ReportFinished?
}

impl SoundViewer
{
    // Reports whether work remains whose result has not reached the waveform yet.
    mtd isLoading()->bool
    {
        if not .openFinished do
            return true
        if not .waveformThread.isValid() do
            return false

        let built = .publishedWaveformCount()
        return not .waveformThread.isDone() or .waveform.readyCount < built
    }

    // Reports whether the host should cover the view, which is until the sound has opened.
    mtd needsLoadingOverlay()->bool => not .openFinished

    // Publishes the file opened by the worker and initializes playback on the GUI thread.
    mtd completeOpen() fail
    {
        if .openFinished do
            return

        let state = Atomic.get(&.openState)
        if not state or (.openThread.isValid() and not .openThread.isDone()) do
            return
        if .openThread.isValid() do
            .openThread.wait()

        .openFinished = true
        if state == 2 do
            fail InvalidFormatError{Errors.mkString(.openFailure.toString())}

        .sound    = #move .pendingSound
        .duration = .sound.durationInSeconds()
        .waveform.duration = .duration
        if .duration > 0 do
            .timeline.setBounds(0, .duration, Math.min(0.01'f32, .duration / 100))
        .startWaveform()

        .engineReady = acquireSoundEngine()
        if .engineReady do
            .playButton.enable(true)
        .backwardButton.enable(.engineReady and .duration > 0)
        .forwardButton.enable(.engineReady and .duration > 0)
        .timeline.enable(.engineReady and .duration > 0)
        .muteButton.enable(.engineReady)
        .volumeSlider.enable(.engineReady)
        .refreshTransport()
        if not .engineReady do
            .playButton.toolTip = soundStrings().ui_NoEngine
        .refreshDetails()
        if .reportLoadingChanged do
            .reportLoadingChanged(me)
    }

    // Rebuilds the host summary in the active language and reports it.
    mtd refreshDetails()
    {
        .details = Format.toString(soundStrings().ui_Details, .sound.sampleRateHz(), channelCountText(.sound.numChannels()), .sound.sampleStorageBits(), soundDurationText(.duration))
        if .reportDetails do
            .reportDetails(me, .details.toString())
    }

    mtd retranslate()
    {
        .playButton.toolTip     = .playing ? soundStrings().ui_TipPause : soundStrings().ui_TipPlay
        .stopButton.toolTip     = soundStrings().ui_TipStop
        .backwardButton.toolTip = soundStrings().ui_TipBackward
        .forwardButton.toolTip  = soundStrings().ui_TipForward
        .volumeSlider.toolTip   = soundStrings().ui_TipVolume
        .muteButton.toolTip     = soundStrings().ui_TipMute
        .timeline.toolTip       = soundStrings().ui_TipSeek
        if not .openFinished or .openState != 1 do
            return

        if not .engineReady do
            .playButton.toolTip = soundStrings().ui_NoEngine
        .refreshDetails()
    }

    // Finishes teardown once neither worker can touch the sound or waveform storage.
    mtd finishRetire()
    {
        if .retired do
            return
        if .openThread.isValid() do
            .openThread.wait()
        if .waveformThread.isValid() do
            .waveformThread.wait()
        .retired = true
    }

    // Requests teardown without waiting on the GUI thread, and reports whether deferred GUI destruction may release this view.
    mtd retire()->bool
    {
        if .retired do
            return true
        if not .retireRequested
        {
            .retireRequested = true
            if .timer
            {
                .removeTimer(.timer)
                .timer = null
            }

            if .voice
            {
                catch .voice.stop()
                .voice.destroy()
                .voice = null
            }

            if .engineReady
            {
                releaseSoundEngine()
                .engineReady = false
            }

            if .openThread.isValid() do
                .openThread.safeForceEnd()
            if .waveformThread.isValid() do
                .waveformThread.safeForceEnd()
        }

        if .openThread.isValid() and not .openThread.isDone() do
            return false
        if .waveformThread.isValid() and not .waveformThread.isDone() do
            return false
        .finishRetire()
        return true
    }

    // Tears the view down for window destruction, which, unlike file selection, may wait for both workers.
    mtd retireBlocking()
    {
        discard .retire()
        .finishRetire()
    }

    // Publishes the first `count` waveform points to the GUI thread.
    //
    // The worker never changes a published point, so the painter can read that prefix after taking
    // this one synchronized count without copying the whole wave.
    mtd publishWaveform(count: u64)
    {
        Sync.scopedLock(&.waveformLock)
        .waveformBuilt = count
    }

    // Returns how many waveform points the worker has published.
    mtd publishedWaveformCount()->u64
    {
        Sync.scopedLock(&.waveformLock)
        return .waveformBuilt
    }

    // Decodes the sound independently from voice streaming and reduces it to the waveform budget.
    //
    // Successive PCM16 chunks are reduced as they arrive; the callback never retains the decoder's
    // borrowed storage.
    mtd buildWaveformInBackground(thread: Thread)
    {
        let frameCount = .sound.sampleFrameCount()
        let pointCount = .waveform.samples.count
        let channels   = .sound.numChannels()
        if not frameCount or not pointCount or not channels do
            return

        var reducer = WaveformReducer{&.waveform.samples, frameCount, pointCount, channels}
        catch .sound.decodePcm16(func|reducer = &reducer, view = me, worker = &thread|(samples: const [..] s16)->bool
        {
            reducer.consume(samples)
            if reducer.readyCount do
                view.publishWaveform(reducer.readyCount)
            return not worker[].requestEnd
        })
        reducer.finish()
        .publishWaveform(reducer.readyCount)
    }

    // Starts the worker that reduces the sound to its waveform.
    mtd startWaveform()
    {
        let pointCount = Math.min(.sound.sampleFrameCount(), WaveformPointCount)
        if not pointCount do
            return
        .waveform.samples.resize(pointCount)
        catch .waveformThread.init(func|view = me|(thread: Thread) { view.buildWaveformInBackground(thread) }, priority: .BelowNormal) as initError
        if initError != null do
            return
        catch .waveformThread.start() as startError
        if startError != null do
            .waveformThread.wait()
    }

    mtd syncWaveform()
    {
        let ready = .publishedWaveformCount()
        if ready == .waveform.readyCount do
            return
        .waveform.readyCount = ready
        .waveform.invalidate()
    }

    mtd refreshTransport()
    {
        .playButton.setIcon(.theme().icon(.playing ? .Pause : .Play, themeActionIconSize(.themeMetrics())))
        .playButton.toolTip = .playing ? soundStrings().ui_TipPause : soundStrings().ui_TipPlay
        .stopButton.enable(.voice != null)
        .timeline.setValueWithoutGesture(.elapsed)
        .timeLabel.setText(Viewer.timeRangeText(.elapsed, .duration))
        .waveform.progress = .duration > 0 ? .elapsed / .duration : 0
        .waveform.invalidate()
    }

    mtd ensureVoice()->bool
    {
        if .voice do
            return true
        .voice = catch Voice.create(&.sound)! as createError
        if createError != null or not .voice do
            return false
        catch .voice.setVolume(.muted ? 0 : .volume)
        return true
    }

    mtd seekSeconds(seconds: f32)
    {
        if not .engineReady or not .ensureVoice() do
            return
        let target = Math.clamp(seconds, 0, .duration)
        let frame  = cast(u64) Math.round(target * cast(f32) .sound.sampleRateHz())
        catch .voice!.seekSampleFrame(frame) as seekError
        if seekError != null do
            return
        .elapsed = target
        .refreshTransport()
    }

    mtd seekRelative(seconds: f32)
    {
        let current = .voice ? cast(f32) .voice.playbackPositionSeconds() : .elapsed
        .seekSeconds(current + seconds)
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

    mtd togglePlayback()
    {
        if not .engineReady or not .ensureVoice() do
            return

        if .playing
        {
            catch .voice!.pause() as pauseError
            if pauseError != null do
                return
            .playing = false
        }
        else
        {
            catch .voice!.play() as playError
            if playError != null do
                return
            .playing = true
        }

        .refreshTransport()
    }

    mtd stopPlayback()
    {
        if .voice
        {
            catch .voice.stop() as stopError
            if stopError != null do
                return
        }

        .playing = false
        .elapsed = 0
        .refreshTransport()
    }

    // Applies what the window's play mode calls for once the sound has been played through.
    //
    // Stopping rewinds the transport either way: a sound has no last picture to park on, and
    // one that is to be replayed starts again from its first sample.
    mtd finishPlayback()
    {
        let continuation = .reportFinished ? .reportFinished(me) : Viewer.Continuation.Stop
        .stopPlayback()
        if continuation == .Replay do
            .togglePlayback()
    }
}

impl IWnd for SoundViewer
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .timer
        {
            evt.accepted = false
            return
        }

        if not .openFinished
        {
            catch .completeOpen() as openError
            if openError != null and .reportFailure do
                .reportFailure(me, Errors.message(openError))
            return
        }

        .syncWaveform()
        if not .playing or not .voice do
            return
        .elapsed = cast(f32) .voice.playbackPositionSeconds()
        if .elapsed >= .duration
        {
            .finishPlayback()
            return
        }

        .refreshTransport()
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
        case .Left:                   .seekRelative(-SoundSeekSeconds)
        case .Right:                  .seekRelative(SoundSeekSeconds)
        case .M, .VolumeMute:         .setMuted(not .muted)
        case .MediaStop:              .stopPlayback()
        default:                      evt.accepted = false
        }
    }
}

impl SoundViewer
{
    // Creates the transport in the command group: transport and seek buttons on the left, the
    // sound controls and the clock on the right, and the timeline between them.
    //
    // Every control starts disabled; opening the sound enables what the engine can serve.
    mtd createTransportBar()
    {
        let iconSize   = themeActionIconSize(.themeMetrics())
        let buttonSize = themeActionButtonSize(.themeMetrics())

        with .playButton = IconButton.create(.commands, .theme().icon(.Play, iconSize), {0, 0, buttonSize, buttonSize})
        {
            .dockStyle = .Left
            .toolTip   = soundStrings().ui_TipPlay
            .enable(false)
            .sigPressed += func|view = me|(button)
            {
                discard button
                view.togglePlayback()
            }
        }

        with .stopButton = IconButton.create(.commands, .theme().icon(.Stop, iconSize), {0, 0, buttonSize, buttonSize})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = soundStrings().ui_TipStop
            .enable(false)
            .sigPressed += func|view = me|(button)
            {
                discard button
                view.stopPlayback()
            }
        }

        with .backwardButton = IconButton.create(.commands, .theme().icon(.SeekBackward, iconSize), {0, 0, buttonSize, buttonSize})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = soundStrings().ui_TipBackward
            .enable(false)
            .sigPressed += func|view = me|(button)
            {
                discard button
                view.seekRelative(-SoundSeekSeconds)
            }
        }

        with .forwardButton = IconButton.create(.commands, .theme().icon(.SeekForward, iconSize), {0, 0, buttonSize, buttonSize})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = soundStrings().ui_TipForward
            .enable(false)
            .sigPressed += func|view = me|(button)
            {
                discard button
                view.seekRelative(SoundSeekSeconds)
            }
        }

        with .volumeSlider = Slider.create(.commands, {0, 0, 96, 36})
        {
            .dockStyle = .Right
            .margin    = {8, 1, 0, 1}
            .toolTip   = soundStrings().ui_TipVolume
            .setBounds(0, 1, 0.05)
            .setValueWithoutGesture(1)
            .enable(false)
            .sigChanged += func|view = me|(slider)
            {
                view.setVolume(slider.value())
            }
        }

        with .muteButton = IconButton.create(.commands, .theme().icon(.Volume, iconSize), {0, 0, buttonSize, buttonSize}, flags: .Toggle)
        {
            .dockStyle = .Right
            .margin.x  = 8
            .toolTip   = soundStrings().ui_TipMute
            .setCheckIndicator(.Frame)
            .enable(false)
            .sigCheckedChanged += func|view = me|(button)
            {
                view.setMuted(button.isChecked)
            }
        }

        with .timeLabel = Label.create(.commands, "", {0, 0, 112, 36}, null, .SecondaryText)
        {
            .dockStyle = .Right
            .margin.x  = 8
            .setTextAlignment(.Right, .Center)
        }

        with .timeline = Slider.create(.commands, {0, 0, 0, 36})
        {
            .dockStyle = .Center
            .margin    = {12, 1, 12, 1}
            .toolTip   = soundStrings().ui_TipSeek
            .enable(false)
            .sigEndChange += func|view = me|(slider)
            {
                view.seekSeconds(slider.value())
            }
        }
    }

    func create(host: Viewer.Host)->*SoundViewer fail
    {
        let services    = host.services()
        with let result = Wnd.create'SoundViewer(host.contentParent(), "scope.sound")
        {
            .backgroundStyle      = .View
            .reportDetails        = services.reportDetails
            .reportFinished       = services.reportFinished
            .reportFailure        = services.reportFailure
            .reportLoadingChanged = services.reportLoadingChanged
        }

        defer #fail result.destroy()

        result.commands = host.createCommandGroup(SoundCommandWidth)
        result.createTransportBar()

        with result.waveform = Wnd.create'SoundWaveformView(result, "scope.sound.waveform")
        {
            .dockStyle       = .Center
            .backgroundStyle = .View
        }

        result.timer = result.addTimer(33'ms)
        result.refreshTransport()
        result.applyLayout()
        result.setInitialFocus(result.playButton)
        result.openFileName = host.fileName()
        try result.openThread.init(&runSoundViewerOpen, result, priority: .Normal)
        try result.openThread.start()
        return result
    }
}

// Opens and indexes the sound without occupying the GUI event loop.
//
// The default allocator makes the owned packet table safe to publish to the GUI thread once
// loading completes.
private func runSoundViewerOpen(thread: Thread)
{
    let view    = cast(*SoundViewer) thread.userParam!
    let context = Swag.getContext()
    context.allocator = context.defaultAllocator!
    var sound = catch SoundFile.load(view.openFileName.toString(), preloadData: false) as openError
    if openError != null
    {
        view.openFailure = Errors.message(openError)
        Atomic.exchange(&view.openState, 2)
        return
    }

    if thread.requestEnd do
        return
    view.pendingSound = #move sound
    Atomic.exchange(&view.openState, 1)
}

// Returns the created viewer as a nullable pointer, which gives `catch` a fallback value.
private func loadSoundViewer(host: Viewer.Host)->*SoundViewer? fail => try SoundViewer.create(host)

// Creates the integrated sound playback and waveform view and connects it to the host.
func createSoundViewer(host: Viewer.Host)
{
    let view = catch loadSoundViewer(host) as createError
    if createError != null
    {
        host.reject(Errors.message(createError))
        return
    }

    host.attachView(view!)
    host.setDetails(view.details.toString())
    host.setLifecycle({
        retire: func(wnd)->bool => (cast #assume (*SoundViewer) wnd).retire(),
        isLoading: func(wnd)->bool => (cast #assume (*SoundViewer) wnd).isLoading(),
        needsLoadingOverlay: func(wnd)->bool => (cast #assume (*SoundViewer) wnd).needsLoadingOverlay()})
}
