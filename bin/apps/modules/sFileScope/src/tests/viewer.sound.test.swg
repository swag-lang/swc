#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Audio

const TinyWav: [48] u8 = [
    0x52, 0x49, 0x46, 0x46, 0x28, 0x00, 0x00, 0x00,
    0x57, 0x41, 0x56, 0x45, 0x66, 0x6D, 0x74, 0x20,
    0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
    0x40, 0x1F, 0x00, 0x00, 0x40, 0x1F, 0x00, 0x00,
    0x01, 0x00, 0x08, 0x00, 0x64, 0x61, 0x74, 0x61,
    0x04, 0x00, 0x00, 0x00, 0x00, 0x80, 0xFF, 0x80]

// Builds a 16-bit mono WAV whose loudness moves the way real material does, so the picture the
// plot is judged on shows what the plot is for: bursts that decay, a transient above the body of
// each one, and silences between them.
func previewWav()->Array'u8
{
    const SampleRate  = 11_025'u64
    const FrameCount  = SampleRate * 2 + SampleRate / 2
    const PayloadSize = FrameCount * 2

    var result: retval
    result.resize(44 + PayloadSize)
    for value, index in TinyWav[0 until 44] do
        result[index] = value

    writeU32(&result, 4, cast(u32) (36 + PayloadSize))
    result[22] = 1                                        // One channel.
    writeU32(&result, 24, cast(u32) SampleRate)           // Frames per second.
    writeU32(&result, 28, cast(u32) (SampleRate * 2))     // Bytes per second.
    result[32] = 2                                        // Bytes per frame.
    result[34] = 16                                       // Bits per sample.
    writeU32(&result, 40, cast(u32) PayloadSize)

    for frame in FrameCount
    {
        let seconds  = cast(f32) frame / cast(f32) SampleRate
        let burst    = cast(u64) (seconds * 4)
        let inBurst  = seconds * 4 - cast(f32) burst
        var envelope = 0'f32
        if inBurst < 0.72 do
            envelope = (1 - inBurst / 0.72) * (0.35 + 0.16 * cast(f32) (burst % 5))

        // The carrier alone would make peak and body the same reading. The click on the first
        // frames of a burst is what separates them, which is the whole point of the two weights.
        let carrier   = Math.sin(seconds * (520 + 90 * cast(f32) burst) * 6.2831855)
        let click     = inBurst < 0.01 ? (frame & 1 ? 0.9'f32 : -0.9) : 0
        let value     = Math.clamp(carrier * envelope + click * envelope, -1, 1)
        let quantized = cast(s16) (value * 32_000)
        writeU16(&result, 44 + frame * 2, cast #bit (u16) quantized)
    }

    return result
}

func waveformFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/waveform.samples.txt")
}

func writeU16(bytes: *Array'u8, offset: u64, value: u16)
{
    bytes[offset]     = cast(u8) (value & 0xFF)
    bytes[offset + 1] = cast(u8) (value >> 8)
}

func writeU32(bytes: *Array'u8, offset: u64, value: u32)
{
    bytes[offset]     = cast(u8) (value & 0xFF)
    bytes[offset + 1] = cast(u8) ((value >> 8) & 0xFF)
    bytes[offset + 2] = cast(u8) ((value >> 16) & 0xFF)
    bytes[offset + 3] = cast(u8) ((value >> 24) & 0xFF)
}

func finishWaveform(view: *SoundViewer)
{
    if view.waveformThread.isValid() do
        view.waveformThread.wait()
    view.syncWaveform()
}

func waitForSoundOpen(host: *Testing.HeadlessHost, view: *SoundViewer)
{
    var attempts: u32
    while !view.openFinished and attempts < 5_000
    {
        Threading.Thread.sleep(1'ms)
        if view.timer do
            host.fireTimer(view.timer)
        attempts += 1
    }

    @assert(view.openFinished)
}

func markSoundOpenFailure(wnd: *Wnd, reason: string)
{
    discard reason
    let failed = cast(*bool) wnd.userData!
    failed[] = true
}

#test
{
    destroyEngine()
    @assert(acquireSoundEngine(.NoSound))
    @assert(isEngineCreated())
    @assert(acquireSoundEngine(.NoSound))

    releaseSoundEngine()
    @assert(isEngineCreated())
    releaseSoundEngine()
    @assert(!isEngineCreated())
    @assert(soundDurationText(0.25) == "250 ms")
    @assert(soundDurationText(2.5) == "2.50 s")
    @assert(mediaTimeText(5.9) == "0:05")
    @assert(mediaTimeText(65.9) == "1:05")
    @assert(mediaTimeText(3_665.0) == "1:01:05")
    @assert(mediaTimeRangeText(5, 65) == "0:05 / 1:05")
    @assert(mediaTimeRangeText(0, 0.5) == "0:00 / 0:01")
}

// A WAV decoder refusal crosses the progressive viewer boundary without blocking its creator.
#test
{
    let fileName = Gui.Testing.tempFilePath("filescope-sound-", ".wav")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not a WAV")

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()

    var failed: bool
    let request = ViewerRequest{contentParent: &host.root, commandParent: &host.root, fileName: fileName, reportFailure: &markSoundOpenFailure}
    var result: ViewerResult
    createSoundViewer(&request, &result)
    @assert(result.view != null and result.commands != null)
    @assert(result.isLoading != null and result.needsLoadingOverlay != null)
    let view = cast(*SoundViewer) result.view!
    view.userData = &failed
    @assert(result.isLoading!(view) and result.needsLoadingOverlay!(view))
    waitForSoundOpen(&host, view)
    @assert(failed and !view.openFailure.isEmpty())
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("filescope_sound_%.wav", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, TinyWav)

    @assert(acquireSoundEngine(.NoSound))
    defer releaseSoundEngine()

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 80, 36})
    let request  = ViewerRequest{&host.root, commands, fileName}
    var result: ViewerResult
    createSoundViewer(&request, &result)
    @assert(result.view != null)
    @assert(result.commands != null and result.isLoading != null and result.needsLoadingOverlay != null)
    let view = cast(*SoundViewer) result.view!
    @assert(result.isLoading!(view) and result.needsLoadingOverlay!(view))
    waitForSoundOpen(&host, view)
    @assert(!result.needsLoadingOverlay!(view))
    @assert(view.engineReady and view.playButton.isEnabled())
    @assert(view.backwardButton.icon.isValid() and view.forwardButton.icon.isValid())
    @assert(view.muteButton.icon.isValid() and view.muteButton.flags.has(.Toggle))
    @assert(!view.sound.isDataPreloaded())
    @assert(view.waveform.samples.count == 4)
    finishWaveform(view)
    @assert(!result.isLoading!(view))
    @assert(view.waveform.readyCount == 4)
    @assert(view.timeline.isEnabled() and view.timeLabel.text() == "0:00 / 0:01")

    // A second file opened after the engine exists must decode exactly like the first one: the
    // waveform of every file but the first went missing when a failure inside the engine was
    // swallowed on its way out of the module.
    let replacementCommands = Wnd.create'Wnd(&host.root, {0, 0, 80, 36})
    let replacementRequest  = ViewerRequest{&host.root, replacementCommands, fileName}
    var replacementResult: ViewerResult
    createSoundViewer(&replacementRequest, &replacementResult)
    @assert(replacementResult.view != null)
    let replacement = cast(*SoundViewer) replacementResult.view!
    waitForSoundOpen(&host, replacement)
    finishWaveform(replacement)
    @assert(replacement.engineReady and replacement.playButton.isEnabled())
    @assert(replacement.waveform.samples.count == view.waveform.samples.count)
    @assert(replacement.duration == view.duration)
    @assert(replacement.details == view.details)

    view.togglePlayback()
    @assert(view.playing and view.voice != null)
    view.seekSeconds(view.duration * 0.5)
    @assert(view.voice!.playbackSampleFrame() == 2)
    view.setVolume(0.4)
    @assert(Math.isEqualEpsilon(expect view.voice!.volume(), 0.4, 0.001))
    view.setMuted(true)
    @assert(view.muted and view.muteButton.isChecked)
    @assert(Math.isEqualEpsilon(expect view.voice!.volume(), 0, 0.001))
    view.setMuted(false)
    @assert(Math.isEqualEpsilon(expect view.voice!.volume(), 0.4, 0.001))
    view.togglePlayback()
    @assert(!view.playing)
    view.stopPlayback()
    @assert(view.elapsed == 0)
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), "viewer.sound.preview.wav")
    defer discard catch File.delete(fileName)
    let wav = previewWav()
    discard expect File.writeAllBytes(fileName, wav.toSlice())

    @assert(acquireSoundEngine(.NoSound))
    defer releaseSoundEngine()

    var host: Testing.HeadlessHost
    host.setup(720, 420)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let commandBar = Wnd.create'Wnd(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Bottom
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}
    let request = ViewerRequest{&host.root, commandBar, fileName}
    var result: ViewerResult
    createSoundViewer(&request, &result)
    @assert(result.view != null)
    let view = cast(*SoundViewer) result.view!
    waitForSoundOpen(&host, view)
    finishWaveform(view)
    view.dockStyle          = .Center
    view.commands.dockStyle = .Center

    // Photographed mid-playback: the picture has to show the played part apart from the rest, the
    // play head between them, and the graduated scale under both.
    view.elapsed = view.duration * 0.38
    view.updatePlaybackUi()
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.sound.document")
}

