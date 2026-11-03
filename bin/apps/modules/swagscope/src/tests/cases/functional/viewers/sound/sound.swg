#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Audio, Viewers

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
internal func previewWav()->Array'u8
{
    const SampleRate  = 11_025'u64
    const FrameCount  = SampleRate * 2 + SampleRate / 2
    const PayloadSize = FrameCount * 2

    var result: #returntype
    result.resize(44 + PayloadSize)
    for value, index in TinyWav[0 until 44] do
        result[index] = value

    writeU32(&result, 4, cast(u32, 36 + PayloadSize))
    result[22] = 1                                       // One channel.
    writeU32(&result, 24, cast(u32, SampleRate))         // Frames per second.
    writeU32(&result, 28, cast(u32, SampleRate * 2))     // Bytes per second.
    result[32] = 2                                       // Bytes per frame.
    result[34] = 16                                      // Bits per sample.
    writeU32(&result, 40, cast(u32, PayloadSize))

    for frame in FrameCount
    {
        let seconds  = cast(f32, frame) / cast(f32, SampleRate)
        let burst    = cast(u64, seconds * 4)
        let inBurst  = seconds * 4 - cast(f32, burst)
        var envelope = 0'f32
        if inBurst < 0.72 do
            envelope = (1 - inBurst / 0.72) * (0.35 + 0.16 * cast(f32, burst % 5))

        // The carrier alone would make peak and body the same reading. The click on the first
        // frames of a burst is what separates them, which is the whole point of the two weights.
        let carrier   = Math.sin(seconds * (520 + 90 * cast(f32, burst)) * 6.2831855)
        let click     = inBurst < 0.01 ? (frame & 1 ? 0.9'f32 : -0.9) : 0
        let value     = Math.clamp(carrier * envelope + click * envelope, -1, 1)
        let quantized = cast(s16, value * 32_000)
        writeU16(&result, 44 + frame * 2, cast #bit (u16, quantized))
    }

    return result
}

func waveformFixturePath()->String => scopeTestDataPath("waveform.samples.txt")

func writeU16(bytes: *Array'u8, offset: u64, value: u16)
{
    bytes[offset]     = cast(u8, value & 0xFF)
    bytes[offset + 1] = cast(u8, value >> 8)
}

func writeU32(bytes: *Array'u8, offset: u64, value: u32)
{
    bytes[offset]     = cast(u8, value & 0xFF)
    bytes[offset + 1] = cast(u8, ((value >> 8) & 0xFF))
    bytes[offset + 2] = cast(u8, ((value >> 16) & 0xFF))
    bytes[offset + 3] = cast(u8, ((value >> 24) & 0xFF))
}

internal func finishWaveform(view: *Sound.Panel)
{
    view.waveformTask.wait()
    view.syncWaveform()
}

internal func waitForSoundOpen(host: *Testing.HeadlessHost, view: *Sound.Panel)
{
    view.openTask.wait()
    host.pump()
    Swag.require(view.openFinished)
}

func markSoundOpenFailure(wnd: *Wnd, _: string)
{
    let failed = cast(*bool, unwrap wnd.userData)
    failed[] = true
}

#test
{
    destroyEngine()
    Swag.require(Sound.acquireEngine(.NoSound))
    Swag.require(isEngineCreated())
    Swag.require(Sound.acquireEngine(.NoSound))

    Sound.releaseEngine()
    Swag.require(isEngineCreated())
    Sound.releaseEngine()
    Swag.require(not isEngineCreated())
    Swag.require(Sound.durationText(0.25) == "250 ms")
    Swag.require(Sound.durationText(2.5) == "2.50 s")
    Swag.require(Viewer.timeText(5.9) == "0:05")
    Swag.require(Viewer.timeText(65.9) == "1:05")
    Swag.require(Viewer.timeText(3_665.0) == "1:01:05")
    Swag.require(Viewer.timeRangeText(5, 65) == "0:05 / 1:05")
    Swag.require(Viewer.timeRangeText(0, 0.5) == "0:00 / 0:01")
}

// A WAV decoder refusal crosses the progressive viewer boundary without blocking its creator.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-sound-", ".wav")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not a WAV")

    var host: Testing.HeadlessHost
    host.setup(640, 420)

    var failed: bool
    var result = openTestViewer(Sound.viewerPlugin(), &host.root, fileName, commandParent: &host.root, services: {reportFailure: &markSoundOpenFailure})
    Swag.require(result.view != null and result.commands != null)
    Swag.require(result.isLoading != null and result.needsLoadingOverlay != null)
    let view = assume cast(*Sound.Panel, result.view)
    view.userData = &failed
    Swag.require(result.isLoading() and result.needsLoadingOverlay())
    waitForSoundOpen(&host, view)
    Swag.require(failed and not view.opened)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-sound-", ".wav")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, TinyWav)

    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 80, 36})
    var result   = openTestViewer(Sound.viewerPlugin(), &host.root, fileName, commandParent: commands)
    Swag.require(result.view != null)
    Swag.require(result.commands != null and result.isLoading != null and result.needsLoadingOverlay != null)
    let view = assume cast(*Sound.Panel, result.view)
    Swag.require(result.isLoading() and result.needsLoadingOverlay())
    waitForSoundOpen(&host, view)
    Swag.require(not result.needsLoadingOverlay())
    Swag.require(view.engineReady and view.playButton.isEnabled())
    Swag.require(view.backwardButton.icon.isValid() and view.forwardButton.icon.isValid())
    Swag.require(view.muteButton.icon.isValid() and view.muteButton.flags.has(.Toggle))
    Swag.require(not view.sound.isDataPreloaded())
    Swag.require(view.waveform.samples.count == 4)
    finishWaveform(view)
    Swag.require(not result.isLoading())
    Swag.require(view.waveform.readyCount == 4)
    Swag.require(view.timeline.isEnabled() and view.timeLabel.text() == "0:00 / 0:01")

    // A second file opened after the engine exists must decode exactly like the first one: a
    // failure swallowed inside the engine on its way out of the module would leave every waveform
    // but the first one empty.
    let replacementCommands = Wnd.create'Wnd(&host.root, {0, 0, 80, 36})
    var replacementResult   = openTestViewer(Sound.viewerPlugin(), &host.root, fileName, commandParent: replacementCommands)
    Swag.require(replacementResult.view != null)
    let replacement = assume cast(*Sound.Panel, replacementResult.view)
    waitForSoundOpen(&host, replacement)
    finishWaveform(replacement)
    Swag.require(replacement.engineReady and replacement.playButton.isEnabled())
    Swag.require(replacement.waveform.samples.count == view.waveform.samples.count)
    Swag.require(replacement.duration == view.duration)
    Swag.require(replacement.details == view.details)

    // Who made the recording stands under its name on the page; the readings say how it is stored.
    view.tags.albumArtist = "Various Artists"
    view.tags.year        = "1999"
    view.refreshDetails()
    Swag.require(view.credits() == "Various Artists · 1999" and not Utf8.contains(view.details.toString(), "Various Artists"))
    view.tags = {}
    view.refreshDetails()
    Swag.require(view.credits().isEmpty())

    view.togglePlayback()
    Swag.require(view.playing and view.voice != null)

    let voice  = view.voice
    let oldTip = String.from(view.playButton.toolTip)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(view.playButton.toolTip == Sound.texts().ui_TipPause and view.playButton.toolTip != oldTip)
    Swag.require(view.stopButton.toolTip == Sound.texts().ui_TipStop)
    Swag.require(view.volumeSlider.toolTip == Sound.texts().ui_TipVolume)
    Swag.require(view.playing and view.voice == voice)
    Swag.require(view.details == Format.toString(Sound.texts().ui_Details, view.sound.sampleRateHz(), Sound.channelCountText(view.sound.numChannels()), view.sound.sampleStorageBits(), Sound.durationText(view.duration)))
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
    Swag.require(view.playButton.toolTip == oldTip and view.playing and view.voice == voice)
    view.seekSeconds(view.duration * 0.5)
    Swag.require(view.voice.playbackSampleFrame() == 2)
    view.setVolume(0.4)
    Swag.require(Math.isEqualEpsilon(expect view.voice.volume(), 0.4, 0.001))
    view.setMuted(true)
    Swag.require(view.muted and view.muteButton.isChecked)
    Swag.require(Math.isEqualEpsilon(expect view.voice.volume(), 0, 0.001))
    view.setMuted(false)
    Swag.require(Math.isEqualEpsilon(expect view.voice.volume(), 0.4, 0.001))

    // A player the reader switches away from pauses, and is still paused when it comes back.
    view.hide()
    Swag.require(not view.playing)
    view.show()
    Swag.require(not view.playing)
    view.togglePlayback()
    Swag.require(view.playing)

    view.togglePlayback()
    Swag.require(not view.playing)
    var reading: ViewerReadingState
    reading.capture(&result, "sound", "")
    view.stopPlayback()
    view.setVolume(1)
    Swag.require(view.elapsed == 0)
    reading.applySettings(&result)
    let restored = reading.restore(&result)
    Swag.require(restored and not view.playing)
    Swag.require(Math.isEqualEpsilon(view.elapsed, cast(f32, reading.seconds), 0.00001))
    Swag.require(view.volume == 0.4 and not view.muted)
    Swag.require(Math.isEqualEpsilon(view.volumeSlider.value(), 0.4, 0.001))
}

#test
{
    let fixture = expect File.readAllText(waveformFixturePath())
    Swag.require(Utf8.contains(fixture, "1.0") and Utf8.contains(fixture, "-1.0"))
    let samples = Sound.buildWaveform([0'u8, 128'u8, 255'u8], .Pcm8, 1)
    Swag.require(samples.count == 3)
    Swag.require(samples[0].peak == 1 and samples[1].peak == 0 and samples[2].peak > 0.99)
    Swag.require(samples[0].body == samples[0].peak)
}

#test
{
    let samples = Sound.buildWaveform([0'u8, 0x80'u8, 0'u8, 0'u8, 0xFF'u8, 0x7F'u8], .Pcm16, 1)
    Swag.require(samples.count == 3)
    Swag.require(samples[0].peak == 1 and samples[1].peak == 0 and samples[2].peak > 0.99)
}

// Packed samples retain their byte order and sign; floating samples are clamped after decoding.
#test
{
    let pcm24: [7] u8 = [0xAA, 0x00, 0x00, 0x80, 0x00, 0x00, 0x40]
    Swag.require(Sound.sampleAt(pcm24, 1, .Pcm24) == -1)
    Swag.require(Sound.sampleAt(pcm24, 4, .Pcm24) == 0.5)

    let pcm32: [9] u8 = [0xAA, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x40]
    Swag.require(Sound.sampleAt(pcm32, 1, .Pcm32) == -1)
    Swag.require(Sound.sampleAt(pcm32, 5, .Pcm32) == 0.5)

    let floats: [12] u8 = [0x00, 0x00, 0x00, 0x3F,
                           0x00, 0x00, 0x00, 0x40,
                           0x00, 0x00, 0x00, 0xC0]
    Swag.require(Sound.sampleAt(floats, 0, .Float32) == 0.5)
    Swag.require(Sound.sampleAt(floats, 4, .Float32) == 1)
    Swag.require(Sound.sampleAt(floats, 8, .Float32) == -1)
}

// One slice covering several frames reports the loudest of them and the mean of them, and the two
// are only equal when the slice is flat.
#test
{
    var payload: Array'u8
    payload.resize(8)
    for index in payload.count do
        payload[index] = index == 0 ? 255'u8 : 128'u8

    let samples = Sound.buildWaveform(payload.toSlice(), .Pcm8, 1)
    Swag.require(samples.count == 8)
    Swag.require(samples[0].peak > 0.99 and samples[0].body > 0.99)

    let single = Sound.buildWaveform(payload.toSlice()[0 until 4], .Pcm8, 1)
    Swag.require(single.count == 4)
    Swag.require(single[0].peak > 0.99 and single[1].peak == 0)
}

// Reads a recorded sound rather than a synthesized one. Its metadata and waveform must not depend
// on whether a playback device can be opened.
#test
{
    let pacmanWav = scopeTestDataPath("pacman_beginning.wav")
    let sound     = expect SoundFile.load(pacmanWav)
    Swag.require(sound.sampleRateHz() == 11_025)
    Swag.require(sound.numChannels() == 1)
    Swag.require(sound.sampleStorageBits() == 8)
    Swag.require(sound.durationInSeconds() > 4.2 and sound.durationInSeconds() < 4.3)
    let waveform = Sound.buildWaveform(sound.preloadedData(), sound.sampleEncoding(), sound.numChannels())
    Swag.require(waveform.count == 4_096)
    var visible: bool
    for sample in waveform where sample.peak > 0.05 and sample.body > 0
    {
        visible = true
        break
    }

    Swag.require(visible)

    var host: Testing.HeadlessHost
    host.setup(640, 320)
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 80, 36})
    var result   = openTestViewer(Sound.viewerPlugin(), &host.root, pacmanWav, commandParent: commands)
    Swag.require(result.view != null)
    let view = assume cast(*Sound.Panel, result.view)
    waitForSoundOpen(&host, view)
    Swag.require(not view.sound.isDataPreloaded())
    finishWaveform(view)
    Swag.require(view.details.indexOf("11025") != Swag.U64.Max)
    Swag.require(view.details.indexOf("8 bit") != Swag.U64.Max)
    Swag.require(view.waveform.samples.count == 4_096)
    Swag.require(view.waveform.readyCount == view.waveform.samples.count)
    Swag.require(view.waveform.duration == view.duration)
}

// Answers a sound that has been played through with the continuation stored on the view.
func answerSoundEnd(wnd: *Wnd)->Viewer.Continuation
{
    let answer = cast(*Viewer.Continuation, unwrap wnd.userData)
    return answer[]
}

// Played through, a sound does what the host's answer calls for: a replay starts again from the
// first sample without leaving the playing state, and any other answer stops it.
#test
{
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp), "viewer.sound.finish.wav")
    defer discard catch File.delete(fileName)
    let wav = previewWav()
    expect File.writeAllBytes(fileName, wav.toSlice())

    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var host: Testing.HeadlessHost
    host.setup(720, 420)

    let commands = Wnd.create'Wnd(&host.root, {0, 0, 480, 36})
    var result   = openTestViewer(Sound.viewerPlugin(), &host.root, fileName, commandParent: commands, services: {reportFinished: &answerSoundEnd})
    Swag.require(result.view != null)
    let view   = assume cast(*Sound.Panel, result.view)
    var answer = Viewer.Continuation.Replay
    view.userData = &answer
    waitForSoundOpen(&host, view)
    finishWaveform(view)
    view.togglePlayback()
    Swag.require(view.playing and view.voice != null)

    view.finishPlayback()
    Swag.require(view.playing and view.voice.isPlaying() and view.elapsed == 0)

    answer = .Next
    view.finishPlayback()
    Swag.require(not view.playing and not view.voice.isPlaying())
}
