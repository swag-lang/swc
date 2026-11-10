#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel, Audio

// A one-picture overlay re-encodes its dependent tail, then resumes byte-identical IDR copying.
#test
{
    let source = softwareTrimSource(48_000)
    let target = videoTempPath("software-trim-overlay", "mp4")
    defer discard catch File.delete(source)
    defer discard catch File.delete(target)
    const Ranges: [1] Mp4.SoftwareRenderRange = [{6, 7}]
    let renderer: Mp4.SoftwareFrameRenderer = func(_: u64, picture: *Image) fail
    {
        picture.fill(Argb.Red)
    }

    let result = expect Mp4.trimSoftwareRecording(source, target, 2, 15, edits: Mp4.SoftwareTrimEdits{Ranges, renderer})
    Swag.require(result.encodedVideoFrames == 4 and result.copiedVideoFrames == 9)
    var reader = expect Reader.open(target)
    let edited = expect reader.decodeFrame(4)
    Swag.require(edited.pixelColor(20, 20).r > 200 and edited.pixelColor(20, 20).g < 50)
    let restored = expect reader.decodeFrame(5)
    Swag.require(Math.abs(cast(s32, restored.pixelColor(20, 20).r) - restored.pixelColor(20, 20).g) <= 2)
    var before = expect Mp4.FragmentedPacketReader.open(source)
    var after  = expect Mp4.FragmentedPacketReader.open(target)
    var a, b: Array'u8
    Swag.require(Slice.equals((expect before.readPacket(8, &a)).bytes, (expect after.readPacket(6, &b)).bytes))
}

// A renderer failure must preserve the previous destination just like a failed packet copy.
#test
{
    let source = softwareTrimSource(48_000)
    let target = videoTempPath("software-trim-render-failure", "mp4")
    defer discard catch File.delete(source)
    defer discard catch File.delete(target)
    discard expect File.writeAllText(target, "previous destination")
    const Ranges: [1] Mp4.SoftwareRenderRange = [{6, 7}]
    let renderer: Mp4.SoftwareFrameRenderer = func(_: u64, _: *Image) fail
    {
        fail Errors.InvalidFormatError{"render failed"}
    }

    var failure: Swag.Error
    discard catch Mp4.trimSoftwareRecording(source, target, 2, 15, edits: Mp4.SoftwareTrimEdits{Ranges, renderer}) as failure
    Swag.require(failure.value() is Errors.InvalidFormatError)
    Swag.require(expect File.readAllText(target) == "previous destination")
}

func softwareTrimSource(rate: u32)->String
{
    let path   = videoTempPath("software-trim-source", "mp4")
    let configs: [2] Mp4.SoftwareAudioConfig = [{rate, 1, .Full}, {rate, 2, .Voice}]
    var writer = expect Mp4.SoftwareRecording.createWithAudioTracks(path, 64, 48, 1_000_000, configs, keyInterval: 4, options: Mp4.FragmentedOptions{4, 4 * 1024 * 1024, 8, true})
    for index in 16'u64
    {
        let image = videoGrayImage(64, 48, cast(u8, 32 + index * 10))
        expect writer.addFrame(&image, {index, index * 100_000, 100_000, 0})
    }

    var mono, stereo: Array's16
    mono.resize(rate * 16 / 10)
    stereo.resize(mono.count * 2)
    for index in mono.count
    {
        mono[index] = cast(s16, Math.round(6_000.0 * Math.sin(Math.ConstF64.TwoPi * 750 * index / rate)))
        stereo[index * 2], stereo[index * 2 + 1] = mono[index]
    }

    expect writer.addAudioFrames(mono.toSlice(), 0)
    expect writer.addAudioFrames(stereo.toSlice(), 1)
    expect writer.end()
    return path
}

// A single-picture cut may replace its source only after all source handles have closed.
#test
{
    let source = softwareTrimSource(48_000)
    defer discard catch File.delete(source)
    let work = expect Mp4.trimSoftwareRecording(source, source, 3, 4)
    Swag.require(work.encodedVideoFrames == 1 and work.copiedVideoFrames == 0)
    var cut = expect Reader.open(source)
    Swag.require(cut.frameCount() == 1 and cut.audioTrackCount() == 2)
    discard expect cut.decodeFrame(0)
    for track in 2'u32 do
        Swag.require(cut.audioTrack(track)!.sampleFrameCount() == 4_800)
}

// A silent recording keeps a video-only topology through an arbitrary cut.
#test
{
    let source = videoTempPath("software-trim-silent", "mp4")
    let target = videoTempPath("software-trim-silent-cut", "mp4")
    defer discard catch File.delete(source)
    defer discard catch File.delete(target)
    var writer  = expect Mp4.SoftwareRecording.createVideoOnly(source, 64, 48, 1_000_000, keyInterval: 4)
    let picture = videoGrayImage(64, 48, 96)
    for index in 8'u64 do
        expect writer.addFrame(&picture, FrameSlot{index, index * 100_000, 100_000, 0})
    expect writer.end()
    let work = expect Mp4.trimSoftwareRecording(source, target, 2, 7)
    Swag.require(work.encodedVideoFrames == 2 and work.copiedVideoFrames == 3 and work.copiedAudioPackets == 0)
    var cut = expect Reader.open(target)
    Swag.require(cut.frameCount() == 5 and cut.audioTrackCount() == 0)
    for index in cut.frameCount() do
        discard expect cut.decodeFrame(index)
}

