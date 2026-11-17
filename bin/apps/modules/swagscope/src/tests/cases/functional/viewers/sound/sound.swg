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

    // The information sheet gives every tag the file names, the track and the genre among them.
    view.tags.track = "4/12"
    view.tags.genre = "Ambient"
    let sheet = InfoSheet.create(&host.root)
    view.describeInformation(sheet)
    let information = sheet.text()
    Swag.require(Utf8.contains(information, "Tags\nAlbum artist\nVarious Artists\nYear\n1999\nTrack\n4/12\nGenre\nAmbient"), information)
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

// Reduces interleaved `samples` of `channels` channels to `pointCount` points in one chunk, the
// way the viewer's worker reduces each chunk the decoder hands it.
func reduceWaveform(samples: const [..] s16, channels: u32, pointCount: u64)->Array'Sound.WaveformPoint
{
    var result: Array'Sound.WaveformPoint
    result.resize(pointCount)
    var reducer = Sound.WaveformReducer{&result, samples.count / channels, pointCount, channels}
    reducer.consume(samples)
    reducer.finish()
    Swag.require(reducer.readyCount == pointCount)
    return result
}

// One point per frame reads the level of that frame, whatever its sign.
#test
{
    var samples: Array's16
    let fixture = expect File.readAllText(waveformFixturePath())
    for line in Tokenize.split(fixture, '\n'u8)
    {
        let text = Latin1.trim(line)
        if not text.count or text[0] == '#' do
            continue
        let value = expect StrConv.toF64(text)
        samples.add(cast(s16, Math.clamp(Math.round(value * 32768), -32768, 32767)))
    }

    let points = reduceWaveform(samples.toSlice(), 1, samples.count)
    Swag.require(points.count == 7)
    Swag.require(points[0].peak == 0 and points[1].peak > 0.99 and points[4].peak == 1)
    Swag.require(points[2].peak == 0.5 and points[3].peak == 0.5 and points[5].peak == 0.25)
    Swag.require(points[1].body == points[1].peak)
}

