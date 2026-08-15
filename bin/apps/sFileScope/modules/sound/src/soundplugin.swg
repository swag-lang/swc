#global public

using Core, Pixel, Gui, Audio

private const ViewerPluginApiVersion = 2'u32
private const WaveformPointCount = 2048'u64

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

internal func buildWaveform(bytes: const [..] u8, encoding: SoundFileEncoding, channels: u32)->Array'f32
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
        for frame in first until last
        {
            var mixed = 0'f32
            for channel in channels
            {
                let offset = frame * bytesPerFrame + channel * bytesPerSample
                mixed += soundSample(bytes, offset, encoding)
            }

            mixed /= channels
            peak  = Math.max(peak, Math.abs(mixed))
        }

        result[point] = peak
    }

    return result
}

private struct SoundWaveformView
{
    using wnd: Wnd
    samples:   Array'f32
    progress:  f32
}

private impl IWnd for SoundWaveformView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let rect    = .clientRect()
        let center  = rect.vertCenter()
        painter.drawLine(rect.x, center, rect.right(), center, .themeColors().label_TextFaint, 1)
        if !.samples.count do
            return

        let width = cast(u64) Math.max(rect.width, 1)
        for x in width
        {
            let index     = Math.min(x * .samples.count / width, .samples.count - 1)
            let amplitude = .samples[index] * rect.height * 0.42
            painter.drawLine(rect.x + x, center - amplitude, rect.x + x, center + amplitude, .themeColors().richColor1, 1)
        }

        if .progress > 0
        {
            let playX = rect.x + rect.width * Math.clamp(.progress, 0, 1)
            painter.drawLine(playX, rect.y, playX, rect.bottom(), .themeColors().activeRail, 2)
        }
    }
}

internal struct SoundPluginView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:   *Wnd
        playButton: *PushButton
        stopButton: *PushButton
        titleLabel: *Label
        infoLabel:  *Label
        waveform:   *SoundWaveformView
    }

    sound:       SoundFile
    voice:       #null *Voice
    timer:       #null *Timer
    duration:    f32
    elapsed:     f32
    engineReady: bool
    playing:     bool
}

internal impl SoundPluginView
{
    mtd updatePlaybackUi()
    {
        .playButton.setText(.playing ? "Pause" : "Play")
        .stopButton.enable(.voice != null)
        .waveform.progress = .duration > 0 ? .elapsed / .duration : 0
        .waveform.invalidate()
    }

    mtd togglePlayback()
    {
        if !.engineReady do
            return
        if !.voice
        {
            .voice = catch Voice.create(&.sound)! as createError
            if createError != null or !.voice do
                return
        }

        if .playing
        {
            catch .voice!.pause()
            .playing = false
        }
        else
        {
            catch .voice!.play()
            .playing = true
        }

        .updatePlaybackUi()
    }

    mtd stopPlayback()
    {
        if .voice do
            catch .voice!.stop()
        .playing = false
        .elapsed = 0
        .updatePlaybackUi()
    }
}

internal impl IWnd for SoundPluginView
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .timer
        {
            evt.accepted = false
            return
        }

        if !.playing do
            return
        .elapsed += 0.033
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
            destroyEngine()
            .engineReady = false
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

internal impl SoundPluginView
{
    func create(contentParent, commandParent: *Wnd, fileName: string)->*SoundPluginView
    {
        let result = Wnd.create'SoundPluginView(contentParent, "sFileScope.sound")
        result.backgroundStyle = .View

        result.commands                 = Wnd.create'Wnd(commandParent, {0, 0, 168, 36})
        result.commands.backgroundStyle = .Window
        with result.playButton = PushButton.create(result.commands, "Play", {0, 0, 80, 36})
        {
            .dockStyle  = .Left
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.togglePlayback()
            }
        }

        with result.stopButton = PushButton.create(result.commands, "Stop", {0, 0, 80, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .enable(false)
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.stopPlayback()
            }
        }

        let header = Wnd.create'Wnd(result, {0, 0, 0, 112})
        header.dockStyle       = .Top
        header.backgroundStyle = .Window
        header.padding         = {32, 20, 32, 16}

        let baseName = Path.fileName(fileName) orelse fileName
        result.titleLabel           = Label.create(header, baseName, {0, 0, 0, 36})
        result.titleLabel.dockStyle = .Top
        result.titleLabel.style.setFont(result.theme().createDefaultFont(22, .Bold), .Regular)
        result.titleLabel.setTextAlignment(.Left, .Center)

        result.infoLabel           = Label.create(header, "Loading WAV…", {0, 0, 0, 28}, null, .SecondaryText)
        result.infoLabel.dockStyle = .Top
        result.infoLabel.setTextAlignment(.Left, .Center)

        result.waveform                 = Wnd.create'SoundWaveformView(result, "sFileScope.sound.waveform")
        result.waveform.dockStyle       = .Center
        result.waveform.backgroundStyle = .View
        result.waveform.padding         = {32, 32, 32, 32}

        catch createEngine() as createError
        if createError != null
        {
            result.infoLabel.setText("Audio playback is unavailable on this system.")
            result.applyLayout()
            return result
        }

        result.engineReady = true

        let sound = catch SoundFile.load(fileName) as loadError
        if loadError != null
        {
            result.infoLabel.setText("This WAV file could not be decoded.")
            result.applyLayout()
            return result
        }

        result.sound            = #move sound
        result.duration         = result.sound.durationInSeconds()
        result.waveform.samples = buildWaveform(result.sound.preloadedData(), result.sound.sampleEncoding(), result.sound.numChannels())
        result.infoLabel.setText(Format.toString("% Hz  ·  % channel%  ·  % bit  ·  % s", result.sound.sampleRateHz(), result.sound.numChannels(), result.sound.numChannels() == 1 ? "" : "s", result.sound.sampleStorageBits(), result.duration).toString())
        result.timer = result.addTimer(33'ms)
        result.updatePlaybackUi()
        result.applyLayout()
        result.setInitialFocus(result.playButton)
        return result
    }
}

// Creates the WAV playback and waveform view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd)->#null *Wnd
{
    if apiVersion != ViewerPluginApiVersion do
        return null
    let view = SoundPluginView.create(contentParent, commandParent, fileName)
    commands[] = view.commands
    return view
}
