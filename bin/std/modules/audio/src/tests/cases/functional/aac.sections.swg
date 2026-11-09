#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Long-window section lengths use 31 as an escape and preserve the final remainder.
#test
{
    for length in [1'u64, 30, 31, 32, 49]
    {
        var active: [49] bool
        for index in length do
            active[index] = true
        var codes: [98] Aac.EncoderSectionCode
        let count = Aac.planEncoderSections(Swag.makeSlice(&active[0], length),
                                            Swag.makeSlice(&codes[0], codes.count))
        Swag.require(codes[0].value == 11 and codes[0].width == 4)
        if length < 31
        {
            Swag.require(count == 2 and codes[1].value == length and codes[1].width == 5)
        }
        else
        {
            Swag.require(count == 3 and codes[1].value == 31 and codes[1].width == 5)
            Swag.require(codes[2].value == length - 31 and codes[2].width == 5)
        }
    }

    let active: [5] bool = [true, true, false, false, true]
    var codes: [10] Aac.EncoderSectionCode
    let count = Aac.planEncoderSections(Swag.makeSlice(&active[0], active.count),
                                        Swag.makeSlice(&codes[0], codes.count))
    let expected: [6] u32 = [11, 2, 0, 2, 11, 1]
    Swag.require(count == expected.count)
    for index in count
    {
        Swag.require(codes[index].value == expected[index])
        Swag.require(codes[index].width == (index % 2 == 0 ? 4 : 5))
    }
}

// Repeated tonal capture packs same-book bands while retaining both decoded channels.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp),
                            Format.toString("aac-sections-%.aac", Guid128.random()))
    defer discard catch File.delete(path)
    var encoder = expect Aac.Encoder.create(48_000, 2)
    var file: Array'u8
    var packets: Array'SoundPacket
    for block in 10'u64
    {
        var samples: [2 * 1_024] s16
        for index in 1_024'u64
        {
            let frame = block * 1_024 + index
            let time = frame / 48_000.0
            samples[index * 2] = cast(s16, Math.round(18_000.0 *
                Math.sin(Math.ConstF64.TwoPi * 440.0 * time) + 120.0 *
                Math.sin(Math.ConstF64.TwoPi * 12_000.0 * time)))
            samples[index * 2 + 1] = cast(s16, Math.round(8_000.0 *
                Math.sin(Math.ConstF64.TwoPi * 1_000.0 * time)))
        }
        var packet: Array'u8
        expect encoder.encode(Swag.makeSlice(&samples[0], samples.count), &packet)
        packets.add({file.count, cast(u32, packet.count), 1_024})
        file.add(packet.toSlice())
    }
    Swag.require(file.count > 100 and file.count < 1_500)
    discard expect File.writeAllBytes(path.toString(), file.toSlice())
    let sound = expect SoundFile.openPacketStream(path.toString(), .AacLc, 48_000, 2,
                                                  10 * 1_024, packets.toSlice(), encoder.decoderConfig())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == 10 * 1_024 * 2)
    var leftPower = 0.0'f64
    var rightPower = 0.0'f64
    for frame in 3 * 1_024 until 8 * 1_024
    {
        leftPower += cast(f64, decoded[frame * 2]) * decoded[frame * 2]
        rightPower += cast(f64, decoded[frame * 2 + 1]) * decoded[frame * 2 + 1]
    }
    Swag.require(leftPower > 1_000_000_000.0 and rightPower > 100_000_000.0)
}