// Arbitrary picture boundaries re-encode the dependent head only and retain exact sound samples.
#test
{
    for rate in [44_100'u32, 48_000'u32]
    {
        let source = softwareTrimSource(rate)
        let target = videoTempPath("software-trim-cut", "mp4")
        defer discard catch File.delete(source)
        defer discard catch File.delete(target)
        let work = expect Mp4.trimSoftwareRecording(source, target, 2, 11)
        Swag.require(work.encodedVideoFrames == 2 and work.copiedVideoFrames == 7)
        Swag.require(work.copiedAudioPackets > 0)
        var original = expect Reader.open(source)
        var cut      = expect Reader.open(target)
        Swag.require(cut.frameCount() == 9 and cut.audioTrackCount() == 2)
        Swag.require(Math.abs(cut.durationInSeconds() - 0.9) < 0.000001)
        for index in cut.frameCount()
        {
            let picture  = expect cut.decodeFrame(index)
            let expected = expect original.decodeFrame(index + 2)
            Swag.require(Math.abs(cast(s32, picture.pixelColor(20, 20).r) - expected.pixelColor(20, 20).r) <= 2)
        }

        var originalPackets = expect Mp4.FragmentedPacketReader.open(source)
        var cutPackets      = expect Mp4.FragmentedPacketReader.open(target)
        var left, right: Array'u8
        for index in 7'u64
        {
            let before = expect originalPackets.readPacket(index + 4, &left)
            let after  = expect cutPackets.readPacket(index + 2, &right)
            Swag.require(Slice.equals(before.bytes, after.bytes), "interior H.264 packets must be byte-identical")
        }

        for track in 2'u32
        {
            let input  = unwrap original.audioTrack(track)
            let output = unwrap cut.audioTrack(track)
            Swag.require(output.sampleFrameCount() == cast(u64, rate) * 9 / 10)
            var sourcePcm, cutPcm: Array's16
            expect input.decodePcm16(func|&sourcePcm|(part: const [..] s16)->bool
            {
                sourcePcm.add(part)
                return true
            })
            expect output.decodePcm16(func|&cutPcm|(part: const [..] s16)->bool
            {
                cutPcm.add(part)
                return true
            })
            let offset = cast(u64, rate) / 5 * output.numChannels()
            Swag.require(Slice.equals(cutPcm.toSlice(), sourcePcm.toSlice()[offset until offset + cutPcm.count]),
                         "AAC preroll must preserve every audible sample at both cut boundaries")
        }

        let nested = videoTempPath("software-trim-again", "mp4")
        defer discard catch File.delete(nested)
        discard expect Mp4.trimSoftwareRecording(target, nested, 1, 6)
        var secondCut = expect Reader.open(nested)
        Swag.require(secondCut.frameCount() == 5)
        let secondSound   = unwrap secondCut.audioTrack(0)
        let originalSound = unwrap original.audioTrack(0)
        var originalPcm, nestedPcm: Array's16
        expect originalSound.decodePcm16(func|&originalPcm|(part: const [..] s16)->bool
        {
            originalPcm.add(part)
            return true
        })
        expect secondSound.decodePcm16(func|&nestedPcm|(part: const [..] s16)->bool
        {
            nestedPcm.add(part)
            return true
        })
        let offset = cast(u64, rate) * 3 / 10
        Swag.require(secondSound.sampleFrameCount() == rate / 2)
        Swag.require(Slice.equals(nestedPcm.toSlice(), originalPcm.toSlice()[offset until offset + nestedPcm.count]),
                     "a repeated trim must retain the source's existing AAC presentation edit")
    }
}

// An aligned start and a P-picture end copy every retained picture without encoding.
#test
{
    let source = softwareTrimSource(48_000)
    let target = videoTempPath("software-trim-aligned", "mp4")
    defer discard catch File.delete(source)
    defer discard catch File.delete(target)
    let work = expect Mp4.trimSoftwareRecording(source, target, 4, 10)
    Swag.require(work.encodedVideoFrames == 0 and work.copiedVideoFrames == 6)
    var cut = expect Reader.open(target)
    Swag.require(cut.frameCount() == 6)
    for index in cut.frameCount() do
        discard expect cut.decodeFrame(index)
}

// Invalid ranges leave an existing destination untouched, including a cut outside the source.
#test
{
    let source = softwareTrimSource(48_000)
    let target = videoTempPath("software-trim-sentinel", "mp4")
    defer discard catch File.delete(source)
    defer discard catch File.delete(target)
    discard expect File.writeAllText(target, "previous destination")
    var failure: Swag.Error
    discard catch Mp4.trimSoftwareRecording(source, target, 8, 8) as failure
    Swag.require(failure.value() is Errors.BadParameterError)
    discard catch Mp4.trimSoftwareRecording(source, target, 8, 20) as failure
    Swag.require(failure.value() is Errors.BadParameterError)
    Swag.require(expect File.readAllText(target) == "previous destination")
}
