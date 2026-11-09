#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

func collectStreamPackets(samples: const [..] s16, chunk: u64)->Array'u8 fail
{
    var encoder = try Aac.StreamEncoder.create(48_000, 1, .Voice)
    var result: Array'u8
    var cursor = 0'u64
    while cursor < samples.count
    {
        let count = Math.min(chunk, samples.count - cursor)
        var packet: Array'u8
        let consumed = try encoder.push(samples[cursor until cursor + count], &packet)
        cursor += consumed
        if packet.count
        {
            result.add(cast(u8, packet.count & 255))
            result.add(cast(u8, packet.count >> 8))
            result.add(packet.toSlice())
        }
    }
    var tail: Array'u8
    while try encoder.finish(&tail)
    {
        result.add(cast(u8, tail.count & 255))
        result.add(cast(u8, tail.count >> 8))
        result.add(tail.toSlice())
    }
    Swag.require(encoder.packetCount() == 4 and encoder.inputFrameCount() == samples.count)
    return result
}

// Arbitrary input chunk boundaries preserve every encoded packet and the final padded tail.
#test
{
    var source: [2_500] s16
    for index in source.count do
        source[index] = cast(s16, cast(s32, index * 31 % 20_000) - 10_000)
    let one = expect collectStreamPackets(Swag.makeSlice(&source[0], source.count), source.count)
    let many = expect collectStreamPackets(Swag.makeSlice(&source[0], source.count), 137)
    Swag.require(Slice.equals(one.toSlice(), many.toSlice()))
}

// Stereo finalization reports the valid input, padded packet and transform drain separately.
#test
{
    var encoder = expect Aac.StreamEncoder.create(44_100, 2)
    Swag.require(encoder.channelCount() == 2 and encoder.sampleRateHz() == 44_100)
    Swag.require(encoder.encoderDelayFrames() == 1_024 and encoder.upperFrequencyHz() == 22_050)
    var source: [1_030 * 2] s16
    for frame in 1_030 do
        source[frame * 2] = cast(s16, frame * 3)
    var packet: Array'u8
    let first = expect encoder.push(Swag.makeSlice(&source[0], source.count), &packet)
    Swag.require(first == 1_024 and packet.count > 0)
    Swag.require(encoder.lastPacketStartSample() == 0 and encoder.lastPacketValidFrames() == 1_024)

    let second = expect encoder.push(Swag.makeSlice(&source[first * 2], source.count - first * 2), &packet)
    Swag.require(second == 6 and packet.isEmpty() and encoder.inputFrameCount() == 1_030)
    Swag.require(expect encoder.finish(&packet))
    Swag.require(packet.count > 0 and encoder.lastPacketStartSample() == 1_024)
    Swag.require(encoder.lastPacketValidFrames() == 6)
    Swag.require(expect encoder.finish(&packet))
    Swag.require(packet.count > 0 and encoder.lastPacketStartSample() == 2_048)
    Swag.require(encoder.lastPacketValidFrames() == 0 and encoder.packetCount() == 3)
    Swag.require(not (expect encoder.finish(&packet)) and packet.isEmpty())
    Swag.require(not (expect encoder.finish(&packet)) and packet.isEmpty())
}

// The drained final packet makes the last partial source block audible after AAC priming.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("aac-stream-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    var source: [2_500] s16
    for index in source.count do
        source[index] = cast(s16, Math.round(10_000.0 * Math.sin(Math.ConstF64.TwoPi *
                                                                  1_000.0 * index / 48_000.0)))
    var encoder = expect Aac.StreamEncoder.create(48_000, 1, .Voice)
    var encoded: Array'u8
    var packets: Array'SoundPacket
    var cursor = 0'u64
    while cursor < source.count
    {
        var packet: Array'u8
        let count = Math.min(113'u64, source.count - cursor)
        cursor += expect encoder.push(Swag.makeSlice(&source[cursor], count), &packet)
        if packet.count
        {
            packets.add({encoded.count, cast(u32, packet.count), 1_024})
            encoded.add(packet.toSlice())
        }
    }
    var tail: Array'u8
    while expect encoder.finish(&tail)
    {
        packets.add({encoded.count, cast(u32, tail.count), 1_024})
        encoded.add(tail.toSlice())
    }
    Swag.require(packets.count == 4)
    discard expect File.writeAllBytes(path.toString(), encoded.toSlice())
    let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 48_000, 1,
                                                  4 * 1_024, packets.toSlice(), encoder.decoderConfig())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == 4 * 1_024)
    var error = 0.0'f64
    var power = 0.0'f64
    for index in 2_048 until source.count
    {
        let expected = cast(f64, source[index])
        let actual = cast(f64, decoded[index + 1_024])
        error += (expected - actual) * (expected - actual)
        power += expected * expected
    }
    Swag.require(Math.sqrt(error / power) < 0.2)
}

// Invalid stereo input and an empty finished stream do not produce packets.
#test
{
    var encoder = expect Aac.StreamEncoder.create(48_000, 2, .Voice)
    const Odd: [3] s16 = [1, 2, 3]
    var packet: Array'u8
    packet.add(99'u8)
    var rejected: Swag.Error
    discard catch encoder.push(Swag.makeSlice(&Odd[0], Odd.count), &packet) as rejected
    Swag.require(rejected.value() is BadParameterError)
    Swag.require(encoder.inputFrameCount() == 0 and packet.count == 1 and packet[0] == 99)
    Swag.require(not (expect encoder.finish(&packet)) and packet.isEmpty())
    discard catch encoder.push([], &packet) as rejected
    Swag.require(rejected.value() is BadParameterError)
}
