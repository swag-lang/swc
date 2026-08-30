#global internal

using Core, Pixel, Gui, Audio, Threading

private const SoundSeekSeconds = 10.0

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
internal struct WaveformPoint
{
    peak: f32     // Loudest absolute level of the slice.
    body: f32     // Mean absolute level of the slice.
}

private var g_SoundEngineUsers:      u32
private var g_SoundViewerOwnsEngine: bool

// Creation of the audio engine started ahead of the first voice, on a scheduler worker.
private var g_SoundEngineWarmUp:  Jobs.Job
private var g_SoundEngineWarming: bool

// Starts creating the audio engine without waiting for it.
//
// Opening the output device is the better part of a second, and a player that only asks for
// the engine once its first picture is ready to be shown adds that second to the wait for
// the picture. Starting it here lets the device come online while the file is being opened
// and its first picture decoded; [[acquireSoundEngine]] then joins the work instead of doing
// it. Call it from the GUI thread, which is the only one that acquires the engine.
internal func warmSoundEngine()
{
    if g_SoundEngineWarming or g_SoundEngineUsers or isEngineCreated() do
        return

    g_SoundEngineWarming       = true
    g_SoundEngineWarmUp.lambda = func(data: #null *void)
    {
        discard data
        discard catch createEngine()
    }
    g_SoundEngineWarmUp.data = null
    Jobs.schedule(&g_SoundEngineWarmUp)
}

internal func acquireSoundEngine(kind = DriverKind.Default)->bool
{
    if g_SoundEngineUsers
    {
        g_SoundEngineUsers += 1
        return true
    }

    if g_SoundEngineWarming
    {
        Jobs.wait(&g_SoundEngineWarmUp)
        g_SoundEngineWarming = false
        if isEngineCreated() do
            g_SoundViewerOwnsEngine = true
    }

    if !isEngineCreated()
    {
        catch createEngine(kind) as createError
        if createError != null do
            return false
        g_SoundViewerOwnsEngine = true
    }

    g_SoundEngineUsers = 1
    return true
}

internal func releaseSoundEngine()
{
    if !g_SoundEngineUsers do
        return
    g_SoundEngineUsers -= 1
    if g_SoundEngineUsers or !g_SoundViewerOwnsEngine do
        return
    destroyEngine()
    g_SoundViewerOwnsEngine = false
}

internal func soundSample(bytes: const [..] u8, offset: u64, encoding: SoundFileEncoding)->f32
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

internal func buildWaveform(bytes: const [..] u8, encoding: SoundFileEncoding, channels: u32)->Array'WaveformPoint
{
    var result: retval
    if !bytes.count or !channels do
        return result

    let bytesPerSample = encoding == .Pcm8 ? 1'u64 : (encoding == .Pcm16 ? 2 : (encoding == .Pcm24 ? 3 : 4))
    let bytesPerFrame  = bytesPerSample * channels
    let frameCount     = bytes.count / bytesPerFrame
    let pointCount     = Math.min(frameCount, WaveformPointCount)
    if !pointCount do
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

internal func soundDurationText(seconds: f32)->String
{
    if seconds < 1 do
        return Format.toString("% ms", cast(u32) Math.max(Math.round(seconds * 1000), 1))
    return Format.toString("%{f2} s", seconds)
}

internal struct SoundWaveformView
{
    using wnd:  Wnd
    samples:    Array'WaveformPoint
    readyCount: u64
    duration:   f32
    progress:   f32
}

// Reduces successive interleaved PCM16 chunks without retaining their borrowed storage.
internal struct WaveformReducer
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

internal impl WaveformReducer
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
                .readyCount              = .currentPoint + 1
                .currentPoint            = target
                .peak                    = 0
                .sum                     = 0
                .sampleCount             = 0
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
        if !.sampleCount or .currentPoint >= .pointCount do
            return
        .points[][.currentPoint] = {.peak, cast(f32) (.sum / cast(f64) .sampleCount)}
        .readyCount              = .currentPoint + 1
    }
}

