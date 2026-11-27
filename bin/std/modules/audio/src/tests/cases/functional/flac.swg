#global if #command == Swag.CompilerCommand.Test

using Core, Core.Errors

// Decodes every packet of a loaded sound through the codec alone and returns the interleaved
// samples.
//
// The packet table comes from the file reader, so this proves the two halves agree: a frame the
// index closed at the wrong byte does not decode.
private func flacDecodeAll(sound: const *SoundFile)->Array!{u8} fail
{
    let file  = try File.readAllBytes(sound.sourcePath())
    let bytes = file.toSlice()

    var codec: Flac.Codec
    let itf:   IPacketCodec = &codec
    try itf.initialize(sound.decoderConfig.toSlice(), sound.sampleRateHz(), sound.numChannels())

    // The largest block a FLAC frame may carry, clause 8.
    const MaxBlockSize = 65_535_u64

    var result: #returntype
    var block:  Array!{u8}
    block.resize(MaxBlockSize * cast(u64, sound.numChannels()) * #sizeof(s16))
    for index in sound.packetCount()
    {
        let packet   = try sound.packet(index)
        let produced = try itf.decodePacket(block.storage(),
                                            block.count,
                                            bytes[packet.sourceOffset until packet.sourceOffset + packet.byteSize])
        result.add(block.toSlice()[0 until produced])
    }

    return result
}

private func flacTestHeaderCrc8(bytes: const [..] u8)->u8
{
    var crc = 0_u8
    for value in bytes
    {
        crc ^= value
        for 8
        {
            crc = (crc & 0x80) != 0 ? cast(u8, ((crc << 1) ^ 0x07)) : cast(u8, (crc << 1))
        }
    }

    return crc
}

// Long FLAC packets use the same CRC16 as short packets and preserve the running remainder.
#test
{
    var bytes: [256] u8
    for index in bytes.count
    {
        bytes[index] = cast(u8, (index * 37 + index / 16) & 0xFF)
    }

    const Initial = 0x926B_u16
    for count in [15_u64, 16, 63, 64, 65, 127, 128, 137, 256]
    {
        let slice    = bytes[until count]
        var expected = cast(u32, Initial)
        for byte in slice
        {
            expected ^= cast(u32, byte) << 8
            for 8
            {
                expected = ((expected << 1) ^ (expected & 0x8000 ? 0x8005 : 0)) & 0xFFFF
            }
        }

        let half  = count / 2
        let first = Flac.frameCrc16(slice[until half], Initial)
        Swag.require(Flac.frameCrc16(slice[half until], first) == expected)
        Swag.require(Flac.frameCrc16(slice, Initial) == expected)
    }
}

private func flacTestAppendBits(bytes: *Array!{u8}, bitCount: *u64, value: u64, count: u32)
{
    for bit in count
    {
        if not (bitCount[] & 7)
        {
            bytes.add(0)
        }

        let shift = count - 1 - bit
        if (value >> shift) & 1
        {
            bytes[bitCount[] >> 3] |= cast(u8, 1_u32 << (7 - cast(u32, bitCount[] & 7)))
        }

        bitCount[] += 1
    }
}

private func flacTestSetTotalSamples(bytes: *Array!{u8}, total: u64)
{
    var description = 0_u64
    for index in 18 until 26
    {
        description = (description << 8) | bytes[][index]
    }

    let patched = (description & ~((1_u64 << 36) - 1)) | total
    for index in 8
    {
        bytes[][18 + index] = cast(u8, (patched >> (56 - index * 8)) & 0xFF)
    }
}

private func flacWideStereoTestConfig()->Array!{u8}
{
    var config: Array!{u8}
    config.add(0)
    config.add(1)     // Min block size: one sample.
    config.add(0)
    config.add(1)     // Max block size: one sample.
    for 6
    {
        config.add(0)     // Min/max frame sizes are unknown.
    }

    let description = (48_000_u64 << 44) | (1_u64 << 41) | (31_u64 << 36) | 1
    for byte in 8
    {
        config.add(cast(u8, (description >> (56 - byte * 8)) & 0xFF))
    }

    for 16
    {
        config.add(0)     // MD5 is not consulted by the frame decoder.
    }

    return config
}

private func flac24BitStereoTestConfig()->Array!{u8}
{
    var config: Array!{u8}
    config.add(0)
    config.add(1)     // Min block size: one sample.
    config.add(0)
    config.add(6)     // Max block size: six samples.
    for 6
    {
        config.add(0)     // Min/max frame sizes are unknown.
    }

    let description = (48_000_u64 << 44) | (1_u64 << 41) | (23_u64 << 36) | 6
    for byte in 8
    {
        config.add(cast(u8, (description >> (56 - byte * 8)) & 0xFF))
    }

    for 16
    {
        config.add(0)     // MD5 is not consulted by the frame decoder.
    }

    return config
}

private func flacMonoTestConfig(samples = 2_u8, depth = 16_u64)->Array!{u8}
{
    var config: Array!{u8}
    config.add(0)
    config.add(samples)
    config.add(0)
    config.add(samples)
    for 6
    {
        config.add(0)     // Min/max frame sizes are unknown.
    }

    let description = (48_000_u64 << 44) | ((depth - 1) << 36) | samples
    for byte in 8
    {
        config.add(cast(u8, (description >> (56 - byte * 8)) & 0xFF))
    }

    for 16
    {
        config.add(0)     // MD5 is not consulted by the frame decoder.
    }

    return config
}

private func flacLinearOverflowTestConfig(samples = 33_u8)->Array!{u8}
{
    var config: Array!{u8}
    config.add(0)
    config.add(samples)
    config.add(0)
    config.add(samples)
    for 6
    {
        config.add(0)     // Min/max frame sizes are unknown.
    }

    let description = (48_000_u64 << 44) | (31_u64 << 36) | samples
    for byte in 8
    {
        config.add(cast(u8, (description >> (56 - byte * 8)) & 0xFF))
    }

    for 16
    {
        config.add(0)     // MD5 is not consulted by the frame decoder.
    }

    return config
}

private func flacLinearShiftFrame(shift: u32)->Array!{u8}
{
    var frame: Array!{u8}
    frame.add(0xFF)
    frame.add(0xF9)     // Variable-block strategy.
    frame.add(0x60)     // Two-sample block size follows; sample rate from STREAMINFO.
    frame.add(0x00)     // One channel, 16-bit samples from STREAMINFO.
    frame.add(0)        // Sample number.
    frame.add(1)        // Block size minus one.
    frame.add(flacTestHeaderCrc8(frame.toSlice()))

    var bitCount = frame.count * 8
    flacTestAppendBits(&frame, &bitCount, 0x40, 8)     // Order-one linear predictor.
    flacTestAppendBits(&frame, &bitCount, 1, 16)       // Warmup sample: 1.
    let fields = (1_u64 << 18) | (cast(u64, shift) << 13) | (1_u64 << 11) | 1
    flacTestAppendBits(&frame, &bitCount, fields, 22)     // Precision 2, coefficient 1, zero residual.
    while bitCount & 7
    {
        flacTestAppendBits(&frame, &bitCount, 0, 1)
    }

    let checksum = Flac.frameCrc16(frame.toSlice())
    frame.add(cast(u8, checksum >> 8))
    frame.add(cast(u8, checksum & 0xFF))
    return frame
}

private func flacOverflowingLinearShiftFrame()->Array!{u8}
{
    var frame: Array!{u8}
    frame.add(0xFF)
    frame.add(0xF9)     // Variable-block strategy.
    frame.add(0x70)     // Thirty-three-sample block size follows; sample rate from STREAMINFO.
    frame.add(0x00)     // One channel, 32-bit samples from STREAMINFO.
    frame.add(0)        // Sample number.
    frame.add(0)
    frame.add(32)     // Block size minus one.
    frame.add(flacTestHeaderCrc8(frame.toSlice()))

    var bitCount = frame.count * 8
    flacTestAppendBits(&frame, &bitCount, 0x7E, 8)     // Order-32 linear predictor.
    for 32
    {
        flacTestAppendBits(&frame, &bitCount, 0x7FFF_FFFF, 32)
    }

    flacTestAppendBits(&frame, &bitCount, 14, 4)           // Fifteen-bit coefficients.
    flacTestAppendBits(&frame, &bitCount, 0b1_0000, 5)     // Signed QLP shift: -16.
    for 32
    {
        flacTestAppendBits(&frame, &bitCount, 0x3FFF, 15)
    }

    flacTestAppendBits(&frame, &bitCount, 0, 2)     // Rice residual coding.
    flacTestAppendBits(&frame, &bitCount, 0, 4)     // One partition, Rice parameter 0.
    flacTestAppendBits(&frame, &bitCount, 1, 1)     // Zero residual.
    while bitCount & 7
    {
        flacTestAppendBits(&frame, &bitCount, 0, 1)
    }

    let checksum = Flac.frameCrc16(frame.toSlice())
    frame.add(cast(u8, checksum >> 8))
    frame.add(cast(u8, checksum & 0xFF))
    return frame
}

private func flacOverflowingLinearAdditionFrame()->Array!{u8}
{
    var frame: Array!{u8}

    // Variable-block strategy, six samples, with the sample format from STREAMINFO.
    frame.add([0xFF_u8, 0xF9, 0x60, 0, 0, 5])
    frame.add(flacTestHeaderCrc8(frame.toSlice()))

    var bitCount = frame.count * 8
    flacTestAppendBits(&frame, &bitCount, 0x48, 8)     // Order-five linear predictor.
    flacTestAppendBits(&frame, &bitCount, 1, 32)
    for 4
    {
        flacTestAppendBits(&frame, &bitCount, 0x8000_0000, 32)
    }

    flacTestAppendBits(&frame, &bitCount, 14, 4)           // Fifteen-bit coefficients.
    flacTestAppendBits(&frame, &bitCount, 0b1_0000, 5)     // Signed QLP shift: -16.
    for 4
    {
        flacTestAppendBits(&frame, &bitCount, 0x4000, 15)     // Coefficient -16,384.
    }

    flacTestAppendBits(&frame, &bitCount, 0x7FFF, 15)     // Coefficient -1.

    // The prediction is 2^63 - 65,536. The residual of 65,536 then overflows the signed sum.
    flacTestAppendBits(&frame, &bitCount, 1, 2)     // Rice coding with a five-bit parameter.
    flacTestAppendBits(&frame, &bitCount, 0, 4)     // One partition.
    flacTestAppendBits(&frame, &bitCount, 17, 5)
    flacTestAppendBits(&frame, &bitCount, 1 << 17, 19)
    while bitCount & 7
    {
        flacTestAppendBits(&frame, &bitCount, 0, 1)
    }

    let checksum = Flac.frameCrc16(frame.toSlice())
    frame.add(cast(u8, checksum >> 8))
    frame.add(cast(u8, checksum & 0xFF))
    return frame
}

private func flac24BitStereoTestFrame()->Array!{u8}
{
    let left:  [6] s32 = [0x007FFFFF, 0x007FFF00, 0x00000100, 0, -0x00000100, -0x00800000]
    let right: [6] s32 = [-0x00800000, -0x007FFF00, -0x00000100, -1, 0x00000100, 0x007FFFFF]

    var frame: Array!{u8}
    frame.add(0xFF)
    frame.add(0xF9)     // Variable-block strategy.
    frame.add(0x60)     // Six-sample block size follows; sample rate from STREAMINFO.
    frame.add(0x10)     // Independent stereo, 24-bit samples from STREAMINFO.
    frame.add(0)        // Sample number.
    frame.add(5)        // Block size minus one.
    frame.add(flacTestHeaderCrc8(frame.toSlice()))

    var bitCount = frame.count * 8
    flacTestAppendBits(&frame, &bitCount, 0x02, 8)     // Verbatim left subframe.
    for value in left
    {
        flacTestAppendBits(&frame, &bitCount, cast(u64, cast #wrap (u32, value) & 0x00FF_FFFF), 24)
    }

    flacTestAppendBits(&frame, &bitCount, 0x02, 8)     // Verbatim right subframe.
    for value in right
    {
        flacTestAppendBits(&frame, &bitCount, cast(u64, cast #wrap (u32, value) & 0x00FF_FFFF), 24)
    }

    while bitCount & 7
    {
        flacTestAppendBits(&frame, &bitCount, 0, 1)
    }

    let checksum = Flac.frameCrc16(frame.toSlice())
    frame.add(cast(u8, checksum >> 8))
    frame.add(cast(u8, checksum & 0xFF))
    return frame
}

private func flacWideMidSideFrame()->Array!{u8}
{
    var frame: Array!{u8}
    frame.add(0xFF)
    frame.add(0xF9)     // Variable-block strategy.
    frame.add(0x60)     // One-sample block size, sample rate from STREAMINFO.
    frame.add(0xA0)     // Two-channel mid/side decorrelation, 32-bit samples from STREAMINFO.
    frame.add(0)        // Sample number.
    frame.add(0)        // Block size minus one.
    frame.add(flacTestHeaderCrc8(frame.toSlice()))

    var bitCount = frame.count * 8
    flacTestAppendBits(&frame, &bitCount, 0, 8)                // Constant mid subframe.
    flacTestAppendBits(&frame, &bitCount, 0xFFFF_FFFF, 32)     // Mid = -1.
    flacTestAppendBits(&frame, &bitCount, 0, 8)                // Constant side subframe.
    flacTestAppendBits(&frame, &bitCount, 0xFFFF_FFFF, 33)     // Side = 2^32 - 1.
    while bitCount & 7
    {
        flacTestAppendBits(&frame, &bitCount, 0, 1)
    }

    let checksum = Flac.frameCrc16(frame.toSlice())
    frame.add(cast(u8, checksum >> 8))
    frame.add(cast(u8, checksum & 0xFF))
    return frame
}

private func flacFrameWithInvalidSampleNumberPrefix()->Array!{u8}
{
    let valid = flacWideMidSideFrame()
    var frame: Array!{u8}
    for index in 5
    {
        frame.add(valid[index])
    }

    frame.add(0xFF)
    for 6
    {
        frame.add(0x80)
    }

    frame.add(valid[5])     // Block-size extension follows the seven-byte sample number.
    frame.add(flacTestHeaderCrc8(frame.toSlice()))
    frame.add(valid[7 until valid.count - 2])

    let checksum = Flac.frameCrc16(frame.toSlice())
    frame.add(cast(u8, checksum >> 8))
    frame.add(cast(u8, checksum & 0xFF))
    return frame
}

private func flacFrameWithInvalidSampleNumberContinuation()->Array!{u8}
{
    let valid = flacWideMidSideFrame()
    var frame: Array!{u8}
    for index in 4
    {
        frame.add(valid[index])
    }

    frame.add(0xC2)         // Valid two-byte number prefix.
    frame.add(0x00)         // Not a UTF-8 continuation byte.
    frame.add(valid[5])     // Block-size extension follows the encoded number.
    frame.add(flacTestHeaderCrc8(frame.toSlice()))
    frame.add(valid[7 until valid.count - 2])

    let checksum = Flac.frameCrc16(frame.toSlice())
    frame.add(cast(u8, checksum >> 8))
    frame.add(cast(u8, checksum & 0xFF))
    return frame
}

// FLAC is lossless, so the only acceptable result is the exact stream that was encoded.
//
// The reference is the interleaved 16-bit PCM the fixture was produced from, not this module's own
// output, so a decoder that is merely self-consistent cannot pass.
private func flacAssertLossless(name: string, sampleRate, channels: u32)
{
    let path  = audioGetTestDataPath(Format.toString("%.flac", name).toString())
    var sound = expect SoundFile.load(path.toString())
    Swag.require(sound.sampleEncoding() == .Flac)
    Swag.require(sound.sampleRateHz() == sampleRate and sound.numChannels() == channels)

    let decoded = expect flacDecodeAll(&sound)
    let wanted  = expect File.readAllBytes(audioGetTestDataPath(Format.toString("%.pcm", name).toString()).toString())
    Swag.require(sound.sampleFrameCount() * cast(u64, channels) * #sizeof(s16) == wanted.count)
    Swag.require(decoded.count == wanted.count)

    var mismatches = 0_u64
    for index in decoded.count where decoded[index] != wanted[index]
    {
        mismatches += 1
    }

    if mismatches
    {
        Swag.print("flac ", name, ": ", mismatches, " of ", decoded.count, " bytes differ\n")
    }

    Swag.require(mismatches == 0)
}

// Stereo, 44.1 kHz, sixteen bits: the shape a music file has.
#test
{
    flacAssertLossless("flac-stereo-44100", 44_100, 2)
}

// Six channels, 48 kHz: the shape a film track has, and the one whose channel order a container
// hands over unchanged.
#test
{
    flacAssertLossless("flac-5.1-48000", 48_000, 6)
}

// Both Rice parameter widths can fall back between groups when a code crosses the input word.
#test
{
    const Samples: [21] s16 = [0, 1, -1, 2, 511, -4, 6, -2, 8, -5, 5, -6, -7, 4, -6, 2, -5, 4, -2, 4, 3]
    for parameter in [2_u32, 16]
    {
        let wide          = parameter == 16
        let inputShift    = wide ? 12_u32 : 0
        let outputShift   = wide ? 4_u32 : 0
        let remainderMask = (1_u64 << parameter) - 1
        var frame: Array!{u8}
        frame.add([0xFF_u8, 0xF9, 0x60, 0, 0, cast(u8, Samples.count - 1)])
        frame.add(flacTestHeaderCrc8(frame.toSlice()))

        // A zero-order fixed predictor leaves the Rice residuals as the output samples.
        var bitCount = frame.count * 8
        flacTestAppendBits(&frame, &bitCount, 0x10, 8)
        flacTestAppendBits(&frame, &bitCount, wide ? 1 : 0, 2)
        flacTestAppendBits(&frame, &bitCount, 0, 4)     // One partition.
        flacTestAppendBits(&frame, &bitCount, cast(u64, parameter), wide ? 5 : 4)
        for sample in Samples
        {
            let twice = cast(u64, Math.abs(cast(s32, sample))) << (inputShift + 1)
            let code  = sample < 0 ? twice - 1 : twice
            for code >> parameter
            {
                flacTestAppendBits(&frame, &bitCount, 0, 1)
            }

            flacTestAppendBits(&frame, &bitCount, 1, 1)
            flacTestAppendBits(&frame, &bitCount, code & remainderMask, parameter)
        }

        while bitCount & 7
        {
            flacTestAppendBits(&frame, &bitCount, 0, 1)
        }

        let checksum = Flac.frameCrc16(frame.toSlice())
        frame.add(cast(u8, checksum >> 8))
        frame.add(cast(u8, checksum & 0xFF))

        var codec:   Flac.Codec
        let decoder: IPacketCodec = &codec
        let config = flacMonoTestConfig(cast(u8, Samples.count), depth: wide ? 24 : 16)
        expect decoder.initialize(config.toSlice(), 48_000, 1)
        var decoded: [Samples.count] s16
        let bytes = expect decoder.decodePacket(cast([*] void, &decoded[0]), #sizeof(decoded), frame.toSlice())
        Swag.require(bytes == #sizeof(decoded))
        for index in Samples.count
        {
            Swag.require(decoded[index] == Samples[index] << outputShift)
        }

        var error: Swag.Error
        discard catch decoder.decodePacket(cast([*] void, &decoded[0]), #sizeof(decoded), frame.toSlice()[until frame.count - 9]) as error
        Swag.require(error.value() is InvalidFormatError)
    }
}

// The side subframe of 32-bit mid/side stereo needs 33 bits to reconstruct the full PCM range.
#test
{
    var codec:   Flac.Codec
    let decoder: IPacketCodec = &codec
    let config = flacWideStereoTestConfig()
    expect decoder.initialize(config.toSlice(), 48_000, 2)

    var decoded: [2] s16
    let frame = flacWideMidSideFrame()
    let bytes = expect decoder.decodePacket(cast([*] void, &decoded[0]), 2 * #sizeof(s16), frame.toSlice())
    Swag.require(bytes == 2 * #sizeof(s16))
    Swag.require(decoded[0] == Swag.S16.Max and decoded[1] == Swag.S16.Min)
}

// 24-bit verbatim samples retain their sign and use the most significant sixteen bits at output.
#test
{
    var codec:   Flac.Codec
    let decoder: IPacketCodec = &codec
    let config = flac24BitStereoTestConfig()
    expect decoder.initialize(config.toSlice(), 48_000, 2)

    var decoded: [12] s16
    let frame = flac24BitStereoTestFrame()
    let bytes = expect decoder.decodePacket(cast([*] void, &decoded[0]), 12 * #sizeof(s16), frame.toSlice())
    Swag.require(bytes == 12 * #sizeof(s16))
    audioAssertSamples(cast([..] u8, decoded), [
        32767_s16, -32768_s16,
        32767, -32767,
        1, -1,
        0, -1,
        -1, 1,
        -32768, 32767])
}

// Signed QLP shifts right-scale when positive and left-scale when negative across the full range.
#test
{
    var codec:   Flac.Codec
    let decoder: IPacketCodec = &codec
    let config = flacMonoTestConfig()
    expect decoder.initialize(config.toSlice(), 48_000, 1)

    var decoded: [2] s16
    let frame = flacLinearShiftFrame(0b1_1111)     // -1.
    let bytes = expect decoder.decodePacket(cast([*] void, &decoded[0]), 2 * #sizeof(s16), frame.toSlice())
    Swag.require(bytes == 2 * #sizeof(s16))
    audioAssertSamples(cast([..] u8, decoded), [1_s16, 2_s16])

    let rightShiftFrame = flacLinearShiftFrame(1)
    discard expect decoder.decodePacket(cast([*] void, &decoded[0]), 2 * #sizeof(s16), rightShiftFrame.toSlice())
    audioAssertSamples(cast([..] u8, decoded), [1_s16, 0_s16])

    let minShiftFrame = flacLinearShiftFrame(0b1_0000)     // -16, the signed field's lower bound.
    discard expect decoder.decodePacket(cast([*] void, &decoded[0]), 2 * #sizeof(s16), minShiftFrame.toSlice())
    audioAssertSamples(cast([..] u8, decoded), [1_s16, 32767_s16])

    let maxShiftFrame = flacLinearShiftFrame(0b0_1111)     // +15, the signed field's upper bound.
    discard expect decoder.decodePacket(cast([*] void, &decoded[0]), 2 * #sizeof(s16), maxShiftFrame.toSlice())
    audioAssertSamples(cast([..] u8, decoded), [1_s16, 0_s16])
}

// The 24-bit predictor uses both signed history planes before finishing a scalar tail.
#test
{
    const Warmup:   [4] s32 = [1_200_003, -700_007, 2_000_010, -1_000_017]
    const Taps:     [4] s32 = [2, -1, 1, -2]
    const Residual: [9] s32 = [25, -40, 33, -9, 71, -15, 11, 32, -21]
    const Frames = Warmup.count + Residual.count

    var frame: Array!{u8}
    frame.add([0xFF_u8, 0xF9, 0x60, 0, 0, cast(u8, Frames - 1)])
    frame.add(flacTestHeaderCrc8(frame.toSlice()))
    var bits = frame.count * 8
    flacTestAppendBits(&frame, &bits, 0x46, 8)     // Order-four LPC subframe.
    for sample in Warmup
    {
        flacTestAppendBits(&frame, &bits, cast #wrap(u64, sample) & 0xFF_FFFF, 24)
    }

    flacTestAppendBits(&frame, &bits, 4, 4)     // Five-bit coefficients.
    flacTestAppendBits(&frame, &bits, 2, 5)     // Right shift by two.
    for tap in Taps
    {
        flacTestAppendBits(&frame, &bits, cast #wrap(u64, tap) & 31, 5)
    }

    flacTestAppendBits(&frame, &bits, 0, 6)      // Rice coding with one partition.
    flacTestAppendBits(&frame, &bits, 15, 4)     // Escape to fixed-width residuals.
    flacTestAppendBits(&frame, &bits, 8, 5)
    for value in Residual
    {
        flacTestAppendBits(&frame, &bits, cast #wrap(u64, value) & 255, 8)
    }

    while bits & 7
    {
        flacTestAppendBits(&frame, &bits, 0, 1)
    }

    let checksum = Flac.frameCrc16(frame.toSlice())
    frame.add(cast(u8, checksum >> 8))
    frame.add(cast(u8, checksum & 0xFF))

    var codec:   Flac.Codec
    let decoder: IPacketCodec = &codec
    let config = flacMonoTestConfig(cast(u8, Frames), depth: 24)
    expect decoder.initialize(config.toSlice(), 48_000, 1)
    var decoded: [Frames] s16
    let written = expect decoder.decodePacket(cast([*] void, &decoded[0]), #sizeof(decoded), frame.toSlice())
    Swag.require(written == #sizeof(decoded))
    audioAssertSamples(cast([..] u8, decoded), [4687_s16, -2735, 7812, -3907, -6934, 829, -2735, -1355, 3680, 1080, 648, 1651, -907])
}

// Channel interleaving preserves clipping for predictor output wider than signed 32 bits.
#test
{
    const Channels      = 6
    const Wide: [5] s64 = [0x1_0000_0001, -0x1_0000_0002, 0x8000_0000, -0x8000_0001, 43]
    const Frames        = Wide.count
    const Parameter     = 30
    const Mask          = (1_u64 << Parameter) - 1

    var config = flacMonoTestConfig(cast(u8, Frames))
    config[12] |= cast(u8, (Channels - 1) << 1)

    var frame: Array!{u8}
    frame.add([0xFF_u8, 0xF9, 0x60, 0x50, 0, cast(u8, Frames - 1)])
    frame.add(flacTestHeaderCrc8(frame.toSlice()))
    var bits = frame.count * 8
    var expected: [Frames * Channels] s16
    for channel in Channels
    {
        flacTestAppendBits(&frame, &bits, 0x10, 8)     // Order-zero fixed predictor.
        flacTestAppendBits(&frame, &bits, 1, 2)        // Rice2 residuals.
        flacTestAppendBits(&frame, &bits, 0, 4)        // One partition.
        flacTestAppendBits(&frame, &bits, Parameter, 5)
        for sample in Frames
        {
            let value = channel ? cast(s64, channel * 10 + sample) - 20 : Wide[sample]
            let code  = value < 0 ? cast(u64, -value) * 2 - 1 : cast(u64, value) * 2
            for code >> Parameter
            {
                flacTestAppendBits(&frame, &bits, 0, 1)
            }

            flacTestAppendBits(&frame, &bits, 1, 1)
            flacTestAppendBits(&frame, &bits, code & Mask, Parameter)
            expected[sample * Channels + channel] = cast(s16, Math.clamp(value, -32768_s64, 32767_s64))
        }
    }

    while bits & 7
    {
        flacTestAppendBits(&frame, &bits, 0, 1)
    }

    let checksum = Flac.frameCrc16(frame.toSlice())
    frame.add(cast(u8, checksum >> 8))
    frame.add(cast(u8, checksum & 0xFF))

    var codec:   Flac.Codec
    let decoder: IPacketCodec = &codec
    expect decoder.initialize(config.toSlice(), 48_000, Channels)
    var actual: [Frames * Channels] s16
    let written = expect decoder.decodePacket(&actual[0], #sizeof(actual), frame.toSlice())
    Swag.require(written == #sizeof(actual))
    audioAssertSamples(cast([..] u8, actual), expected)
}

// Wide verbatim stereo retains exact samples from independent and unaligned side channels.
#test
{
    const Frames = 5
    const Left:  [Frames] s64 = [0x7FFF_FFFF, -0x8000_0000, -65537, 0, 65536]
    const Right: [Frames] s64 = [-0x8000_0000, 0x7FFF_FFFF, 65536, -1, -65537]

    var config = flacWideStereoTestConfig()
    config[1] = cast(u8, Frames)
    config[3] = cast(u8, Frames)
    flacTestSetTotalSamples(&config, Frames)

    for assignment in [0x10_u8, 0x80]
    {
        var frame: Array!{u8}
        frame.add([0xFF_u8, 0xF9, 0x60, assignment, 0, cast(u8, Frames - 1)])
        frame.add(flacTestHeaderCrc8(frame.toSlice()))
        var bits = frame.count * 8
        flacTestAppendBits(&frame, &bits, 2, 8)     // Verbatim left subframe.
        for sample in Left
        {
            flacTestAppendBits(&frame, &bits, cast #wrap(u64, sample) & 0xFFFF_FFFF, 32)
        }

        flacTestAppendBits(&frame, &bits, 2, 8)
        let width = assignment == 0x10 ? 32_u32 : 33
        let mask  = (1_u64 << width) - 1
        for index in Frames
        {
            let sample = assignment == 0x10 ? Right[index] : Left[index] - Right[index]
            flacTestAppendBits(&frame, &bits, cast #wrap(u64, sample) & mask, width)
        }

        while bits & 7
        {
            flacTestAppendBits(&frame, &bits, 0, 1)
        }

        let checksum = Flac.frameCrc16(frame.toSlice())
        frame.add(cast(u8, checksum >> 8))
        frame.add(cast(u8, checksum & 0xFF))

        var codec:   Flac.Codec
        let decoder: IPacketCodec = &codec
        expect decoder.initialize(config.toSlice(), 48_000, 2)
        var decoded: [Frames * 2] s16
        let written = expect decoder.decodePacket(&decoded[0], #sizeof(decoded), frame.toSlice())
        Swag.require(written == #sizeof(decoded))
        for index in Frames
        {
            Swag.require(decoded[2 * index] == Left[index] >> 16)
            Swag.require(decoded[2 * index + 1] == Right[index] >> 16)
        }

        var errorOutcome: Swag.Error
        discard catch decoder.decodePacket(&decoded[0], #sizeof(decoded), frame.toSlice()[until frame.count - 6]) as errorOutcome
        Swag.require(errorOutcome.value() is InvalidFormatError)
    }
}

// A valid 17-bit side sample can outgrow the packed predictor midway through a block.
#test
{
    var config = flac24BitStereoTestConfig()
    config[3] = 11
    const Description = (48_000_u64 << 44) | (1_u64 << 41) | (15_u64 << 36) | 11
    for byte in 8
    {
        config[10 + byte] = cast(u8, (Description >> (56 - byte * 8)) & 0xFF)
    }

    var frame: Array!{u8}
    frame.add([0xFF_u8, 0xF8, 0x6A, 0x98, 0, 10])
    frame.add(flacTestHeaderCrc8(frame.toSlice()))
    var bits = frame.count * 8
    flacTestAppendBits(&frame, &bits, 0x44, 8)     // Order-three predictor on the 17-bit side channel.
    for 3
    {
        flacTestAppendBits(&frame, &bits, 0, 17)
    }

    flacTestAppendBits(&frame, &bits, 1, 4)     // Two-bit coefficients.
    flacTestAppendBits(&frame, &bits, 0, 5)     // No prediction shift.
    flacTestAppendBits(&frame, &bits, 1, 2)
    flacTestAppendBits(&frame, &bits, 0, 4)
    flacTestAppendBits(&frame, &bits, 0, 6)      // Rice method 0, one partition.
    flacTestAppendBits(&frame, &bits, 15, 4)     // Raw residuals.
    flacTestAppendBits(&frame, &bits, 17, 5)
    for delta in [1_u64, 1, 1, 1, 32764, 0, 0x18000, 8]
    {
        flacTestAppendBits(&frame, &bits, delta, 17)
    }

    flacTestAppendBits(&frame, &bits, 0, 8)     // Constant right channel.
    flacTestAppendBits(&frame, &bits, 0xC000, 16)

    var codec: Flac.Codec
    let itf:   IPacketCodec = &codec
    expect itf.initialize(config.toSlice(), 48_000, 2)
    var pcm: [22] s16
    let produced = expect itf.decodePacket(&pcm[0], #sizeof(pcm), frame.toSlice())
    Swag.require(produced == #sizeof(pcm))
    const Left: [11] s16 = [-16384, -16384, -16384, -16383, -16382, -16381, -16380, 16384, 16384, -16384, -16376]
    for index in Left.count
    {
        Swag.require(pcm[2 * index] == Left[index])
        Swag.require(pcm[2 * index + 1] == -16384)
    }
}

// A malformed linear predictor cannot overflow the signed accumulator on a left shift.
#test
{
    var codec:   Flac.Codec
    let decoder: IPacketCodec = &codec
    let config = flacLinearOverflowTestConfig()
    expect decoder.initialize(config.toSlice(), 48_000, 1)

    var decoded:      [33] s16
    let frame = flacOverflowingLinearShiftFrame()
    var errorOutcome: Swag.Error
    discard catch decoder.decodePacket(cast([*] void, &decoded[0]), 33 * #sizeof(s16), frame.toSlice()) as errorOutcome
    Swag.require(errorOutcome.value() is InvalidFormatError)
}

// A representable prediction and residual can still overflow when added together.
#test
{
    var codec:   Flac.Codec
    let decoder: IPacketCodec = &codec
    let config = flacLinearOverflowTestConfig(6)
    expect decoder.initialize(config.toSlice(), 48_000, 1)

    var decoded:      [6] s16
    let frame = flacOverflowingLinearAdditionFrame()
    var errorOutcome: Swag.Error
    discard catch decoder.decodePacket(cast([*] void, &decoded[0]), 6 * #sizeof(s16), frame.toSlice()) as errorOutcome
    Swag.require(errorOutcome.value() is InvalidFormatError)
}

// 0xFE is FLAC's seven-byte number prefix; 0xFF is reserved and rejected.
#test
{
    var codec:   Flac.Codec
    let decoder: IPacketCodec = &codec
    let config = flacWideStereoTestConfig()
    expect decoder.initialize(config.toSlice(), 48_000, 2)

    var decoded:      [2] s16
    let frame = flacFrameWithInvalidSampleNumberPrefix()
    var errorOutcome: Swag.Error
    discard catch decoder.decodePacket(cast([*] void, &decoded[0]), 2 * #sizeof(s16), frame.toSlice()) as errorOutcome
    Swag.require(errorOutcome.value() is InvalidFormatError)

    // The container index must reject the same invalid prefix before exposing a packet.
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("audio-flac-invalid-number-%.flac", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())
    var fileBytes: Array!{u8}
    fileBytes.add("fLaC")
    fileBytes.add(0x80)     // Last metadata block: STREAMINFO.
    fileBytes.add(0)
    fileBytes.add(0)
    fileBytes.add(34)
    fileBytes.add(config.toSlice())
    fileBytes.add(frame.toSlice())
    expect File.writeAllBytes(path.toString(), fileBytes.toSlice())

    discard catch SoundFile.load(path.toString()) as errorOutcome
    Swag.require(errorOutcome.value() is InvalidFormatError)
}

// A syntactically valid FLAC frame-number lead still needs UTF-8 continuation bytes.
#test
{
    var codec:   Flac.Codec
    let decoder: IPacketCodec = &codec
    let config = flacWideStereoTestConfig()
    expect decoder.initialize(config.toSlice(), 48_000, 2)

    var decoded:      [2] s16
    let frame = flacFrameWithInvalidSampleNumberContinuation()
    var errorOutcome: Swag.Error
    discard catch decoder.decodePacket(cast([*] void, &decoded[0]), 2 * #sizeof(s16), frame.toSlice()) as errorOutcome
    Swag.require(errorOutcome.value() is InvalidFormatError)

    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("audio-flac-invalid-number-continuation-%.flac", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())
    var fileBytes: Array!{u8}
    fileBytes.add("fLaC")
    fileBytes.add(0x80)     // Last metadata block: STREAMINFO.
    fileBytes.add(0)
    fileBytes.add(0)
    fileBytes.add(34)
    fileBytes.add(config.toSlice())
    fileBytes.add(frame.toSlice())
    expect File.writeAllBytes(path.toString(), fileBytes.toSlice())

    discard catch SoundFile.load(path.toString()) as errorOutcome
    Swag.require(errorOutcome.value() is InvalidFormatError)
}

// Opening a file walks its frame headers rather than its audio, and the index it builds agrees
// with the length the stream information states.
#test
{
    var sound = expect SoundFile.load(audioGetTestDataPath("flac-5.1-48000.flac").toString())
    Swag.require(sound.isPacketStream() and not sound.isDataPreloaded())
    Swag.require(sound.packetCount() == 6)
    Swag.require((expect sound.packet(0)).sampleFrameCount == 4608)
    Swag.require(sound.sampleFrameCount() == 24_000)
    Swag.require(sound.speakerChannelMask() == 0x3F)
}

// A file that carries the marker and nothing else fails on its own terms rather than being
// decoded into noise.
#test
{
    let directory = Env.getSpecialDirectory(.Temp)
    let path      = Path.combine(directory.toString(),
                                 Format.toString("audio-flac-%.flac", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())

    var bytes: Array!{u8}
    bytes.add("fLaC")
    expect File.writeAllBytes(path.toString(), bytes.toSlice())
    var errOutcome: Swag.Error
    discard catch SoundFile.load(path.toString()) as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
}

// The first byte of a frame header can be the last byte in a read window.
#test
{
    let original = audioGetTestDataPath("flac-stereo-44100.flac")
    let sound    = expect SoundFile.load(original.toString())
    let second   = expect sound.packet(1)
    let bytes    = expect File.readAllBytes(original.toString())
    let boundary = ByteSource.WindowSize - 1

    // Insert a metadata padding block after the marker and STREAMINFO.
    const StreamInfoEnd = 42
    let padding = boundary - second.sourceOffset - 4
    var shifted: Array!{u8}
    shifted.add(bytes.toSlice()[until StreamInfoEnd])
    shifted.add(1)
    shifted.add(cast(u8, (padding >> 16)))
    shifted.add(cast(u8, (padding >> 8) & 0xFF))
    shifted.add(cast(u8, padding & 0xFF))
    shifted.resize(shifted.count + padding)
    shifted.add(bytes.toSlice()[StreamInfoEnd until])

    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("audio-flac-window-%.flac", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())
    expect File.writeAllBytes(path.toString(), shifted.toSlice())

    let loaded = expect SoundFile.load(path.toString())
    Swag.require(loaded.packetCount() == sound.packetCount())
    Swag.require((expect loaded.packet(1)).sourceOffset == boundary)
}

// STREAMINFO's nonzero total sample count must match the indexed frame lengths exactly.
#test
{
    let source = expect File.readAllBytes(audioGetTestDataPath("flac-5.1-48000.flac").toString())
    let path   = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                              Format.toString("audio-flac-total-samples-%.flac", Guid128.random()).toString())
    defer discard catch File.delete(path.toString())

    for total in [23_999_u64, 24_001]
    {
        var bytes: Array!{u8}
        bytes.add(source.toSlice())
        flacTestSetTotalSamples(&bytes, total)
        expect File.writeAllBytes(path.toString(), bytes.toSlice())

        var error: Swag.Error
        discard catch SoundFile.load(path.toString()) as error
        Swag.require(error.value() is InvalidFormatError)
    }
}

// A final frame with its CRC16 trailer truncated is rejected while the file is indexed.
#test
{
    let source = expect File.readAllBytes(audioGetTestDataPath("flac-stereo-44100.flac").toString())
    var bytes: Array!{u8}
    bytes.add(source.toSlice()[until source.count - 1])

    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("audio-flac-truncated-frame-%.flac", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())
    expect File.writeAllBytes(path.toString(), bytes.toSlice())

    var error: Swag.Error
    discard catch SoundFile.load(path.toString()) as error
    Swag.require(error.value() is InvalidFormatError)
}

// The codec is reachable through the registry a container uses, and what a voice plays back is
// the start of the same reference stream.
#test
{
    var sound = expect SoundFile.load(audioGetTestDataPath("flac-5.1-48000.flac").toString())

    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = expect Voice.create(&sound)
    defer voice.destroy()
    let decoded = expect voice.readBuffer()
    Swag.require(decoded.size != 0)

    let wanted = expect File.readAllBytes(audioGetTestDataPath("flac-5.1-48000.pcm").toString())
    let bytes  = cast(const [*] u8, unwrap decoded.buffer)
    let count  = Math.min(cast(u64, decoded.size), wanted.count)
    for index in count
    {
        Swag.require(bytes[index] == wanted[index])
    }
}

// Older muxers can add an empty packet after the last FLAC frame on the EOS page.
#test
{
    let originalPath = audioGetTestDataPath("flac-stereo-44100.oga")
    let source       = expect File.readAllBytes(originalPath.toString())
    let original     = expect SoundFile.load(originalPath, preloadData: false)

    var pageOffset = 0_u64
    var page = expect Ogg.readPageHeader(source.toSlice(), pageOffset)
    while (page.flags & Ogg.LastPage) == 0
    {
        pageOffset += page.totalBytes()
        page = expect Ogg.readPageHeader(source.toSlice(), pageOffset)
    }

    Swag.require(pageOffset + page.totalBytes() == source.count)
    Swag.require(page.segments < 255 and page.segments != 0)
    Swag.require(page.lacing[page.segments - 1] < 255)
    let lacingEnd = pageOffset + page.headerBytes
    var bytes: Array!{u8}
    bytes.add(source.toSlice()[until lacingEnd])
    bytes.add(0_u8)
    bytes.add(source.toSlice()[lacingEnd until])
    bytes[pageOffset + 26] += 1
    let checksum = Ogg.pageChecksum(bytes.toSlice()[pageOffset until])
    for index in 4
    {
        bytes[pageOffset + 22 + index] = cast(u8, (checksum >> (8 * index)) & 0xFF)
    }

    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(),
                            Format.toString("audio-flac-empty-eos-%.oga", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())
    expect File.writeAllBytes(path.toString(), bytes.toSlice())
    let sound = expect SoundFile.load(path.toString(), preloadData: false)
    Swag.require(sound.sampleFrameCount() == original.sampleFrameCount())

    var reference, decoded: Array!{s16}
    expect original.decodePcm16(func|&reference|(part)
    {
        reference.add(part)
        return true
    })
    expect sound.decodePcm16(func|&decoded|(part)
    {
        decoded.add(part)
        return true
    })
    Swag.require(not reference.isEmpty())
    Swag.require(Slice.equals(decoded.toSlice(), reference.toSlice()))
}

// A range through several FLAC decode batches keeps the packet callback boundaries on the caller.
#test
{
    for name in ["flac-stereo-44100.flac", "flac-stereo-44100.oga"]
    {
        let original = expect SoundFile.load(audioGetTestDataPath(name), preloadData: false)
        let packet   = expect original.packet(0)
        let channels = original.numChannels()
        let frames   = cast(u64, packet.sampleFrameCount)
        let samples  = frames * channels
        var reference: Array!{s16}
        expect original.decodePcm16(0, frames, func|&reference|(part)
        {
            reference.add(part)
            return true
        })
        Swag.require(reference.count == samples)

        // More than two MiB of PCM exercises multiple bounded read-ahead batches.
        var packets: Array!{SoundPacket}
        let packetCount = 2 * 1024 * 1024_u64 / (samples * #sizeof(s16)) + 8
        for packetCount
        {
            packets.add(packet)
        }

        let source = expect SoundFile.openPacketStream(original.sourcePath(),
                                                       .Flac,
                                                       original.sampleRateHz(),
                                                       channels,
                                                       frames * packetCount,
                                                       packets.toSlice(),
                                                       original.decoderConfig.toSlice())

        var callbacks = 0_u64
        let caller    = Swag.getContext()
        let expected  = reference.toSlice()
        expect source.decodePcm16(1, frames * packetCount - 2, func|&callbacks, caller, expected, channels, packetCount|(part)
        {
            Swag.require(Swag.getContext() == caller)
            let first = callbacks == 0 ? cast(u64, channels) : 0
            let last  = callbacks + 1 == packetCount ? expected.count - channels : expected.count
            Swag.require(Slice.equals(part, expected[first until last]))
            callbacks += 1
            return true
        })
        Swag.require(callbacks == packetCount)
    }
}

// A failure from speculative read-ahead is observed only after earlier callbacks accept the data.
#test
{
    let original    = expect SoundFile.load(audioGetTestDataPath("flac-stereo-44100.flac"), preloadData: false)
    let packet      = expect original.packet(0)
    let frames      = cast(u64, packet.sampleFrameCount)
    let channels    = original.numChannels()
    var packets: Array!{SoundPacket}
    let packetCount = 1024 * 1024_u64 / (frames * channels * #sizeof(s16)) + 8
    for packetCount
    {
        packets.add(packet)
    }

    let invalidAt = packetCount / 2
    packets[invalidAt].byteSize = 1
    let source = expect SoundFile.openPacketStream(original.sourcePath(),
                                                   .Flac,
                                                   original.sampleRateHz(),
                                                   channels,
                                                   frames * packetCount,
                                                   packets.toSlice(),
                                                   original.decoderConfig.toSlice())

    var callbacks = 0_u64
    expect source.decodePcm16(func|&callbacks|(_)
    {
        callbacks += 1
        return callbacks == 1
    })
    Swag.require(callbacks == 2)

    callbacks = 0
    var outcome: Swag.Error
    catch source.decodePcm16(func|&callbacks|(_)
    {
        callbacks += 1
        return true
    }) as outcome
    Swag.require(callbacks == invalidAt)
    Swag.require(outcome.value() is InvalidFormatError)

    // The first packet runs directly. A failure must not publish its unwritten PCM.
    packets[0].byteSize = 1
    let invalid = expect SoundFile.openPacketStream(original.sourcePath(),
                                                    .Flac,
                                                    original.sampleRateHz(),
                                                    channels,
                                                    frames * packetCount,
                                                    packets.toSlice(),
                                                    original.decoderConfig.toSlice())
    callbacks = 0
    var firstError: Swag.Error
    catch invalid.decodePcm16(func|&callbacks|(_)
    {
        callbacks += 1
        return true
    }) as firstError
    Swag.require(callbacks == 0)
    Swag.require(firstError.value() is InvalidFormatError)
}
