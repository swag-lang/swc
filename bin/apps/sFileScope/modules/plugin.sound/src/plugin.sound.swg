#global public

using Core, Pixel, Gui, Audio

private const ViewerPluginApiVersion = 3'u32
private const WaveformPointCount = 2048'u64
private const SoundGlyphSize = 18.0

private var g_SoundEngineUsers: u32
private var g_SoundPluginOwnsEngine: bool

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
        g_SoundPluginOwnsEngine = true
    }

    g_SoundEngineUsers = 1
    return true
}

internal func releaseSoundEngine()
{
    if !g_SoundEngineUsers do
        return
    g_SoundEngineUsers -= 1
    if g_SoundEngineUsers or !g_SoundPluginOwnsEngine do
        return
    destroyEngine()
    g_SoundPluginOwnsEngine = false
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

internal func soundDurationText(seconds: f32)->String
{
    if seconds < 1 do
        return Format.toString("% ms", cast(u32) Math.max(Math.round(seconds * 1000), 1))
    return Format.toString("%{f2} s", seconds)
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
        playButton: *IconButton
        stopButton: *IconButton
        waveform:   *SoundWaveformView
    }

    sound:       SoundFile
    voice:       #null *Voice
    timer:       #null *Timer
    duration:    f32
    elapsed:     f32
    engineReady: bool
    playing:     bool
    details:     String
}

internal impl SoundPluginView
{
    mtd updatePlaybackUi()
    {
        .playButton.setIcon(.theme().icon(.playing ? .Pause : .Play, SoundGlyphSize))
        .playButton.toolTip = .playing ? "Pause" : "Play"
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
            releaseSoundEngine()
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

        result.commands                 = Wnd.create'Wnd(commandParent, {0, 0, 80, 36})
        result.commands.backgroundStyle = .Window
        with result.playButton = IconButton.create(result.commands, result.theme().icon(.Play, SoundGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle = .Left
            .toolTip   = "Play"
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
            .toolTip   = "Stop"
            .enable(false)
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.stopPlayback()
            }
        }

        result.waveform                 = Wnd.create'SoundWaveformView(result, "sFileScope.sound.waveform")
        result.waveform.dockStyle       = .Center
        result.waveform.backgroundStyle = .View
        result.waveform.padding         = {32, 32, 32, 32}

        let sound = catch SoundFile.load(fileName) as loadError
        if loadError != null
        {
            result.details = "WAV · decode failed"
            let label = Label.create(result, "This WAV file could not be decoded.", {}, null, .WordWrap | .SecondaryText)
            label.dockStyle = .Center
            label.setTextAlignment(.Center, .Center)
            result.waveform.hide()
            result.applyLayout()
            return result
        }

        result.sound            = #move sound
        result.duration         = result.sound.durationInSeconds()
        result.waveform.samples = buildWaveform(result.sound.preloadedData(), result.sound.sampleEncoding(), result.sound.numChannels())
        let durationText = soundDurationText(result.duration)
        result.details = Format.toString("% Hz · % channel% · % bit · %", result.sound.sampleRateHz(), result.sound.numChannels(), result.sound.numChannels() == 1 ? "" : "s", result.sound.sampleStorageBits(), durationText)
        result.engineReady = acquireSoundEngine()
        if result.engineReady
        {
            result.timer = result.addTimer(33'ms)
            result.playButton.enable(true)
        }
        result.updatePlaybackUi()
        if !result.engineReady do
            result.playButton.toolTip = "Playback unavailable"
        result.applyLayout()
        result.setInitialFocus(result.playButton)
        return result
    }
}

// Creates the WAV playback and waveform view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd, details: *String)->#null *Wnd
{
    if apiVersion != ViewerPluginApiVersion do
        return null
    let view = SoundPluginView.create(contentParent, commandParent, fileName)
    commands[] = view.commands
    details[] = view.details
    return view
}
