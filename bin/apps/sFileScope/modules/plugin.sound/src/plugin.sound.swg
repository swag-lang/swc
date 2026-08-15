#global public

using Core, Pixel, Gui, Audio

private const ViewerPluginApiVersion = 3'u32
private const SoundGlyphSize = 18.0

// Slices the payload is reduced to. It is read back one column of pixels at a time, so it only
// has to stay ahead of the widest plot a window can give it; past that the columns repeat.
private const WaveformPointCount = 4096'u64

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
            sum += level
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
    using wnd: Wnd
    samples:   Array'WaveformPoint
    duration:  f32
    progress:  f32
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

        // The wave is ink, in the four weights that carry two readings at once. Across a column,
        // the transient reaches further than the body the ear hears; along the file, what has been
        // played is the stronger pair. The accent stays for the play head alone: a waveform washed
        // in it would be a window of accent pointing at nothing.
        let ink      = colors.label_Text
        let playBody = Color.lerp(colors.view_Bk, ink, 0.92)
        let playPeak = Color.lerp(colors.view_Bk, ink, 0.5)
        let restBody = Color.lerp(colors.view_Bk, ink, 0.55)
        let restPeak = Color.lerp(colors.view_Bk, ink, 0.28)

        let columns  = cast(u64) Math.max(plot.width, 1)
        let playHead = Math.clamp(.progress, 0, 1) * plot.width
        let scale    = plot.height * 0.5 - 1

        for column in columns
        {
            let first = column * .samples.count / columns
            let last  = Math.max((column + 1) * .samples.count / columns, first + 1)
            var peak  = 0'f32
            var body  = 0'f32
            for index in first until Math.min(last, .samples.count)
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

        result.sound             = #move sound
        result.duration          = result.sound.durationInSeconds()
        result.waveform.samples  = buildWaveform(result.sound.preloadedData(), result.sound.sampleEncoding(), result.sound.numChannels())
        result.waveform.duration = result.duration
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
