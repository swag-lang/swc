//! Format: BC7 block decompression for DDS and KTX2.
//! Supported: All eight BC7 UNORM and SRGB modes, with packed RGBA8 output.
//! Role: This file extracts BC7 endpoints and indices and reconstructs each block.
//
// @LICENCE: MIT
// @ORIGIN: bcdec partition and fix-up tables, https://github.com/iOrange/bcdec
// @MODIFIED: Packed the normative partition and anchor tables for the Swag decoder.
// @NOTICE: /bin/THIRDPARTY.md#bcdec

#global namespace TextureBlocks

using Core, Core.Math

private struct Bc7Mode
{
    subsets:       u32
    partitionBits: u32
    colorBits:     u32
    alphaBits:     u32
    hasPBits:      bool
    primaryBits:   u32
    secondaryBits: u32
}

private const Bc7Modes: [8] Bc7Mode = [
    {3, 4, 4, 0, true,  3, 0},
    {2, 6, 6, 0, true,  3, 0},
    {3, 6, 5, 0, false, 2, 0},
    {2, 6, 7, 0, true,  2, 0},
    {1, 0, 5, 6, false, 2, 3},
    {1, 0, 7, 8, false, 2, 2},
    {1, 0, 7, 7, true,  4, 0},
    {2, 6, 5, 5, true,  2, 0}]

// Low 32 bits hold two-bit subset numbers. Bits 32–47 mark short fix-up indices.
private const Bc7Partitions: [2, 64] u64 = [
    [
        0x8001_5050_5050_u64, 0x8001_4040_4040_u64, 0x8001_5454_5454_u64, 0x8001_5450_5040_u64,
        0x8001_5040_4000_u64, 0x8001_5554_5450_u64, 0x8001_5554_5040_u64, 0x8001_5450_4000_u64,
        0x8001_5040_0000_u64, 0x8001_5555_5450_u64, 0x8001_5554_4000_u64, 0x8001_5440_0000_u64,
        0x8001_5555_5440_u64, 0x8001_5555_0000_u64, 0x8001_5555_5500_u64, 0x8001_5500_0000_u64,
        0x8001_5515_0100_u64, 0x0005_0000_4054_u64, 0x0101_1501_0000_u64, 0x0005_0040_5054_u64,
        0x0005_0000_4050_u64, 0x0101_1505_0100_u64, 0x0101_0501_0000_u64, 0x8001_4050_5054_u64,
        0x0005_0040_4050_u64, 0x0101_0501_0100_u64, 0x0005_1414_1414_u64, 0x0005_0514_1450_u64,
        0x0101_0115_5440_u64, 0x0101_0055_5500_u64, 0x0005_1501_4054_u64, 0x0005_0541_4150_u64,
        0x8001_4444_4444_u64, 0x8001_5500_5500_u64, 0x0041_1144_1144_u64, 0x0101_0505_5050_u64,
        0x0005_0550_0550_u64, 0x0101_1111_4444_u64, 0x8001_4114_4114_u64, 0x8001_4411_1144_u64,
        0x0005_1505_5054_u64, 0x0101_0105_5040_u64, 0x0005_0504_1050_u64, 0x0005_0545_5150_u64,
        0x0005_1441_4114_u64, 0x8001_5005_0550_u64, 0x8001_4141_1414_u64, 0x0041_0014_1400_u64,
        0x0041_0004_1504_u64, 0x0005_0010_5410_u64, 0x0041_1054_1000_u64, 0x0101_0415_0400_u64,
        0x8001_5041_0514_u64, 0x8001_4105_1450_u64, 0x0005_0541_5014_u64, 0x0005_1405_4150_u64,
        0x8001_4105_0514_u64, 0x8001_4150_5014_u64, 0x8001_4001_1554_u64, 0x8001_5415_0140_u64,
        0x8001_5050_5500_u64, 0x0005_0055_5050_u64, 0x0005_1515_1010_u64, 0x8001_5454_0404_u64],
    [
        0x8009_AA68_5050_u64, 0x0109_6A5A_5040_u64, 0x8101_5A5A_4200_u64, 0x8009_5450_A0A8_u64,
        0x8101_A5A5_0000_u64, 0x8009_A0A0_5050_u64, 0x8009_5555_A0A0_u64, 0x8101_5A5A_5050_u64,
        0x8101_AA55_0000_u64, 0x8101_AA55_5500_u64, 0x8041_AAAA_5500_u64, 0x8041_9090_9090_u64,
        0x8041_9494_9494_u64, 0x8021_A4A4_A4A4_u64, 0x8009_A9A5_9450_u64, 0x0109_2A0A_4250_u64,
        0x8009_A594_5040_u64, 0x0109_0A42_5054_u64, 0x8101_A5A5_A500_u64, 0x8009_55A0_A0A0_u64,
        0x8009_A8A8_5454_u64, 0x0109_6A6A_4040_u64, 0x8041_A4A4_5000_u64, 0x0501_1A1A_0500_u64,
        0x0029_0050_A4A4_u64, 0x8101_AAA5_9090_u64, 0x0141_1469_6914_u64, 0x0441_6969_1400_u64,
        0x8101_A085_85A0_u64, 0x8021_AA82_1414_u64, 0x8401_50A4_A450_u64, 0x8101_6A5A_0200_u64,
        0x8101_A9A5_8000_u64, 0x8009_5090_A0A8_u64, 0x8009_A8A0_9050_u64, 0x0421_2424_2424_u64,
        0x0441_00AA_5500_u64, 0x0501_2492_4924_u64, 0x0301_2449_9224_u64, 0x8401_50A5_0A50_u64,
        0x8041_500A_A550_u64, 0x8009_AAAA_4444_u64, 0x8101_6666_0000_u64, 0x8021_A5A0_A5A0_u64,
        0x8009_50A0_50A0_u64, 0x8041_6928_6928_u64, 0x8041_44AA_AA44_u64, 0x8101_6666_6600_u64,
        0x8009_AA44_4444_u64, 0x8009_54A8_54A8_u64, 0x8021_9580_9580_u64, 0x8021_9696_9600_u64,
        0x8021_A854_54A8_u64, 0x8101_8095_9580_u64, 0x8021_AA14_1414_u64, 0x8401_9696_0000_u64,
        0x8021_AAAA_1414_u64, 0x8401_A050_50A0_u64, 0x8101_A0A5_A5A0_u64, 0xA001_9600_0000_u64,
        0x8009_4080_4080_u64, 0x9001_A9A8_A9A8_u64, 0x8009_AAAA_AA44_u64, 0x0109_2A4A_5254_u64]]