// Returns the interval a time scale is graduated at, so the marks land on numbers a reader
// already thinks in rather than on an even division of whatever the duration happens to be.
internal func waveformTickStep(duration: f32, plotWidth: f32)->f32
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
internal func waveformTickText(seconds, step: f32)->String
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

        let resolved = .font().regular
        if !resolved do
            return

        let font    = resolved!
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
        if !.samples.count do
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

internal struct SoundViewer
{
    using wnd: Wnd

    #[Swag.Late]
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

    voice:       #null *Voice
    timer:       #null *Timer
    duration:    f32
    elapsed:     f32
    engineReady: bool
    playing:     bool
    muted:       bool
    volume = 1'f32

    retireRequested: bool
    retired:         bool

    details:              String
    reportDetails:        #null ViewerReportDetails
    reportFailure:        #null ViewerReportFailure
    reportLoadingChanged: #null ViewerReportLoadingChanged
}

internal impl SoundViewer
{
    // Reports work whose result has not reached the waveform yet.
    mtd isLoading()->bool
    {
        if !.openFinished do
            return true
        if !.waveformThread.isValid() do
            return false

        .waveformLock.lock()
        let built = .waveformBuilt
        .waveformLock.unlock()
        return !.waveformThread.isDone() or .waveform.readyCount < built
    }

