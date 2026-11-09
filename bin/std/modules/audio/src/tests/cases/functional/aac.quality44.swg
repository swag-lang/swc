#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A 44.1 kHz stereo music mix and separate impulses remain audible and temporally distinct.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("aac-quality44-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    var encoder = expect Aac.StreamEncoder.create(44_100, 2)
    var source: [12 * 1_024 * 2] s16
    for frame in 6 * 1_024
    {
        let time = frame / 44_100.0
        let left = 5_000.0 * Math.sin(Math.ConstF64.TwoPi * 220.0 * time) +
                   3_500.0 * Math.sin(Math.ConstF64.TwoPi * 660.0 * time) +
                   2_500.0 * Math.sin(Math.ConstF64.TwoPi * 2_200.0 * time) +
                   1_500.0 * Math.sin(Math.ConstF64.TwoPi * 8_000.0 * time) +
                   1_000.0 * Math.sin(Math.ConstF64.TwoPi * 14_000.0 * time)
        let right = 4_000.0 * Math.sin(Math.ConstF64.TwoPi * 330.0 * time) +
                    3_000.0 * Math.sin(Math.ConstF64.TwoPi * 990.0 * time) +
                    2_000.0 * Math.sin(Math.ConstF64.TwoPi * 3_300.0 * time) +
                    1_300.0 * Math.sin(Math.ConstF64.TwoPi * 9_000.0 * time) +
                    800.0 * Math.sin(Math.ConstF64.TwoPi * 15_000.0 * time)
        source[frame * 2] = cast(s16, Math.round(left))
        source[frame * 2 + 1] = cast(s16, Math.round(right))
    }
    const LeftImpulseFrame = 7 * 1_024 + 256
    const RightImpulseFrame = 8 * 1_024 + 768
    source[LeftImpulseFrame * 2] = 20_000
    source[RightImpulseFrame * 2 + 1] = -18_000

    var encoded: Array'u8
    var packets: Array'SoundPacket
    var packet: Array'u8
    for block in 12
    {
        Swag.require(expect encoder.push(Swag.makeSlice(&source[block * 2 * 1_024], 2 * 1_024), &packet) == 1_024)
        Swag.require(packet.count > 0 and packet.count < 8_191)
        packets.add({encoded.count, cast(u32, packet.count), 1_024})
        encoded.add(packet.toSlice())
    }
    Swag.require(expect encoder.finish(&packet) and encoder.lastPacketValidFrames() == 0)
    packets.add({encoded.count, cast(u32, packet.count), 1_024})
    encoded.add(packet.toSlice())
    Swag.require(not expect encoder.finish(&packet))
    discard expect File.writeAllBytes(path.toString(), encoded.toSlice())
    let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 44_100, 2,
                                                  packets.count * 1_024, packets.toSlice(), encoder.decoderConfig())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == packets.count * 1_024 * 2)

    for channel in 2
    {
        var sourcePower = 0.0'f64
        var decodedPower = 0.0'f64
        var cross = 0.0'f64
        var error = 0.0'f64
        for frame in 3 * 1_024 until 5 * 1_024
        {
            let original = cast(f64, source[(frame - 1_024) * 2 + channel])
            let actual = cast(f64, decoded[frame * 2 + channel])
            sourcePower += original * original
            decodedPower += actual * actual
            cross += original * actual
            error += (original - actual) * (original - actual)
        }
        Swag.require(cross / Math.sqrt(sourcePower * decodedPower) > 0.95)
        Swag.require(Math.sqrt(error / sourcePower) < 0.2)
    }

    for channel in 2
    {
        let expected = (channel == 0 ? LeftImpulseFrame : RightImpulseFrame) + 1_024
        var peak = 0's32
        var peakAt = 0'u64
        for frame in expected - 256 until expected + 256
        {
            let magnitude = Math.abs(cast(s32, decoded[frame * 2 + channel]))
            if magnitude > peak
            {
                peak = magnitude
                peakAt = frame
            }
        }
        Swag.require(peak > 5_000 and Math.abs(cast(s64, peakAt) - expected) < 64)
    }
}