private const Bc7Weights2: [4] u8  = [0, 21, 43, 64]
private const Bc7Weights3: [8] u8  = [0, 9, 18, 27, 37, 46, 55, 64]
private const Bc7Weights4: [16] u8 = [0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64]

private struct Bc7Bits
{
    low, high: u64
}

private impl Bc7Bits
{
    #[Swag.Inline]
    mtd read(count: u32)->u32
    {
        let value = cast #wrap(u32, .low) & ((1_u32 << count) - 1)
        .low  = (.low >> count) | (.high << (64 - count))
        .high >>= count
        return value
    }
}

#[Swag.Inline]
private func expandBc7Endpoint(value, bits: u32)->u32
{
    let expanded = value << (8 - bits)
    return expanded | (expanded >> bits)
}

#[Swag.Inline]
private func(T) interpolateBc7(first, second, weight: T)->T
{
    // Multiply two channels in the low and high halves of each word.
    const Channels = 0x00FF_00FF_u32
    const Rounding = 0x0020_0020_u32
    let complement = 64_u32 - weight
    let redBlue    = (first & Channels) * complement + (second & Channels) * weight + Rounding
    let greenAlpha = ((first >> 8) & Channels) * complement + ((second >> 8) & Channels) * weight + Rounding
    return ((redBlue >> 6) & Channels) | (((greenAlpha >> 6) & Channels) << 8)
}

private func bc7Weights(bits: u32)->const [*] u8
{
    if bits == 2
    {
        return Bc7Weights2.buffer
    }

    return bits == 3 ? Bc7Weights3.buffer : Bc7Weights4.buffer
}

private func decodeBc7Mode6(low, high: u64, output: [*] u32)
{
    using Math.Simd

    // Eight seven-bit endpoints start after the mode prefix. The two parity
    // bits extend them to complete bytes at the end of the endpoint stream.
    let first = ((low >> 6) & 0xFE) | ((low >> 12) & 0xFE00) |
                ((low >> 18) & 0xFE0000) | ((low >> 24) & 0xFE000000) |
                ((low >> 63) * 0x01010101)
    let second = ((low >> 13) & 0xFE) | ((low >> 19) & 0xFE00) |
                 ((low >> 25) & 0xFE0000) | ((low >> 31) & 0xFE000000) |
                 ((high & 1) * 0x01010101)
    let left  = splat(cast(u32, first))
    let right = splat(cast(u32, second))

    // The first index has three bits. Zero-fill its missing high bit so that
    // all sixteen indices can use the same nibble shuffle.
    let codes   = (high & ~15_u64) | ((high >> 1) & 7)
    let pairs   = cast #bit(U8x16, splat(codes))
    let upper   = cast #bit(U8x16, (cast #bit(U16x8, pairs) >> 4))
    let indices = interleaveLow(pairs & 15_u8, upper & 15_u8)
    let weights = shuffle(cast(U8x16, Bc7Weights4), indices)
    let first8  = widenLow(weights)
    let second8 = widenHigh(weights)
    store(output, interpolateBc7(left, right, widenLow(first8)))
    store(output + 4, interpolateBc7(left, right, widenHigh(first8)))
    store(output + 8, interpolateBc7(left, right, widenLow(second8)))
    store(output + 12, interpolateBc7(left, right, widenHigh(second8)))
}

