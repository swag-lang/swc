#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Audio

private const TinyWav: [48] u8 = [
    0x52, 0x49, 0x46, 0x46, 0x28, 0x00, 0x00, 0x00,
    0x57, 0x41, 0x56, 0x45, 0x66, 0x6D, 0x74, 0x20,
    0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
    0x40, 0x1F, 0x00, 0x00, 0x40, 0x1F, 0x00, 0x00,
    0x01, 0x00, 0x08, 0x00, 0x64, 0x61, 0x74, 0x61,
    0x04, 0x00, 0x00, 0x00, 0x00, 0x80, 0xFF, 0x80,
]

private func previewWav()->Array'u8
{
    const SampleCount = 800'u64
    var result: retval
    result.resize(44 + SampleCount)
    for value, index in TinyWav[0 until 44] do
        result[index] = value
    result[4]  = 0x44
    result[5]  = 0x03
    result[40] = 0x20
    result[41] = 0x03
    for index in SampleCount do
        result[44 + index] = cast(u8) ((index % 64) * 4)
    return result
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
    let view     = SoundPluginView.create(&host.root, commands, fileName)
    @assert(view.engineReady and view.playButton.isEnabled())
    @assert(view.waveform.samples.count == 4)
    let replacementCommands = Wnd.create'Wnd(&host.root, {0, 0, 80, 36})
    let replacement         = SoundPluginView.create(&host.root, replacementCommands, fileName)
    @assert(replacement.engineReady and replacement.playButton.isEnabled())

    view.togglePlayback()
    @assert(view.playing and view.voice != null)
    view.togglePlayback()
    @assert(!view.playing)
    view.stopPlayback()
    @assert(view.elapsed == 0)
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), "plugin.sound.preview.wav")
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
    commandBar.dockStyle       = .Top
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}
    let view = SoundPluginView.create(&host.root, commandBar, fileName)
    view.dockStyle          = .Center
    view.commands.dockStyle = .Right
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "plugin.sound.document")
}

#test
{
    let samples = buildWaveform([0'u8, 128'u8, 255'u8], .Pcm8, 1)
    @assert(samples.count == 3)
    @assert(samples[0] == 1 and samples[1] == 0 and samples[2] > 0.99)
}

#test
{
    let samples = buildWaveform([0'u8, 0x80'u8, 0'u8, 0'u8, 0xFF'u8, 0x7F'u8], .Pcm16, 1)
    @assert(samples.count == 3)
    @assert(samples[0] == 1 and samples[1] == 0 and samples[2] > 0.99)
}

// Reproduces the asset reported with sFileScope when the adjacent examples workspace is present.
// Its metadata and waveform must not depend on whether a playback device can be opened.
#test
{
    let sourceDirectory = Path.directoryName(#curlocation.fileName)!
    let pacmanWav       = Path.combine(sourceDirectory, "../../../../../../../swag/bin/examples/scripts/datas/pacman/audio/pacman_beginning.wav")
    if !File.exists(pacmanWav) do
        return

    let sound = expect SoundFile.load(pacmanWav.toString())
    @assert(sound.sampleRateHz() == 11_025)
    @assert(sound.numChannels() == 1)
    @assert(sound.sampleStorageBits() == 8)
    @assert(sound.durationInSeconds() > 4.2 and sound.durationInSeconds() < 4.3)
    let waveform = buildWaveform(sound.preloadedData(), sound.sampleEncoding(), sound.numChannels())
    @assert(waveform.count == 2_048)
    var visible: bool
    for sample in waveform where sample > 0.05
    {
        visible = true
        break
    }
    @assert(visible)

    var host: Testing.HeadlessHost
    host.setup(640, 320)
    defer host.shutdown()
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 80, 36})
    let view = SoundPluginView.create(&host.root, commands, pacmanWav.toString())
    @assert(view.details.indexOf("11025") != Swag.U64.Max)
    @assert(view.details.indexOf("8 bit") != Swag.U64.Max)
    @assert(view.waveform.samples.count == 2_048)
}
