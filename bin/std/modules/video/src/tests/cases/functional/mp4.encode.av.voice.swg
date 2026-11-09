#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Audio, Pixel

// Software H.264 and non-silent software AAC survive a fragmented MP4 round trip.
#test
{
    let path = videoTempPath("mp4-encoded-video-voice", "mp4")
    defer discard catch File.delete(path)

    var rgb: Array'u8
    rgb.resize(32 * 16 * 3)
    for pixel in 32 * 16
    {
        rgb[pixel * 3]     = 180
        rgb[pixel * 3 + 1] = 70
        rgb[pixel * 3 + 2] = 25
    }
    let image = Image.create(32, 16, .RGB8, rgb.toSlice())
    var nv12: Nv12Frame
    expect nv12.convertFrom(&image)

    var video = expect H264.Encoder.create(32, 16, keyInterval: 4)
    var audio = expect Aac.Encoder.create(48_000, 1)
    var writer = expect Mp4.FragmentedWriter.createWithAudio(path, 32, 16, 90_000,
                                                             video.decoderConfig(),
                                                             Mp4.FragmentedAudioConfig{48_000, 1,
                                                                                       audio.decoderConfig()})
    for index in 8'u64 do
        expect writer.addPacket(expect video.encode(&nv12, index * 3_000, 3_000))

    var input: [12 * 1_024] s16
    for sample in input.count do
        input[sample] = cast(s16, Math.round(10_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                  1_000.0 * sample / 48_000.0)))
    for block in 12'u64
    {
        var packet: Array'u8
        expect audio.encode(Swag.makeSlice(&input[block * 1_024], 1_024), &packet)
        expect writer.addAudioPacket(EncodedPacket{packet.toSlice(), block * 1_024,
                                                   block * 1_024, 1_024, true})
    }
    expect writer.end()

    let summary = expect Mp4.summarizeFragmentedRecording(path)
    Swag.require(summary.video.packetCount == 8 and summary.audioTracks.count == 1)
    Swag.require(summary.audioTracks[0].packetCount == 12 and not summary.hasIncompleteTail)

    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 8 and reader.audioTrackCount() == 1)
    var decodedFrame: PlanarFrame
    expect reader.decodeFramePlanesInto(&decodedFrame, 7)
    Swag.require(Slice.equals(decodedFrame.luma.toSlice(), nv12.luma()))
    let uv = nv12.chroma()
    for index in decodedFrame.chromaB.count
    {
        Swag.require(decodedFrame.chromaB[index] == uv[index * 2])
        Swag.require(decodedFrame.chromaR[index] == uv[index * 2 + 1])
    }

    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleEncoding() == .AacLc and sound.sampleFrameCount() == input.count)
    var pcm: Array's16
    expect sound.decodePcm16(func|pcm = &pcm|(part: const [..] s16)->bool
    {
        pcm.add(part)
        return true
    })
    Swag.require(pcm.count == input.count)
    var error = 0.0'f64
    var power = 0.0'f64
    var cross = 0.0'f64
    var decodedPower = 0.0'f64
    for index in 3_072 until 10_240
    {
        let original = cast(f64, input[index - 1_024])
        let actual   = cast(f64, pcm[index])
        error        += (original - actual) * (original - actual)
        power        += original * original
        decodedPower += actual * actual
        cross        += original * actual
    }
    Swag.require(Math.sqrt(error / power) < 0.15)
    Swag.require(cross / Math.sqrt(power * decodedPower) > 0.9)
}
