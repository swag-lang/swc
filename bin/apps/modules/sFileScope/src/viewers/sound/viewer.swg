#global internal

using Core, Pixel, Gui, Audio, Threading

private const SoundGlyphSize = 18.0
private const SoundSeekSeconds = 10.0

// Slices the payload is reduced to. It is read back one column of pixels at a time, so it only
// has to stay ahead of the widest plot a window can give it; past that the columns repeat.
private const WaveformPointCount = 4096'u64

// The analyzer yields after each bounded read. Playback uses its own stream, so neither cursor can
// stall or reposition the other while a very large file is still becoming visible.
private const WaveformReadSize = 256 * 1024'u64

// Air around the plot, and the band the time scale is read in.
private const WaveformInsetX = 24.0
private const WaveformInsetY = 32.0
private const WaveformScaleHeight = 26.0
private const WaveformTickHeight = 5.0

// Loudness of a slice, in the two readings a level meter carries: the transient that clips and the
// body the ear hears. Drawing both is what separates a waveform from a silhouette.
internal struct WaveformPoint
{
    peak: f32     // Loudest absolute level of the slice.
    body: f32     // Mean absolute level of the slice.
}

private var g_SoundEngineUsers: u32
private var g_SoundViewerOwnsEngine: bool

internal func acquireSoundEngine(kind = DriverKind.Default)->bool
{
    if g_SoundEngineUsers
    {
        g_SoundEngineUsers += 1
        return true
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
    if !@countof(bytes) or !channels do
        return result

    let bytesPerSample = encoding == .Pcm8 ? 1'u64 : (encoding == .Pcm16 ? 2 : (encoding == .Pcm24 ? 3 : 4))
    let bytesPerFrame  = bytesPerSample * channels
    let frameCount     = @countof(bytes) / bytesPerFrame
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
    return Steps[@countof(Steps) - 1]
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
        commands:       *ViewerCommandBar
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

    sound:          SoundFile
    voice:          #null *Voice
    timer:          #null *Timer
    waveformThread: Thread
    waveformLock:   Sync.Mutex
    waveformBuilt:  u64
    duration:       f32
    elapsed:        f32
    engineReady:    bool
    playing:        bool
    muted:          bool
    volume = 1'f32
    details:        String
}

internal impl SoundViewer
{
    // Publishes a completed prefix. The worker never changes a published point, so the painter can
    // read that prefix after taking this one synchronized count without copying the whole wave.
    mtd publishWaveform(count: u64)
    {
        Sync.scopedLock(&.waveformLock)
        .waveformBuilt = count
    }

    // Walks the payload sequentially and reduces it to a fixed visual budget. This is independent
    // from Voice streaming and deliberately owns every block it reads.
    mtd buildWaveformInBackground(thread: Thread)
    {
        let encoding       = .sound.sampleEncoding()
        let channels       = .sound.numChannels()
        let bytesPerSample = encoding == .Pcm8 ? 1'u64 : (encoding == .Pcm16 ? 2 : (encoding == .Pcm24 ? 3 : 4))
        let bytesPerFrame  = bytesPerSample * channels
        let frameCount     = .sound.sampleFrameCount()
        let pointCount     = .waveform.samples.count
        if !bytesPerFrame or !frameCount or !pointCount do
            return

        var byteOffset:   u64
        var frameOffset:  u64
        var currentPoint: u64
        var peak:         f32
        var sum:          f64
        var sampleCount:  u64

        while byteOffset < .sound.payloadSize() and !thread.requestEnd
        {
            var wanted = Math.min(WaveformReadSize, .sound.payloadSize() - byteOffset)
            wanted -= wanted % bytesPerFrame
            if !wanted do
                break

            let bytes = catch .sound.readPayload(byteOffset, wanted) as readError
            if readError != null or bytes.count < bytesPerFrame do
                break
            let frames = bytes.count / bytesPerFrame
            for frame in frames
            {
                let target = Math.min(frameOffset * pointCount / frameCount, pointCount - 1)
                if target != currentPoint
                {
                    .waveform.samples[currentPoint] = {peak, sampleCount ? cast(f32) (sum / cast(f64) sampleCount) : 0}
                    if (currentPoint + 1) % 32 == 0 do
                        .publishWaveform(currentPoint + 1)
                    currentPoint = target
                    peak         = 0
                    sum          = 0
                    sampleCount  = 0
                }

                var mixed = 0'f32
                for channel in channels
                {
                    let offset = frame * bytesPerFrame + channel * bytesPerSample
                    mixed += soundSample(bytes.toSlice(), offset, encoding)
                }

                let level = Math.abs(mixed / channels)
                peak        = Math.max(peak, level)
                sum         += level
                sampleCount += 1
                frameOffset += 1
            }

            byteOffset += frames * bytesPerFrame
        }

        if sampleCount and currentPoint < pointCount
        {
            .waveform.samples[currentPoint] = {peak, cast(f32) (sum / cast(f64) sampleCount)}
            .publishWaveform(currentPoint + 1)
        }
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
        .playButton.setIcon(.theme().icon(.playing ? .Pause : .Play, SoundGlyphSize))
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
        .muteButton.setIcon(.theme().icon(muted ? .VolumeMute : .Volume, SoundGlyphSize))
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
        if .waveformThread.isValid()
        {
            .waveformThread.safeForceEnd()
            .waveformThread.wait()
        }

        if .timer
        {
            .removeTimer(.timer!)
            .timer = null
        }

        if .voice
        {
            .voice!.destroy()
            .voice = null
        }

        if .engineReady
        {
            releaseSoundEngine()
            .engineReady = false
        }
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
    func create(contentParent, commandParent: *Wnd, fileName: string)->*SoundViewer fail
    {
        let sound  = try SoundFile.load(fileName, preloadData: false)
        let result = Wnd.create'SoundViewer(contentParent, "sFileScope.sound")
        result.backgroundStyle = .View

        result.commands = ViewerCommandBar.create(commandParent, 0)
        with result.playButton = IconButton.create(result.commands, result.theme().icon(.Play, SoundGlyphSize), {0, 0, 36, 36})
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

        with result.stopButton = IconButton.create(result.commands, result.theme().icon(.Stop, SoundGlyphSize), {0, 0, 36, 36})
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

        with result.backwardButton = IconButton.create(result.commands, result.theme().icon(.SeekBackward, SoundGlyphSize), {0, 0, 36, 36})
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

        with result.forwardButton = IconButton.create(result.commands, result.theme().icon(.SeekForward, SoundGlyphSize), {0, 0, 36, 36})
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

        with result.muteButton = IconButton.create(result.commands, result.theme().icon(.Volume, SoundGlyphSize), {0, 0, 36, 36}, flags: .Toggle)
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

        result.waveform                 = Wnd.create'SoundWaveformView(result, "sFileScope.sound.waveform")
        result.waveform.dockStyle       = .Center
        result.waveform.backgroundStyle = .View

        result.sound             = #move sound
        result.duration          = result.sound.durationInSeconds()
        result.waveform.duration = result.duration
        if result.duration > 0 do
            result.timeline.setBounds(0, result.duration, Math.min(0.01'f32, result.duration / 100))
        result.startWaveform()
        let durationText = soundDurationText(result.duration)
        result.details     = Format.toString(soundStrings().ui_Details, result.sound.sampleRateHz(), channelCountText(result.sound.numChannels()), result.sound.sampleStorageBits(), durationText)
        result.engineReady = acquireSoundEngine()
        result.timer       = result.addTimer(33'ms)
        if result.engineReady do
            result.playButton.enable(true)
        result.backwardButton.enable(result.engineReady and result.duration > 0)
        result.forwardButton.enable(result.engineReady and result.duration > 0)
        result.timeline.enable(result.engineReady and result.duration > 0)
        result.muteButton.enable(result.engineReady)
        result.volumeSlider.enable(result.engineReady)
        result.updatePlaybackUi()
        if !result.engineReady do
            result.playButton.toolTip = soundStrings().ui_NoEngine
        result.applyLayout()
        result.setInitialFocus(result.playButton)
        return result
    }
}

private func loadSoundViewer(contentParent, commandParent: *Wnd, fileName: string)->#null *SoundViewer fail => try SoundViewer.create(contentParent, commandParent, fileName)

// Creates the integrated WAV playback and waveform view.
func createSoundViewer(request: const *ViewerRequest, result: *ViewerResult)
{
    registerSoundStrings(request.contentParent.app())
    let view = catch loadSoundViewer(request.contentParent, request.commandParent, request.fileName) as decodeError
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
        let soundView = cast(*SoundViewer) wnd
        return soundView.waveform.readyCount < soundView.waveform.samples.count
    }
}