// One slice covering several frames reports the loudest of them and the mean of them, and the two
// are only equal when the slice is flat. Channels are mixed before either is read.
#test
{
    let mono = reduceWaveform([32767's16, 0, 0, 0], 1, 2)
    Swag.require(mono[0].peak > 0.99 and mono[0].body > 0.49 and mono[0].body < 0.51)
    Swag.require(mono[1].peak == 0 and mono[1].body == 0)

    let stereo = reduceWaveform([16384's16, 16384, -16384, 16384], 2, 2)
    Swag.require(stereo[0].peak == 0.5 and stereo[1].peak == 0)
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
    var visible: bool
    for sample in view.waveform.samples where sample.peak > 0.05 and sample.body > 0
    {
        visible = true
        break
    }

    Swag.require(visible)
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

// A recording stored beside its sleeve shows that sleeve as its cover; without one the cover stays
// the neutral record, and a sleeve too large to be a picture of the album is passed over.
#test
{
    let folder = Gui.Testing.tempFilePath("scope-sleeve-", "")
    expect Directory.create(folder, recurse: true)
    let fileName = Path.combine(folder, "track.wav")
    expect File.writeAllBytes(fileName, TinyWav)
    defer discard catch File.delete(fileName)
    Swag.require(not Sound.localSleeve(fileName).isValid())

    let sleeve  = Path.combine(folder, "cover.png")
    let picture = expect File.readAllBytes(scopeTestDataPath("title.png"))
    expect File.writeAllBytes(sleeve, picture.toSlice())
    defer discard catch File.delete(sleeve)
    let image = Sound.localSleeve(fileName)
    Swag.require(image.isValid() and Math.max(image.width, image.height) <= cast(s32, Sound.CoverSize * 2))

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    var result = openTestViewer(Sound.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view   = assume cast(*Sound.Panel, result.view)
    waitForSoundOpen(&host, view)
    Swag.require(view.opened and view.cover.isValid() and not view.coverImage.isValid())
}

// A sleeve the recording embeds in its tags is decoded and fitted like one beside it, and its
// encoded bytes are let go; one that does not decode gives no cover.
#test
{
    var tags: SoundTags
    tags.picture = expect File.readAllBytes(scopeTestDataPath("title.png"))
    tags.pictureExtension = ".png"
    let image = Sound.embeddedSleeve(&tags)
    Swag.require(image.isValid() and Math.max(image.width, image.height) <= cast(s32, Sound.CoverSize * 2))
    Swag.require(tags.picture.isEmpty())

    tags.picture.add(0xFF'u8)
    tags.picture.add(0xD8'u8)
    tags.pictureExtension = ".jpg"
    Swag.require(not Sound.embeddedSleeve(&tags).isValid())
}

// The thumbnail of a recording that embeds its sleeve is that sleeve, fitted to the size asked for,
// rather than a waveform.
#test
{
    let png = expect File.readAllBytes(scopeTestDataPath("title.png"))
    var frame: Array'u8
    frame.add(0'u8)
    for byte in "image/png" do
        frame.add(byte)
    frame.add(0'u8)
    frame.add(3'u8)
    frame.add(0'u8)
    for byte in png do
        frame.add(byte)

    var file: Array'u8
    for byte in "ID3" do
        file.add(byte)
    for byte in [3'u8, 0, 0] do
        file.add(byte)
    let size = frame.count + 10
    for shift in [21'u64, 14, 7, 0] do
        file.add(cast(u8, (size >> shift) & 0x7F))
    for byte in "APIC" do
        file.add(byte)
    for shift in [24'u64, 16, 8, 0] do
        file.add(cast(u8, (frame.count >> shift) & 0xFF))
    file.add(0'u8)
    file.add(0'u8)
    for byte in frame do
        file.add(byte)

    let fileName = Gui.Testing.tempFilePath("scope-sound-sleeve-", ".mp3")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, file.toSlice())

    let plugin = Sound.viewerPlugin()
    let image  = expect plugin.thumbnail!(fileName, 96)

    // The 5000 × 367 banner keeps its shape; a waveform would be half as tall as it is wide.
    Swag.require(image.isValid() and image.width == 96 and image.height == 7)
}

// Shift and an arrow step the rate of a recording through the rates a film offers, the lens
// steps it too, and the summary declares a rate other than the source one.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-sound-rate-", ".wav")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, TinyWav)
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 80, 36})
    var result   = openTestViewer(Sound.viewerPlugin(), &host.root, fileName, commandParent: commands)
    let view     = assume cast(*Sound.Panel, result.view)
    waitForSoundOpen(&host, view)
    Swag.require(view.playbackRate == 1)

    var faster = KeyEvent{kind: .Pressed, key: .Right, modifiers: .Shift}
    view.sendEvent(&faster)
    Swag.require(view.playbackRate == 1.25 and Utf8.contains(view.details.toString(), "1.25×"))

    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Sound", host.theme)
    view.describeLens(&entries)
    for &entry in results.sections[0]!.entries where entry.title == Sound.texts().cmd_Slower do
        entry.run!()
    Swag.require(view.playbackRate == 1 and not Utf8.contains(view.details.toString(), "×"))

    for 9 do
        view.sendEvent(&faster)
    Swag.require(view.playbackRate == Viewer.PlaybackRates[Viewer.PlaybackRates.count - 1])
}

// A colon and an instant, or a displacement in seconds, in the lens move a recording there; an
// instant past its end offers nothing.
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("pacman_beginning.wav"), false)
    let view   = assume cast(*Sound.Panel, window.instances[window.activeChoiceIndex].view)
    waitForSoundOpen(&host, view)
    Swag.require(view.playButton.isEnabled() and view.duration > 3)

    window.lens.open(":0:02")
    host.finishAnimations()
    let section = unwrap window.lens.results.sections[0]
    Swag.require(section.entries[0].title == Format.toString(appStrings().lens_GoToTime, "0:02"))
    section.entries[0].run!()
    window.lens.close()
    host.finishAnimations()
    Swag.require(Math.abs(view.elapsed - 2) < 0.05)

    window.lens.open(":+1")
    host.finishAnimations()
    Swag.require((unwrap window.lens.results.sections[0]).entries[0].title == Format.toString(appStrings().lens_GoToTime, "0:03 (+1)"))
    window.lens.close()
    host.finishAnimations()

    window.lens.open(":59:00")
    host.finishAnimations()
    Swag.require(window.lens.results.sections.isEmpty())
    window.lens.close()
    host.finishAnimations()
}

// Writes `samples` as a 16-bit mono WAV at 8 kHz.
func pcm16Wav(samples: const [..] s16)->Array'u8
{
    var result: #returntype
    result.resize(44 + samples.count * 2)
    for value, index in TinyWav[0 until 44] do
        result[index] = value
    writeU32(&result, 4, cast(u32, 36 + samples.count * 2))
    writeU32(&result, 28, 16_000)     // Bytes per second.
    result[32] = 2      // Bytes per frame.
    result[34] = 16     // Bits per sample.
    writeU32(&result, 40, cast(u32, samples.count * 2))
    for sample, index in samples do
        writeU16(&result, 44 + index * 2, cast #bit (u16, sample))
    return result
}

// Opens `bytes` as a WAV, measures it in full, and returns what the information sheet reads.
func soundInformation(bytes: const [..] u8)->String
{
    let fileName = Gui.Testing.tempFilePath("scope-sound-levels-", ".wav")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, bytes)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var result = openTestViewer(Sound.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view   = assume cast(*Sound.Panel, result.view)
    waitForSoundOpen(&host, view)
    let sheet = InfoSheet.create(&host.root)
    view.describeInformation(sheet)
    Swag.require(not Utf8.contains(sheet.text(), "Sample peak"))
    finishWaveform(view)
    view.describeInformation(sheet)
    return sheet.text()
}

// Once the waveform worker has read every sample, the sheet states the levels of the whole
// recording: its sample peak, its RMS level and how many samples touch full scale, where an 8-bit
// source tops out lower than a 16-bit one.
#test
{
    let halfBytes = pcm16Wav([16384's16, -16384, 0, 0])
    let half      = soundInformation(halfBytes.toSlice())
    Swag.require(Utf8.contains(half, "Levels"), half)
    Swag.require(Utf8.contains(half, "Format\n") and Utf8.contains(half, "Approx. bitrate\n128 kb/s"), half)
    Swag.require(Utf8.contains(half, "Sample peak\n-6.0 dBFS"), half)
    Swag.require(Utf8.contains(half, "RMS level\n-9.0 dBFS"), half)
    Swag.require(Utf8.contains(half, "Full scale\n0 samples"), half)

    let full = soundInformation(TinyWav)
    Swag.require(Utf8.contains(full, "Sample peak\n0.0 dBFS"), full)
    Swag.require(Utf8.contains(full, "RMS level\n-3.0 dBFS"), full)
    Swag.require(Utf8.contains(full, "Full scale\n2 samples"), full)

    let silentBytes = pcm16Wav([0's16, 0, 0, 0])
    let silent      = soundInformation(silentBytes.toSlice())
    Swag.require(Utf8.contains(silent, "Sample peak\n−∞ dBFS"), silent)
}

// Two points marked while listening loop the passage between them: playback past its end goes
// back to its start, the wave and the summary show it, and stopping the loop plays through again.
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    var samples: Array's16
    samples.resize(8_000 * 3)
    let bytes    = pcm16Wav(samples.toSlice())
    let fileName = Gui.Testing.tempFilePath("scope-sound-loop-", ".wav")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, bytes.toSlice())

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var result = openTestViewer(Sound.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view   = assume cast(*Sound.Panel, result.view)
    waitForSoundOpen(&host, view)
    Swag.require(view.engineReady and view.duration > 2.9)

    // An end before any start loops from the beginning; a start after the end drops the end.
    view.seekSeconds(1)
    view.setLoopEnd()
    Swag.require(view.loopStart == 0 and Math.abs(view.loopEnd - 1) < 0.01)
    view.seekSeconds(2)
    view.setLoopStart()
    Swag.require(Math.abs(view.loopStart - 2) < 0.01 and view.loopEnd < 0)

    view.seekSeconds(0.5)
    view.setLoopStart()
    view.seekSeconds(1.5)
    view.setLoopEnd()
    Swag.require(Math.abs(view.waveform.loopStart - 0.5 / view.duration) < 0.01 and view.waveform.loopEnd > view.waveform.loopStart)
    Swag.require(Utf8.contains(view.details.toString(), Format.toString(Sound.texts().ui_Loop, "0:00", "0:01").toString()), view.details)

    view.seekSeconds(1.6)
    Swag.require(view.followLoop() and Math.abs(view.elapsed - 0.5) < 0.01, Format.toString("%", view.elapsed))
    view.seekSeconds(1.2)
    Swag.require(not view.followLoop())

    view.clearLoop()
    Swag.require(view.loopStart < 0 and
                 view.waveform.loopStart < 0 and
                 not Utf8.contains(view.details.toString(), "0:00–"))
    view.seekSeconds(1.6)
    Swag.require(not view.followLoop())

    // The lens copies the instant playback stands at, as the clock writes it.
    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Sound", host.theme)
    entries.query = "copy"
    view.describeLens(&entries)
    var found = false
    for &entry in results.sections[0]!.entries where entry.title == Format.toString(appStrings().cmd_CopyTime, "0:01")
    {
        entry.run!()
        found = true
    }

    Swag.require(found)
    if Clipboard.isFake() do
        Swag.require(Clipboard.getString() == "0:01", Clipboard.getString())
}
