#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

// Encoded mono and stereo silence decodes through the normal packet stream.
#test
{
    for channels in [1'u16, 2]
    {
        for sampleRate in [44_100'u32, 48_000, 96_000]
        {
            let path = Path.combine(Env.getSpecialDirectory(.Temp),
                                    Format.toString("aac-silence-%-%.aac", channels, Guid128.random()))
            defer discard catch File.delete(path)

            let encoder = expect Aac.SilenceEncoder.create(sampleRate, channels)
            let config  = encoder.decoderConfig()
            let packet  = encoder.packet()
            Swag.require(config.count == 2 and packet.count == (channels == 1 ? 4 : 7))
            Swag.require(encoder.packetFrames() == 1_024 and encoder.sampleRateHz() == sampleRate)
            Swag.require(encoder.channelCount() == channels)
            if channels == 2 and sampleRate == 44_100 do
                Swag.require(config[0] == 0x12 and config[1] == 0x10)

            var file: Array'u8
            var packets: Array'SoundPacket
            for 3
            {
                packets.add({file.count, cast(u32, packet.count), encoder.packetFrames()})
                file.add(packet)
            }
            discard expect File.writeAllBytes(path.toString(), file.toSlice())
            let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, sampleRate, channels,
                                                          3 * encoder.packetFrames(), packets.toSlice(), config)
            var decoded: Array's16
            expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
            {
                decoded.add(part)
                return true
            })
            Swag.require(decoded.count == 3 * encoder.packetFrames() * channels)
            for sample in decoded do
                Swag.require(sample == 0)
        }
    }
}

// A lost source becomes silence after the decoder drains its preceding AAC overlap.
#test
{
    let encoder = expect Aac.SilenceEncoder.create(44_100, 2)
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("aac-silence-after-sound-%.aac", Guid128.random()))
    defer discard catch File.delete(path)

    let source = expect File.readAllBytes(audioGetTestDataPath("aac-lc-stereo-44100.aac"))
    var file: Array'u8
    var packets: Array'SoundPacket
    var offset = 0'u64
    for 4
    {
        Swag.require(source.count - offset >= 7 and source[offset] == 0xFF)
        let size = (cast(u32, source[offset + 3] & 3) << 11) |
                   (cast(u32, source[offset + 4]) << 3) |
                   (cast(u32, source[offset + 5]) >> 5)
        Swag.require(size >= 7 and size <= source.count - offset)
        packets.add({file.count, size - 7, 1_024})
        file.add(source.toSlice()[offset + 7 until offset + size])
        offset += size
    }
    for 3
    {
        packets.add({file.count, cast(u32, encoder.packet().count), encoder.packetFrames()})
        file.add(encoder.packet())
    }
    discard expect File.writeAllBytes(path.toString(), file.toSlice())
    let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 44_100, 2,
                                                  7 * 1_024, packets.toSlice(), encoder.decoderConfig())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == 7 * 1_024 * 2)
    var hadSound = false
    for index in 4 * 1_024 * 2 where decoded[index] != 0 do
        hadSound = true
    Swag.require(hadSound)
    for index in 6 * 1_024 * 2 until decoded.count do
        Swag.require(decoded[index] == 0)
}

// Unsupported channel layouts and sample-rate escape modes are rejected.
#test
{
    var rejected: Swag.Error
    discard catch Aac.SilenceEncoder.create(48_000, 0) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch Aac.SilenceEncoder.create(48_000, 3) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch Aac.SilenceEncoder.create(47_999, 2) as rejected
    Swag.require(rejected.value() is BadParameterError)
}