func decodeBc7Block(source: const [*] u8, pixels: *[16] u32)
{
    var bits = Bc7Bits{loadAlphaBits(source), loadAlphaBits(source + 8)}
    let mask = cast #wrap(u8, bits.low)
    if not mask
    {
        // The reserved all-zero mode decodes to transparent black.
        Memory.clear(cast([*] u8, pixels), 64)
        return
    }

    if (mask & 127) == 64
    {
        decodeBc7Mode6(bits.low, bits.high, cast([*] u32, pixels))
        return
    }

    let modeIndex = Math.trailingZeros(cast(u32, mask))
    discard bits.read(modeIndex + 1)
    let mode  = &Bc7Modes[modeIndex]
    var shape = 1_u64 << 32
    if mode.partitionBits
    {
        let partition = bits.read(mode.partitionBits)
        shape = Bc7Partitions[mode.subsets - 2, partition]
    }

    let rotation    = mode.secondaryBits ? bits.read(2) : 0
    let swapIndices = modeIndex == 4 and bits.read(1) != 0
    var components: [4, 6] u32
    let endpoints   = mode.subsets * 2
    for channel in (mode.alphaBits ? 4 : 3)
    {
        let count = channel == 3 ? mode.alphaBits : mode.colorBits
        for endpoint in endpoints
        {
            components[channel, endpoint] = bits.read(count)
        }
    }

    var parity: [6] u32
    if mode.hasPBits
    {
        if modeIndex == 1
        {
            for subset in mode.subsets
            {
                let pbit = bits.read(1)
                parity[2 * subset], parity[2 * subset + 1] = pbit
            }
        }
        else
        {
            for endpoint in endpoints
            {
                parity[endpoint] = bits.read(1)
            }
        }
    }

    var colors: [6] u32
    let extra = cast(u32, mode.hasPBits)
    for endpoint in endpoints
    {
        let red   = expandBc7Endpoint((components[0, endpoint] << extra) | parity[endpoint], mode.colorBits + extra)
        let green = expandBc7Endpoint((components[1, endpoint] << extra) | parity[endpoint], mode.colorBits + extra)
        let blue  = expandBc7Endpoint((components[2, endpoint] << extra) | parity[endpoint], mode.colorBits + extra)
        let alpha = mode.alphaBits ? expandBc7Endpoint((components[3, endpoint] << extra) | parity[endpoint], mode.alphaBits + extra) : 255
        colors[endpoint] = red | (green << 8) | (blue << 16) | (alpha << 24)
    }

    let primary = bc7Weights(mode.primaryBits)
    if mode.secondaryBits
    {
        let secondary     = bc7Weights(mode.secondaryBits)
        var primaryCode   = bits.read(31)
        var secondaryCode = bits.low
        for pixel in 16
        {
            let firstBits = 2 - cast(u32, pixel == 0)
            let first     = cast(u32, primary[primaryCode & ((1 << firstBits) - 1)])
            primaryCode >>= firstBits
            let secondaryWidth = mode.secondaryBits - cast(u32, pixel == 0)
            let other = cast(u32, secondary[secondaryCode & ((1_u64 << secondaryWidth) - 1)])
            secondaryCode >>= secondaryWidth
            let weight      = swapIndices ? other : first
            let alphaWeight = swapIndices ? first : other
            let alpha       = (((colors[0] >> 24) * (64 - alphaWeight) + (colors[1] >> 24) * alphaWeight + 32) >> 6) << 24
            var color       = (interpolateBc7(colors[0], colors[1], weight) & 0x00FF_FFFF_u32) | alpha
            if rotation
            {
                // Swap alpha with the red, green, or blue component.
                let shift = (rotation - 1) * 8
                let swap  = ((color >> shift) ^ (color >> 24)) & 255
                color ^= (swap << shift) | (swap << 24)
            }

            pixels[][pixel] = color
        }

        return
    }

    var codes   = bits.low
    var anchors = cast(u32, shape >> 32)
    var subsets = cast #wrap(u32, shape)
    for pixel in 16
    {
        let width = mode.primaryBits - (anchors & 1)
        let code  = codes & ((1_u64 << width) - 1)
        codes >>= width
        let set = (subsets & 3) * 2
        pixels[][pixel] = interpolateBc7(colors[set], colors[set + 1], primary[code])
        anchors         >>= 1
        subsets         >>= 2
    }
}
