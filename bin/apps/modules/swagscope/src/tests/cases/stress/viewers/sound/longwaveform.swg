#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Audio, Viewers

func storeWavSize(bytes: *Array'u8, at: u64, value: u32)
{
    for index in 4 do
        bytes[at + index] = cast(u8, (value >> (index * 8)) & 0xFF)
}

// Reduce a five-minute recording to a bounded waveform and seek near its end.
#[Swag.TestTag("stress")]
#test
{
    const SampleRate = 11_025'u64
    const Frames = SampleRate * 60 * 5
    const PayloadSize = Frames * 2
    let file = Testing.tempFilePath("scope-long-waveform-", ".wav")
    defer discard catch File.delete(file)
    var wav = previewWav()
    let initialSize = wav.count
    wav.resize(44 + PayloadSize)
    for index in wav.count - initialSize do
        wav[initialSize + index] = 0
    storeWavSize(&wav, 4, cast(u32, 36 + PayloadSize))
    storeWavSize(&wav, 40, cast(u32, PayloadSize))
    expect File.writeAllBytes(file, wav.toSlice())

    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    host.setup(820, 480)
    var session = openTestViewer(Sound.viewerPlugin(), &host.root, file,
                                 commandParent: &host.root)
    Swag.require(session.view != null)
    let view = assume cast(*Sound.Panel, session.view)
    waitForSoundOpen(&host, view)
    finishWaveform(view)
    Swag.require(Math.abs(view.duration - 300) < 0.01)
    Swag.require(view.waveform.samples.count == 4_096 and
                 view.waveform.readyCount == view.waveform.samples.count)

    view.dockStyle = .Center
    host.root.applyLayout()
    view.seekSeconds(270)
    Swag.require(Math.abs(view.elapsed - 270) < 0.01 and view.waveform.progress > 0.89)
    var image = host.render(&host.root)
    Swag.require(image.isValid())
}