    // Publishes the file opened by the worker and initializes playback on the GUI thread.
    mtd completeOpen() fail
    {
        if .openFinished do
            return

        let state = Atomic.get(&.openState)
        if !state or (.openThread.isValid() and !.openThread.isDone()) do
            return
        if .openThread.isValid() do
            .openThread.wait()

        .openFinished = true
        if state == 2 do
            fail InvalidFormatError{Errors.mkString(.openFailure.toString())}

        .sound             = #move .pendingSound
        .duration          = .sound.durationInSeconds()
        .waveform.duration = .duration
        if .duration > 0 do
            .timeline.setBounds(0, .duration, Math.min(0.01'f32, .duration / 100))
        .startWaveform()

        let durationText = soundDurationText(.duration)
        .details     = Format.toString(soundStrings().ui_Details, .sound.sampleRateHz(), channelCountText(.sound.numChannels()), .sound.sampleStorageBits(), durationText)
        .engineReady = acquireSoundEngine()
        if .engineReady do
            .playButton.enable(true)
        .backwardButton.enable(.engineReady and .duration > 0)
        .forwardButton.enable(.engineReady and .duration > 0)
        .timeline.enable(.engineReady and .duration > 0)
        .muteButton.enable(.engineReady)
        .volumeSlider.enable(.engineReady)
        .updatePlaybackUi()
        if !.engineReady do
            .playButton.toolTip = soundStrings().ui_NoEngine
        if .reportDetails do
            .reportDetails!(me, .details.toString())
        if .reportLoadingChanged do
            .reportLoadingChanged!(me)
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

    // Requests release without waiting on the GUI thread.
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

            if .voice
            {
                catch .voice!.stop()
                .voice!.destroy()
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

        if .openThread.isValid() and !.openThread.isDone() do
            return false
        if .waveformThread.isValid() and !.waveformThread.isDone() do
            return false
        .finishRetire()
        return true
    }

    // Window destruction is the terminal fallback and may wait for both workers.
    mtd retireBlocking()
    {
        discard .retire()
        .finishRetire()
    }

    // Publishes a completed prefix. The worker never changes a published point, so the painter can
    // read that prefix after taking this one synchronized count without copying the whole wave.
    mtd publishWaveform(count: u64)
    {
        Sync.scopedLock(&.waveformLock)
        .waveformBuilt = count
    }

    // Decodes the sound independently from Voice streaming and reduces successive PCM16 chunks to
    // a fixed visual budget. The callback never retains the decoder's borrowed storage.
    mtd buildWaveformInBackground(thread: Thread)
    {
        let frameCount = .sound.sampleFrameCount()
        let pointCount = .waveform.samples.count
        let channels   = .sound.numChannels()
        if !frameCount or !pointCount or !channels do
            return

        var reducer = WaveformReducer{&.waveform.samples, frameCount, pointCount, channels}
        catch .sound.decodePcm16(func|reducer = &reducer, view = me, worker = &thread|(samples: const [..] s16)->bool
        {
            reducer.consume(samples)
            if reducer.readyCount do
                view.publishWaveform(reducer.readyCount)
            return !worker[].requestEnd
        })
        reducer.finish()
        .publishWaveform(reducer.readyCount)
    }

    mtd startWaveform()
    {
        let pointCount = Math.min(.sound.sampleFrameCount(), WaveformPointCount)
        if !pointCount do
            return
        .waveform.samples.resize(pointCount)
        catch .waveformThread.init(func|view = me|(thread: Thread) { view.buildWaveformInBackground(thread); }, priority: .BelowNormal) as initError
        if initError != null do
            return
        catch .waveformThread.start() as startError
        if startError != null
        {
            .waveformThread.wait()
            return
        }
    }

    mtd syncWaveform()
    {
        .waveformLock.lock()
        let ready = .waveformBuilt
        .waveformLock.unlock()
        if ready == .waveform.readyCount do
            return
        .waveform.readyCount = ready
        .waveform.invalidate()
    }

    mtd updatePlaybackUi()
    {
        .playButton.setIcon(.theme().icon(.playing ? .Pause : .Play, themeActionIconSize(.themeMetrics())))
        .playButton.toolTip = .playing ? soundStrings().ui_TipPause : soundStrings().ui_TipPlay
        .stopButton.enable(.voice != null)
        .timeline.setValueWithoutGesture(.elapsed)
        .timeLabel.setText(mediaTimeRangeText(.elapsed, .duration))
        .waveform.progress = .duration > 0 ? .elapsed / .duration : 0
        .waveform.invalidate()
    }

    mtd ensureVoice()->bool
    {
        if .voice do
            return true
        .voice = catch Voice.create(&.sound)! as createError
        if createError != null or !.voice do
            return false
        catch .voice!.setVolume(.muted ? 0 : .volume)
        return true
    }

    mtd seekSeconds(seconds: f32)
    {
        if !.engineReady or !.ensureVoice() do
            return
        let target = Math.clamp(seconds, 0, .duration)
        let frame  = cast(u64) Math.round(target * cast(f32) .sound.sampleRateHz())
        catch .voice!.seekSampleFrame(frame) as seekError
        if seekError != null do
            return
        .elapsed = target
        .updatePlaybackUi()
    }

    mtd seekRelative(seconds: f32)
    {
        let current = .voice ? cast(f32) .voice!.playbackPositionSeconds() : .elapsed
        .seekSeconds(current + seconds)
    }

    mtd setMuted(muted: bool)
    {
        .muted = muted
        .muteButton.setChecked(muted)
        .muteButton.setIcon(.theme().icon(muted ? .VolumeMute : .Volume, themeActionIconSize(.themeMetrics())))
        if .voice do
            catch .voice!.setVolume(muted ? 0 : .volume)
    }

    mtd setVolume(volume: f32)
    {
        .volume = Math.clamp(volume, 0, 1)
        if .voice and !.muted do
            catch .voice!.setVolume(.volume)
    }

    mtd togglePlayback()
    {
        if !.engineReady do
            return
        if !.ensureVoice() do
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

        .updatePlaybackUi()
    }

    mtd stopPlayback()
    {
        if .voice
        {
            catch .voice!.stop() as stopError
            if stopError != null do
                return
        }

        .playing = false
        .elapsed = 0
        .updatePlaybackUi()
    }
}

internal impl IWnd for SoundViewer
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .timer
        {
            evt.accepted = false
            return
        }

        if !.openFinished
        {
            catch .completeOpen() as openError
            if openError != null and .reportFailure do
                .reportFailure!(me, Errors.message(openError))
            return
        }

        .syncWaveform()
        if !.playing or !.voice do
            return
        .elapsed = cast(f32) .voice!.playbackPositionSeconds()
        if .elapsed >= .duration
        {
            .stopPlayback()
            return
        }

        .updatePlaybackUi()
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
        case .M, .VolumeMute:         .setMuted(!.muted)
        case .MediaStop:              .stopPlayback()
        default:                      evt.accepted = false
        }
    }
}

