#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Audio, Pixel

// A one-packet AAC preroll makes decoded audio and video start on the same media timeline.
#test
{
    let path = videoTempPath("mp4-encoded-av-preroll", "mp4")
    defer discard catch File.delete(path)
    var rgb: Array'u8
    rgb.resize(32 * 16 * 3)
    Memory.set(rgb.storage(), 100, rgb.count)
    let image = Image.create(32, 16, .RGB8, rgb.toSlice())
    var nv12: Nv12Frame
    expect nv12.convertFrom(&image)

    var video = expect H264.Encoder.create(32, 16, keyInterval: 4)
    var audio = expect Aac.StreamEncoder.create(48_000, 1)
    Swag.require(audio.encoderDelayFrames() == 1_024)
    var writer = expect Mp4.FragmentedWriter.createWithAudio(path, 32, 16, 90_000,
                                                             video.decoderConfig(),
                                                             Mp4.FragmentedAudioConfig{48_000, 1,
                                                                                       audio.decoderConfig()})
    // 1,024 audio samples equal 1,920 ticks at the 90 kHz video timescale.
    for frame in 13'u64 do
        expect writer.addPacket(expect video.encode(&nv12, 1_920 + frame * 1_500, 1_500))

    var source: [10 * 1_024] s16
    for sample in source.count do
        source[sample] = cast(s16, Math.round(10_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                   1_000.0 * sample / 48_000.0)))
    var cursor = 0'u64
    while cursor < source.count
    {
        let count = Math.min(317'u64, source.count - cursor)
        var packet: Array'u8
        cursor += expect audio.push(Swag.makeSlice(&source[cursor], count), &packet)
        if packet.count do
            expect writer.addAudioPacket(EncodedPacket{packet.toSlice(), audio.lastPacketStartSample(),
                                                       audio.lastPacketStartSample(), 1_024, true})
    }
    var drain: Array'u8
    while expect audio.finish(&drain) do
        expect writer.addAudioPacket(EncodedPacket{drain.toSlice(), audio.lastPacketStartSample(),
                                                   audio.lastPacketStartSample(), 1_024, true})
    Swag.require(audio.inputFrameCount() == source.count and audio.packetCount() == 11)
    expect writer.end()

    var reader = expect Reader.open(path)
    Swag.require(reader.frameCount() == 13 and reader.audioTrackCount() == 1)
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
    for index in 2_048 until 8_192
    {
        let expected = cast(f64, source[index])
        let actual = cast(f64, decoded[index])
        error += (expected - actual) * (expected - actual)
        power += expected * expected
    }
    Swag.require(Math.sqrt(error / power) < 0.15)
}
