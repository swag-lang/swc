#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Audio, Pixel

// New H.264 pictures and AAC silence share a playable fragmented MP4 timeline.
#test
{
    let path = videoTempPath("mp4-encoded-video-silence", "mp4")
    defer discard catch File.delete(path)

    var rgb: Array'u8
    rgb.resize(32 * 16 * 3)
    for pixel in 32 * 16
    {
        rgb[pixel * 3]     = 200
        rgb[pixel * 3 + 1] = 50
        rgb[pixel * 3 + 2] = 30
    }
    let image = Image.create(32, 16, .RGB8, rgb.toSlice())
    var nv12: Nv12Frame
    expect nv12.convertFrom(&image)

    var video = expect H264.Encoder.create(32, 16, keyInterval: 2)
    let audio = expect Aac.SilenceEncoder.create(48_000, 2)
    var writer = expect Mp4.FragmentedWriter.createWithAudio(path, 32, 16, 90_000,
                                                             video.decoderConfig(),
                                                             Mp4.FragmentedAudioConfig{48_000, 2,
                                                                                       audio.decoderConfig()})
    for index in 3'u64
    {
        expect writer.addPacket(expect video.encode(&nv12, index * 3_000, 3_000))
        expect writer.addAudioPacket(EncodedPacket{audio.packet(), index * 1_024,
                                                   index * 1_024, 1_024, true})
    }
    expect writer.end()

    let summary = expect Mp4.summarizeFragmentedRecording(path)
    Swag.require(summary.video.packetCount == 3 and summary.audioTracks.count == 1)
    Swag.require(summary.audioTracks[0].packetCount == 3 and not summary.hasIncompleteTail)

    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 3 and reader.audioTrackCount() == 1)
    var decoded: PlanarFrame
    expect reader.decodeFramePlanesInto(&decoded, 2)
    Swag.require(Slice.equals(decoded.luma.toSlice(), nv12.luma()))
    let uv = nv12.chroma()
    for index in decoded.chromaB.count
    {
        Swag.require(decoded.chromaB[index] == uv[index * 2])
        Swag.require(decoded.chromaR[index] == uv[index * 2 + 1])
    }

    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleEncoding() == .AacLc and sound.sampleFrameCount() == 3 * 1_024)
    var pcm: Array's16
    expect sound.decodePcm16(func|pcm = &pcm|(part: const [..] s16)->bool
    {
        pcm.add(part)
        return true
    })
    Swag.require(pcm.count == 3 * 1_024 * 2)
    for sample in pcm do
        Swag.require(sample == 0)
}