#test
{
    let fixture = expect File.readAllText(waveformFixturePath())
    @assert(Utf8.contains(fixture.toString(), "1.0") and Utf8.contains(fixture.toString(), "-1.0"))
    let samples = buildWaveform([0'u8, 128'u8, 255'u8], .Pcm8, 1)
    @assert(samples.count == 3)
    @assert(samples[0].peak == 1 and samples[1].peak == 0 and samples[2].peak > 0.99)
    @assert(samples[0].body == samples[0].peak)
}

#test
{
    let samples = buildWaveform([0'u8, 0x80'u8, 0'u8, 0'u8, 0xFF'u8, 0x7F'u8], .Pcm16, 1)
    @assert(samples.count == 3)
    @assert(samples[0].peak == 1 and samples[1].peak == 0 and samples[2].peak > 0.99)
}

// One slice covering several frames reports the loudest of them and the mean of them, and the two
// are only equal when the slice is flat.
#test
{
    var payload: Array'u8
    payload.resize(8)
    for index in payload.count do
        payload[index] = index == 0 ? 255'u8 : 128'u8

    let samples = buildWaveform(payload.toSlice(), .Pcm8, 1)
    @assert(samples.count == 8)
    @assert(samples[0].peak > 0.99 and samples[0].body > 0.99)

    let single = buildWaveform(payload.toSlice()[0 until 4], .Pcm8, 1)
    @assert(single.count == 4)
    @assert(single[0].peak > 0.99 and single[1].peak == 0)
}

// The time scale is graduated on numbers a reader thinks in, and its labels shorten with the step.
#test
{
    @assert(waveformTickStep(4.2, 640) == 1)
    @assert(waveformTickStep(0.7, 640) == 0.25)
    @assert(waveformTickStep(600, 640) == 120)
    @assert(waveformTickText(2, 1) == "2")
    @assert(waveformTickText(0.5, 0.25) == "0.50")
    @assert(waveformTickText(95, 30) == "1:35")
}

// Reads a recorded sound rather than a synthesized one. Its metadata and waveform must not depend
// on whether a playback device can be opened.
#test
{
    let pacmanWav = Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "pacman_beginning.wav")
    let sound     = expect SoundFile.load(pacmanWav.toString())
    @assert(sound.sampleRateHz() == 11_025)
    @assert(sound.numChannels() == 1)
    @assert(sound.sampleStorageBits() == 8)
    @assert(sound.durationInSeconds() > 4.2 and sound.durationInSeconds() < 4.3)
    let waveform = buildWaveform(sound.preloadedData(), sound.sampleEncoding(), sound.numChannels())
    @assert(waveform.count == 4_096)
    var visible: bool
    for sample in waveform where sample.peak > 0.05 and sample.body > 0
    {
        visible = true
        break
    }

    @assert(visible)

    var host: Testing.HeadlessHost
    host.setup(640, 320)
    defer host.shutdown()
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 80, 36})
    let request  = ViewerRequest{&host.root, commands, pacmanWav.toString()}
    var result: ViewerResult
    createSoundViewer(&request, &result)
    @assert(result.view != null)
    let view = cast(*SoundViewer) result.view!
    waitForSoundOpen(&host, view)
    @assert(!view.sound.isDataPreloaded())
    finishWaveform(view)
    @assert(view.details.indexOf("11025") != Swag.U64.Max)
    @assert(view.details.indexOf("8 bit") != Swag.U64.Max)
    @assert(view.waveform.samples.count == 4_096)
    @assert(view.waveform.readyCount == view.waveform.samples.count)
    @assert(view.waveform.duration == view.duration)
}