internal impl SoundViewer
{
    func create(host: FileViewer.Host)->*SoundViewer fail
    {
        registerSoundStrings(host.application())
        let services = host.services()
        let result   = Wnd.create'SoundViewer(host.contentParent(), "scope.sound")
        result.backgroundStyle      = .View
        result.reportDetails        = services.reportDetails
        result.reportFailure        = services.reportFailure
        result.reportLoadingChanged = services.reportLoadingChanged

        result.commands = host.createCommandGroup(0)
        with result.playButton = IconButton.create(result.commands, result.theme().icon(.Play, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle = .Left
            .toolTip   = soundStrings().ui_TipPlay
            .enable(false)
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.togglePlayback()
            }
        }

        with result.stopButton = IconButton.create(result.commands, result.theme().icon(.Stop, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = soundStrings().ui_TipStop
            .enable(false)
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.stopPlayback()
            }
        }

        with result.backwardButton = IconButton.create(result.commands, result.theme().icon(.SeekBackward, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = soundStrings().ui_TipBackward
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.seekRelative(-SoundSeekSeconds)
            }
        }

        with result.forwardButton = IconButton.create(result.commands, result.theme().icon(.SeekForward, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = soundStrings().ui_TipForward
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.seekRelative(SoundSeekSeconds)
            }
        }

        with result.volumeSlider = Slider.create(result.commands, {0, 0, 96, 36})
        {
            .dockStyle = .Right
            .margin    = {8, 1, 0, 1}
            .toolTip   = soundStrings().ui_TipVolume
            .setBounds(0, 1, 0.05)
            .setValueWithoutGesture(1)
            .sigChanged += func|view = result|(slider)
            {
                view.setVolume(slider.value())
            }
        }

        with result.muteButton = IconButton.create(result.commands, result.theme().icon(.Volume, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())}, flags: .Toggle)
        {
            .dockStyle = .Right
            .margin.x  = 8
            .toolTip   = soundStrings().ui_TipMute
            .setCheckIndicator(.Frame)
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
            .dockStyle    = .Center
            .margin       = {12, 1, 12, 1}
            .toolTip      = soundStrings().ui_TipSeek
            .sigEndChange += func|view = result|(slider)
            {
                view.seekSeconds(slider.value())
            }
        }

        result.waveform                 = Wnd.create'SoundWaveformView(result, "scope.sound.waveform")
        result.waveform.dockStyle       = .Center
        result.waveform.backgroundStyle = .View

        result.backwardButton.enable(false)
        result.forwardButton.enable(false)
        result.timeline.enable(false)
        result.muteButton.enable(false)
        result.volumeSlider.enable(false)
        result.timer = result.addTimer(33'ms)
        result.updatePlaybackUi()
        result.applyLayout()
        result.setInitialFocus(result.playButton)
        result.openFileName = host.fileName()
        defer #fail
        {
            result.destroy()
        }

        try result.openThread.init(&runSoundViewerOpen, result, priority: .Normal)
        try result.openThread.start()
        return result
    }
}

// Opens and indexes the sound without occupying the GUI event loop. The default allocator makes
// the owned packet table safe to publish to the GUI thread once loading completes.
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

// Creates the integrated sound playback and waveform view.
private func loadSoundViewer(host: FileViewer.Host)->#null *SoundViewer fail => try SoundViewer.create(host)

func createSoundViewer(host: FileViewer.Host)
{
    let view = catch loadSoundViewer(host) as decodeError
    if decodeError != null
    {
        host.reject(Errors.message(decodeError))
        return
    }

    host.attachView(view!)
    host.setDetails(view!.details.toString())
    host.setLifecycle({
        retire: func(wnd)->bool { return (cast(*SoundViewer) wnd).retire() },
        isLoading: func(wnd)->bool { return (cast(*SoundViewer) wnd).isLoading() },
        needsLoadingOverlay: func(wnd)->bool { return !(cast(*SoundViewer) wnd).openFinished }})
}
