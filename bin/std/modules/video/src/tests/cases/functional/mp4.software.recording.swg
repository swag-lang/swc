#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors, Audio, Pixel

// The recorder accepts arbitrary PCM chunks and exact video slots, then removes AAC priming.
#test
{
    let path = videoTempPath("mp4-software-recorder", "mp4")
    defer discard catch File.delete(path)
    let image = Image.create(32, 16, .BGRA8)
    Memory.set(image.pixels.storage(), 127, image.pixels.count)
    var recorder = expect Mp4.SoftwareRecording.create(path, 32, 16, 90_000, 48_000, 1)
    Swag.require(recorder.videoPrerollTicks() == 1_920)
    let pacer = expect FramePacer.create(expect FrameRate.create(60, 1), 1_000_000, 90_000)
    for frame in 13'u64
    {
        expect recorder.addFrame(&image, expect pacer.slotAt(frame))
        if frame == 4 do
            expect recorder.flush()
    }

    var source: [10 * 1_024] s16
    for sample in source.count do
        source[sample] = cast(s16, Math.round(10_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                   1_000.0 * sample / 48_000.0)))
    var cursor = 0'u64
    while cursor < source.count
    {
        let count = Math.min(137'u64, source.count - cursor)
        expect recorder.addAudioFrames(Swag.makeSlice(&source[cursor], count))
        cursor += count
    }
    Swag.require(recorder.videoFrameCount() == 13)
    Swag.require(recorder.audioInputFrameCount() == source.count and recorder.audioPacketCount() == 10)
    expect recorder.end()
    expect recorder.end()
    Swag.require(recorder.audioPacketCount() == 11 and recorder.writtenByteCount() > 0)

    let summary = expect Mp4.summarizeFragmentedRecording(path)
    Swag.require(summary.video.packetCount == 13 and summary.audioTracks.count == 1)
    Swag.require(summary.audioTracks[0].packetCount == 11 and not summary.hasIncompleteTail)
    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 13 and reader.audioTrackCount() == 1)
    var decodedFrame: PlanarFrame
    expect reader.decodeFramePlanesInto(&decodedFrame, 12)
    var expected: Nv12Frame
    expect expected.convertFrom(&image)
    Swag.require(Slice.equals(decodedFrame.luma.toSlice(), expected.luma()))
    let uv = expected.chroma()
    for index in decodedFrame.chromaB.count
    {
        Swag.require(decodedFrame.chromaB[index] == uv[index * 2])
        Swag.require(decodedFrame.chromaR[index] == uv[index * 2 + 1])
    }
    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleFrameCount() == source.count)
    Swag.require(Math.abs(sound.timelineStartSeconds()) < 0.000001)
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == source.count)
    var error = 0.0'f64
    var power = 0.0'f64
    for sample in 2_048 until 8_192
    {
        let expectedSample = cast(f64, source[sample])
        let actual = cast(f64, decoded[sample])
        error += (expectedSample - actual) * (expectedSample - actual)
        power += expectedSample * expectedSample
    }
    Swag.require(Math.sqrt(error / power) < 0.15)
}

// Bad frame order and partial stereo samples are rejected before the next valid packet.
#test
{
    let path = videoTempPath("mp4-software-recorder-invalid", "mp4")
    defer discard catch File.delete(path)
    let image = Image.create(16, 16, .RGB8)
    var recorder = expect Mp4.SoftwareRecording.create(path, 16, 16, 90_000, 48_000, 2)
    let pacer = expect FramePacer.create(expect FrameRate.create(30, 1), 1_000, 90_000)
    var rejected: Swag.Error
    discard catch recorder.end() as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch recorder.addFrame(&image, expect pacer.slotAt(1)) as rejected
    Swag.require(rejected.value() is BadParameterError and recorder.videoFrameCount() == 0)
    const Odd: [1] s16 = [10]
    discard catch recorder.addAudioFrames(Swag.makeSlice(&Odd[0], Odd.count)) as rejected
    Swag.require(rejected.value() is BadParameterError and recorder.audioInputFrameCount() == 0)
    expect recorder.addFrame(&image, expect pacer.slotAt(0))
    const Pair: [2] s16 = [10, 20]
    expect recorder.addAudioFrames(Swag.makeSlice(&Pair[0], Pair.count))
    expect recorder.end()
    Swag.require(recorder.audioInputFrameCount() == 1 and recorder.audioPacketCount() == 2)
    discard catch recorder.addFrame(&image, expect pacer.slotAt(1)) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch recorder.addAudioFrames(Swag.makeSlice(&Pair[0], Pair.count)) as rejected
    Swag.require(rejected.value() is BadParameterError)
}

// Lost screen slots repeat the last picture and remain visible as reported recorder frames.
#test
{
    let path = videoTempPath("mp4-software-recorder-repeat", "mp4")
    defer discard catch File.delete(path)
    let image = Image.create(16, 16, .BGRA8)
    Memory.set(image.pixels.storage(), 90, image.pixels.count)
    var recorder = expect Mp4.SoftwareRecording.create(path, 16, 16, 90_000, 48_000, 1)
    let pacer = expect FramePacer.create(expect FrameRate.create(60, 1), 1_000, 90_000)
    var rejected: Swag.Error
    discard catch recorder.repeatLastFrame(expect pacer.slotAt(0)) as rejected
    Swag.require(rejected.value() is BadParameterError)
    expect recorder.addFrame(&image, expect pacer.slotAt(0))
    discard catch recorder.repeatLastFrame(expect pacer.slotAt(2)) as rejected
    Swag.require(rejected.value() is BadParameterError and recorder.videoFrameCount() == 1)
    for index in 1'u64 until 4 do
        expect recorder.repeatLastFrame(expect pacer.slotAt(index))
    expect recorder.addFrame(&image, expect pacer.slotAt(4))
    Swag.require(recorder.videoFrameCount() == 5 and recorder.repeatedFrameCount() == 3)
    var silence: [1_024] s16
    expect recorder.addAudioFrames(Swag.makeSlice(&silence[0], silence.count))
    expect recorder.end()

    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 5)
    var expected: Nv12Frame
    expect expected.convertFrom(&image)
    var decoded: PlanarFrame
    for index in 5'u64
    {
        expect reader.decodeFramePlanesInto(&decoded, index)
        Swag.require(Slice.equals(decoded.luma.toSlice(), expected.luma()))
    }
}
