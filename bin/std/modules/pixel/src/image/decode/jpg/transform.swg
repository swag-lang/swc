//! Format: Joint Photographic Experts Group (JPEG) decoder component.
//! Supported: Baseline and progressive Huffman-coded grayscale, YCbCr, directly sampled RGB, and CMYK or YCCK images.
//! Not supported: Arithmetic coding, lossless JPEG, and unsupported chroma sampling layouts.
//! Role: This file owns inverse DCT and sample reconstruction.
//
#global namespace Jpg

using Swag, Core, Core.Errors

// Byte permutations that weave three channel vectors into eight RGB or BGR triplets.
//
// A table byte of 0x80 clears the destination byte, so the contribution of each source vector is
// combined with a bitwise or.

private
{
    const TripletLowBG  = cast(Math.Simd.U8x16, [0_u8, 8, 0x80, 1, 9, 0x80, 2, 10, 0x80, 3, 11, 0x80, 4, 12, 0x80, 5])
    const TripletLowR   = cast(Math.Simd.U8x16, [0x80_u8, 0x80, 0, 0x80, 0x80, 1, 0x80, 0x80, 2, 0x80, 0x80, 3, 0x80, 0x80, 4, 0x80])
    const TripletHighBG = cast(Math.Simd.U8x16, [13_u8, 0x80, 6, 14, 0x80, 7, 15, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80])
    const TripletHighR  = cast(Math.Simd.U8x16, [0x80_u8, 5, 0x80, 0x80, 6, 0x80, 0x80, 7, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80])
}

// Replicates a row's luma samples across the three channels of the BGR image.
private func expandGrayRow(output: [*] u8, input: const [*] u8, width: s32)
{
    const Triplets0 = cast(Math.Simd.U8x16, [0_u8, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5])
    const Triplets1 = cast(Math.Simd.U8x16, [5_u8, 5, 6, 6, 6, 7, 7, 7, 8, 8, 8, 9, 9, 9, 10, 10])
    const Triplets2 = cast(Math.Simd.U8x16, [10_u8, 11, 11, 11, 12, 12, 12, 13, 13, 13, 14, 14, 14, 15, 15, 15])

    var source      = input
    var destination = output
    var remaining   = width
    while remaining >= 16
    {
        let samples = Math.Simd.load(source)
        Math.Simd.store(destination, Math.Simd.shuffle(samples, Triplets0))
        Math.Simd.store(destination + 16, Math.Simd.shuffle(samples, Triplets1))
        Math.Simd.store(destination + 32, Math.Simd.shuffle(samples, Triplets2))
        source      += 16
        destination += 48
        remaining   -= 16
    }

    for index in remaining
    {
        let sample = source[index]
        destination[0] = sample
        destination[1] = sample
        destination[2] = sample
        destination    += 3
    }
}

// The chroma correction of one group of samples, broadcast over the pixels the group covers.
//
// A pixel is its luma sample plus these three values, so a subsampled chroma sample computes them
// once and every pixel it spans reads the same lane.
private struct ChromaBias
{
    rc: Math.Simd.S16x8
    gc: Math.Simd.S16x8
    bc: Math.Simd.S16x8
}

#[Swag.Inline]

private
{
    // Centers four chroma samples around zero, the way the conversion coefficients expect them.
    func centeredChroma(source: const [*] u8)->Math.Simd.S32x4
    {
        let samples = cast #bit(Math.Simd.S32x4, Math.Simd.widenLow(Math.Simd.widenLow(Math.Simd.load(source))))
        return (samples << 1) - Math.Simd.splat(256_s32)
    }

    // Centers the four low or four high chroma samples of an already widened group of eight.
    func centeredChromaLow(samples: Math.Simd.U16x8)->Math.Simd.S32x4  => (cast #bit(Math.Simd.S32x4, Math.Simd.widenLow(samples)) << 1) - Math.Simd.splat(256_s32)
    func centeredChromaHigh(samples: Math.Simd.U16x8)->Math.Simd.S32x4 => (cast #bit(Math.Simd.S32x4, Math.Simd.widenHigh(samples)) << 1) - Math.Simd.splat(256_s32)

    // The three corrections, in the fixed point the decoded value is defined in.
    func redBias(kr: Math.Simd.S32x4)->Math.Simd.S32x4       => (Math.Simd.splat(FixCrToR) * kr + Math.Simd.splat(1_s32 << 15)) >> 16
    func blueBias(kb: Math.Simd.S32x4)->Math.Simd.S32x4      => (Math.Simd.splat(FixCbToB) * kb + Math.Simd.splat(1_s32 << 15)) >> 16
    func greenBias(kr, kb: Math.Simd.S32x4)->Math.Simd.S32x4 => (Math.Simd.splat(FixCrToG) * kr + Math.Simd.splat(FixCbToG) * kb + Math.Simd.splat(1_s32 << 15)) >> 16

    // Narrows four corrections to eight lanes, each repeated over the pixel pair it covers.
    func duplicatedLanes(value: Math.Simd.S32x4)->Math.Simd.S16x8
    {
        let packed = cast #bit(Math.Simd.U16x8, Math.Simd.packSigned(value, value))
        return cast #bit(Math.Simd.S16x8, Math.Simd.interleaveLow(packed, packed))
    }

    // Joins the low eight bytes of two planes into one vector.
    func joinLow8(low, high: const [*] u8)->Math.Simd.U8x16
    {
        let joined = Math.Simd.interleaveLow(cast #bit(Math.Simd.U64x2, Math.Simd.load(low)), cast #bit(Math.Simd.U64x2, Math.Simd.load(high)))
        return cast #bit(Math.Simd.U8x16, joined)
    }

    // High-half multiplication plus the discarded high bit rounds exactly at 16 fractional bits.
    func roundedHigh(samples: Math.Simd.S16x8, factor: s16)->Math.Simd.S16x8
    {
        let weights = Math.Simd.splat(factor)
        let round   = cast #bit(Math.Simd.S16x8, cast #bit(Math.Simd.U16x8, samples * weights) >> 15)
        return Math.Simd.mulHigh(samples, weights) + round
    }

    // Work with undoubled chroma centered at zero. Split off whole multiples of 65536 so
    // the red and blue factors fit a signed 16-bit multiply. Sum the green terms before rounding.
    func chromaBias8Samples(cb, cr: Math.Simd.U8x16)->ChromaBias
    {
        using Math.Simd

        const Green = cast(S16x8, [cast(s16, FixCbToG), cast(s16, FixCrToG),
                                   cast(s16, FixCbToG), cast(s16, FixCrToG), cast(s16, FixCbToG), cast(s16, FixCrToG),
                                   cast(s16, FixCbToG), cast(s16, FixCrToG)])
        let blue    = cast #bit(S16x8, widenLow(cb)) - 128's16
        let red     = cast #bit(S16x8, widenLow(cr)) - 128's16
        let greenLo = (mulAddPairs(pairLow(blue, red), Green) + (1's32 << 14)) >> 15
        var result: #returntype
        result.bc = roundedHigh(blue, cast(s16, 2 * FixCbToB - 2 * 65536)) + (blue << 1)
        result.rc = roundedHigh(red, cast(s16, 2 * FixCrToR - 65536)) + red
        let greenHi = (mulAddPairs(pairHigh(blue, red), Green) + (1's32 << 14)) >> 15
        result.gc = packSigned(greenLo, greenHi)

        return result
    }

    func chromaBias8(cb, cr: const [*] u8)->ChromaBias => chromaBias8Samples(Math.Simd.load(cb), Math.Simd.load(cr))

    // Each sample of a chroma half serves two horizontally adjacent luma samples.
    func(High: bool) duplicateBias(bias: ChromaBias)->ChromaBias
    {
        #static if High do
            return {pairHigh(bias.rc, bias.rc), pairHigh(bias.gc, bias.gc), pairHigh(bias.bc, bias.bc)}
        else do
            return {pairLow(bias.rc, bias.rc), pairLow(bias.gc, bias.gc), pairLow(bias.bc, bias.bc)}
    }

    // Writes the twenty-four bytes of eight interleaved pixels.
    func storeTriplets(destination: [*] u8, firstGreen, last: Math.Simd.U8x16)
    {
        Math.Simd.store(destination, Math.Simd.shuffle(firstGreen, TripletLowFirstGreen) | Math.Simd.shuffle(last, TripletLowLast))
        Math.Simd.storeLow8(destination + 16, Math.Simd.shuffle(firstGreen, TripletHighFirstGreen) | Math.Simd.shuffle(last, TripletHighLast))
    }

    // Converts eight luma samples and their chroma corrections into eight packed pixels.
    //
    // The saturating narrowing is the clamp the conversion needs: a corrected sample outside the
    // byte range lands on its nearest end.
    func(Rgb: bool) storeColorSamples(destination: [*] u8, luma: Math.Simd.U8x16, bias: ChromaBias)
    {
        let y     = cast #bit(Math.Simd.S16x8, Math.Simd.widenLow(luma))
        let first = Rgb ? bias.rc : bias.bc
        let last  = Rgb ? bias.bc : bias.rc
        storeTriplets(destination, Math.Simd.packUnsigned(y + first, y + bias.gc), Math.Simd.packUnsigned(y + last, y + last))
    }

    func(Rgb: bool) storeColor(destination: [*] u8, luma: const [*] u8, bias: ChromaBias) => storeColorSamples'Rgb(destination, Math.Simd.load(luma), bias)
}

// The transform coefficients, paired the way a multiply-add of adjacent lanes consumes them.
//
// Each pair belongs to two input lines: the even part reads lines 0 and 4, then 2 and 6, and the
// odd part reads lines 1 and 3, then 5 and 7. Every constant below is the sum the scalar form of
// the transform reaches for that line, so both forms compute the same integers.

private
{
    const EvenSum        = cast(Math.Simd.S16x8, [8192_s16, 8192, 8192, 8192, 8192, 8192, 8192, 8192])
    const EvenDifference = cast(Math.Simd.S16x8, [8192_s16, -8192, 8192, -8192, 8192, -8192, 8192, -8192])
    const EvenUpper      = cast(Math.Simd.S16x8, [10703_s16, 4433, 10703, 4433, 10703, 4433, 10703, 4433])
    const EvenLower      = cast(Math.Simd.S16x8, [4433_s16, -10704, 4433, -10704, 4433, -10704, 4433, -10704])

    const Odd0From13 = cast(Math.Simd.S16x8, [2260_s16, -6436, 2260, -6436, 2260, -6436, 2260, -6436])
    const Odd0From57 = cast(Math.Simd.S16x8, [9633_s16, -11363, 9633, -11363, 9633, -11363, 9633, -11363])
    const Odd1From13 = cast(Math.Simd.S16x8, [6437_s16, -11362, 6437, -11362, 6437, -11362, 6437, -11362])
    const Odd1From57 = cast(Math.Simd.S16x8, [2261_s16, 9633, 2261, 9633, 2261, 9633, 2261, 9633])
    const Odd2From13 = cast(Math.Simd.S16x8, [9633_s16, -2259, 9633, -2259, 9633, -2259, 9633, -2259])
    const Odd2From57 = cast(Math.Simd.S16x8, [-11362_s16, -6436, -11362, -6436, -11362, -6436, -11362, -6436])
    const Odd3From13 = cast(Math.Simd.S16x8, [11363_s16, 9633, 11363, 9633, 11363, 9633, 11363, 9633])
    const Odd3From57 = cast(Math.Simd.S16x8, [6437_s16, 2260, 6437, 2260, 6437, 2260, 6437, 2260])
}

#[Swag.Inline]

private
{
    // Pairs the lanes of two vectors, low halves and high halves.
    func pairLow(x, y: Math.Simd.S16x8)->Math.Simd.S16x8  => cast #bit(Math.Simd.S16x8, Math.Simd.interleaveLow(cast #bit(Math.Simd.U16x8, x), cast #bit(Math.Simd.U16x8, y)))
    func pairHigh(x, y: Math.Simd.S16x8)->Math.Simd.S16x8 => cast #bit(Math.Simd.S16x8, Math.Simd.interleaveHigh(cast #bit(Math.Simd.U16x8, x), cast #bit(Math.Simd.U16x8, y)))

    // Transposes eight lines of eight 16-bit lanes, so that a pass over lines becomes a pass over
    // lanes. It is the price of running the eight lines of a pass at once.
    func transpose(v: [*] Math.Simd.S16x8)
    {
        let a0 = pairLow(v[0], v[1])
        let a1 = pairHigh(v[0], v[1])
        let a2 = pairLow(v[2], v[3])
        let a3 = pairHigh(v[2], v[3])
        let a4 = pairLow(v[4], v[5])
        let a5 = pairHigh(v[4], v[5])
        let a6 = pairLow(v[6], v[7])
        let a7 = pairHigh(v[6], v[7])

        let b0 = Math.Simd.interleaveLow(cast #bit(Math.Simd.U32x4, a0), cast #bit(Math.Simd.U32x4, a2))
        let b1 = Math.Simd.interleaveHigh(cast #bit(Math.Simd.U32x4, a0), cast #bit(Math.Simd.U32x4, a2))
        let b2 = Math.Simd.interleaveLow(cast #bit(Math.Simd.U32x4, a1), cast #bit(Math.Simd.U32x4, a3))
        let b3 = Math.Simd.interleaveHigh(cast #bit(Math.Simd.U32x4, a1), cast #bit(Math.Simd.U32x4, a3))
        let b4 = Math.Simd.interleaveLow(cast #bit(Math.Simd.U32x4, a4), cast #bit(Math.Simd.U32x4, a6))
        let b5 = Math.Simd.interleaveHigh(cast #bit(Math.Simd.U32x4, a4), cast #bit(Math.Simd.U32x4, a6))
        let b6 = Math.Simd.interleaveLow(cast #bit(Math.Simd.U32x4, a5), cast #bit(Math.Simd.U32x4, a7))
        let b7 = Math.Simd.interleaveHigh(cast #bit(Math.Simd.U32x4, a5), cast #bit(Math.Simd.U32x4, a7))

        v[0] = cast #bit(Math.Simd.S16x8, Math.Simd.interleaveLow(cast #bit(Math.Simd.U64x2, b0), cast #bit(Math.Simd.U64x2, b4)))
        v[1] = cast #bit(Math.Simd.S16x8, Math.Simd.interleaveHigh(cast #bit(Math.Simd.U64x2, b0), cast #bit(Math.Simd.U64x2, b4)))
        v[2] = cast #bit(Math.Simd.S16x8, Math.Simd.interleaveLow(cast #bit(Math.Simd.U64x2, b1), cast #bit(Math.Simd.U64x2, b5)))
        v[3] = cast #bit(Math.Simd.S16x8, Math.Simd.interleaveHigh(cast #bit(Math.Simd.U64x2, b1), cast #bit(Math.Simd.U64x2, b5)))
        v[4] = cast #bit(Math.Simd.S16x8, Math.Simd.interleaveLow(cast #bit(Math.Simd.U64x2, b2), cast #bit(Math.Simd.U64x2, b6)))
        v[5] = cast #bit(Math.Simd.S16x8, Math.Simd.interleaveHigh(cast #bit(Math.Simd.U64x2, b2), cast #bit(Math.Simd.U64x2, b6)))
        v[6] = cast #bit(Math.Simd.S16x8, Math.Simd.interleaveLow(cast #bit(Math.Simd.U64x2, b3), cast #bit(Math.Simd.U64x2, b7)))
        v[7] = cast #bit(Math.Simd.S16x8, Math.Simd.interleaveHigh(cast #bit(Math.Simd.U64x2, b3), cast #bit(Math.Simd.U64x2, b7)))
    }

    // Only the first four frequencies survive the first pass of a low-frequency block.
    func transposeFirstFour(v: [*] Math.Simd.S16x8)
    {
        let first  = cast #bit(Math.Simd.U32x4, pairLow(v[0], v[1]))
        let second = cast #bit(Math.Simd.U32x4, pairLow(v[2], v[3]))
        let third  = cast #bit(Math.Simd.U32x4, pairLow(v[4], v[5]))
        let fourth = cast #bit(Math.Simd.U32x4, pairLow(v[6], v[7]))
        let low0   = cast #bit(Math.Simd.U64x2, Math.Simd.interleaveLow(first, second))
        let low1   = cast #bit(Math.Simd.U64x2, Math.Simd.interleaveLow(third, fourth))
        let high0  = cast #bit(Math.Simd.U64x2, Math.Simd.interleaveHigh(first, second))
        let high1  = cast #bit(Math.Simd.U64x2, Math.Simd.interleaveHigh(third, fourth))
        v[0] = cast #bit(Math.Simd.S16x8, Math.Simd.interleaveLow(low0, low1))
        v[1] = cast #bit(Math.Simd.S16x8, Math.Simd.interleaveHigh(low0, low1))
        v[2] = cast #bit(Math.Simd.S16x8, Math.Simd.interleaveLow(high0, high1))
        v[3] = cast #bit(Math.Simd.S16x8, Math.Simd.interleaveHigh(high0, high1))
    }

    // Transforms four lines, and leaves their eight results unscaled: the caller owns the rounding
    // and the width, which is what separates the two passes.
    func(LowBand: bool) transformHalf(pair04, pair26, pair13, pair57: Math.Simd.S16x8, result: [*] Math.Simd.S32x4)
    {
        let tmp0 = Math.Simd.mulAddPairs(pair04, EvenSum)
        let tmp1 = LowBand ? tmp0 : Math.Simd.mulAddPairs(pair04, EvenDifference)
        let tmp3 = Math.Simd.mulAddPairs(pair26, EvenUpper)
        let tmp2 = Math.Simd.mulAddPairs(pair26, EvenLower)

        let tmp10 = tmp0 + tmp3
        let tmp13 = tmp0 - tmp3
        let tmp11 = tmp1 + tmp2
        let tmp12 = tmp1 - tmp2

        let zero = Math.Simd.splat(0's32)
        let odd0 = Math.Simd.mulAddPairs(pair13, Odd0From13) + (LowBand ? zero : Math.Simd.mulAddPairs(pair57, Odd0From57))
        let odd1 = Math.Simd.mulAddPairs(pair13, Odd1From13) + (LowBand ? zero : Math.Simd.mulAddPairs(pair57, Odd1From57))
        let odd2 = Math.Simd.mulAddPairs(pair13, Odd2From13) + (LowBand ? zero : Math.Simd.mulAddPairs(pair57, Odd2From57))
        let odd3 = Math.Simd.mulAddPairs(pair13, Odd3From13) + (LowBand ? zero : Math.Simd.mulAddPairs(pair57, Odd3From57))

        result[0] = tmp10 + odd3
        result[7] = tmp10 - odd3
        result[1] = tmp11 + odd2
        result[6] = tmp11 - odd2
        result[2] = tmp12 + odd1
        result[5] = tmp12 - odd1
        result[3] = tmp13 + odd0
        result[4] = tmp13 - odd0
    }

    // Runs one pass over the eight lines held in `v`, into the two halves of the result.
    func transformLines(v: [*] Math.Simd.S16x8, low, high: [*] Math.Simd.S32x4)
    {
        transformHalf'false(pairLow(v[0], v[4]), pairLow(v[2], v[6]), pairLow(v[1], v[3]), pairLow(v[5], v[7]), low)
        transformHalf'false(pairHigh(v[0], v[4]), pairHigh(v[2], v[6]), pairHigh(v[1], v[3]), pairHigh(v[5], v[7]), high)
    }

    func(Upper: bool) transformLowBandHalf(v: [*] Math.Simd.S16x8, result: [*] Math.Simd.S32x4)
    {
        let zero = Math.Simd.splat(0's16)
        #static if Upper do
            transformHalf'true(pairHigh(v[0], zero), pairHigh(v[2], zero), pairHigh(v[1], v[3]), zero, result)
        else do
            transformHalf'true(pairLow(v[0], zero), pairLow(v[2], zero), pairLow(v[1], v[3]), zero, result)
    }
}

impl Decoder
{
    // Turns one dequantized block into eight-bit samples.
    //
    // This is the integer transform of the specification, run on all eight lines at once: the pass
    // over lines keeps two extra fraction bits, and the pass over columns removes them together
    // with the eight bits of the transform itself. The entropy stage already transposes the
    // coefficients, so the second pass needs the only transpose here.
    func idct(data: [*] s16, buf: [*] u8)
    {
        // A block that carries nothing but its average is the common case of a photograph, and the
        // whole transform then reduces to one repeated sample.
        const AcOnly = cast(Math.Simd.U16x8, [0_u16, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF])
        let coefficients = cast(const [*] u16, data)
        var ac = Math.Simd.load(coefficients) & AcOnly
        for i in 1 to 7
        {
            ac |= Math.Simd.load(coefficients + i * 8)
        }

        if Math.Simd.allTrue(ac == Math.Simd.splat(0_u16))
        {
            idctFlat(data[0], buf)
        }
        else
        {
            idctFull(data, buf)
        }
    }

    #[Swag.Inline]
    func idctFlat(dc: s16, buf: [*] u8)
    {
        // The pass over lines would have scaled the average before the pass over columns
        // removed that scale again, and it stores the product as a sixteen-bit value.
        let scaled = cast(s32, cast(s16, (cast(s32, dc) << Pass1Bits)))
        let flat   = Math.Simd.splat(clamp(descale(scaled, Pass1Bits + 3) + 128))
        for i in 4
        {
            Math.Simd.store(buf + i * 16, flat)
        }
    }

    func(LowBand: bool) idctFull(data: [*] s16, buf: [*] u8)
    {
        var v:    [8] Math.Simd.S16x8
        var low:  [8] Math.Simd.S32x4
        var high: [8] Math.Simd.S32x4

        for i in 8
        {
            v[i] = Math.Simd.load(cast(const [*] s16, (data + i * 8)))
        }

        transpose(v)
        transformLines(v, low, high)

        // The pass over lines keeps the two extra fraction bits the second pass will remove.
        let linePass  = ConstBits - Pass1Bits
        let lineRound = Math.Simd.splat(1_s32 << (linePass - 1))
        for i in 8
        {
            v[i] = Math.Simd.packSigned((low[i] + lineRound) >> linePass, (high[i] + lineRound) >> linePass)
        }

            transposeFirstFour(v)
            transformLowBandHalf'false(v, low)
            transformLowBandHalf'true(v, high)
        }
        else
        {
            for i in 8 do
                v[i] = Math.Simd.load(data + i * 8)
            transformLines(v, low, high)
            for i in 8 do
                v[i] = Math.Simd.packSigned((low[i] + lineRound) >> linePass, (high[i] + lineRound) >> linePass)

            transpose(v)
            transformLines(v, low, high)
        }

        // The pass over columns leaves eight-bit samples: the level shift of the format, then the
        // saturating narrowing that is exactly its clamp.
        let columnPass  = ConstBits + Pass1Bits + 3
        let columnRound = Math.Simd.splat(1_s32 << (columnPass - 1))
        let levelShift  = Math.Simd.splat(128_s32)
        for i in 8
        {
            let first  = pair * 2
            let second = first + 1
            let row0   = Math.Simd.packSigned((low[first] + columnRound) >> columnPass, (high[first] + columnRound) >> columnPass)
            let row1   = Math.Simd.packSigned((low[second] + columnRound) >> columnPass, (high[second] + columnRound) >> columnPass)
            Math.Simd.store(buf + pair * 16, Math.Simd.packUnsigned(row0 + levelShift, row1 + levelShift))
        }
    }

    mtd findEoi() fail
    {
        if not .progressiveFlag
        {
            .primeMarkerBits()
            let marker = try .processMarkers()
            if marker != .M_EOI
            {
                fail InvalidFormatError{"JPEG scan is not followed by the end-of-image marker"}
            }

            if .lastMarkerSynthetic
            {
                fail InvalidFormatError{"JPEG data ends before the end-of-image marker"}
            }
        }

        .totalBytesRead -= .inBufLeft
    }

    mtd convertGrayscale(output: [*] u8)
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d   = output
        var s   = .safeSampleBuf() + row * 8
        for _ in rangeTo(1, .maxMcusPerRow).reversed()
        {
            cast([*] u64, d)[0] = cast(const [*] u64, s)[0]

            s += 64
            d += 8
        }
    }

    mtd(Rgb: bool) convertH1V1(output: [*] u8)
    {
        let row         = .maxMcuSizeY - .mcuLinesLeft
        let planeBytes  = .compSampV[0] * 64
        let mcuBytes    = 3 * planeBytes
        var destination = output
        var luma        = .safeSampleBuf() + row * 8
        for .maxMcusPerRow
        {
            storeColor'Rgb(destination, luma, chromaBias8(luma + planeBytes, luma + 2 * planeBytes))

            destination += 24
            luma        += mcuBytes
        }
    }

    mtd(Rgb: bool) convertRgbH1V1(output: [*] u8)
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d   = output
        var s   = .safeSampleBuf() + row * 8
        for _ in rangeTo(1, .maxMcusPerRow).reversed()
        {
            const First = Rgb ? 0 : 128
            const Last  = 128 - First
            let firstGreen = joinLow8(s + First, s + 64)
            storeTriplets(d, firstGreen, Math.Simd.load(cast(const [*] u8, s + Last)))

            d += 24
            s += 64 * 3
        }
    }

    // Turns one row of a four-component unit into packed colour triplets.
    //
    // Four components are the inks of a printed page, in one of two spellings. The luminance and
    // chrominance form carries the three chromatic inks the way a photograph carries colour, and
    // its definition already complements them: converting the three back yields the complement of
    // each ink, and the black channel is stored plainly. The direct form spells the four inks
    // themselves, complemented when the file carries the Adobe marker, which is what that
    // producer writes and what the marker is read for here.
    mtd(Rgb: bool) convertCmykH1V1(output: [*] u8)
    {
        let row         = .maxMcuSizeY - .mcuLinesLeft
        let chromatic   = .adobeTransform == 2
        let inverse     = .hasAdobeMarker and not chromatic
        let colorMask   = Math.Simd.splat(inverse ? 0'u8 : 255'u8)
        let blackMask   = ~colorMask
        var destination = output
        var source      = .safeSampleBuf() + row * 8
        for .maxMcusPerRow
        {
            var firstGreen, last: Math.Simd.U8x16
            if chromatic
            {
                var cyan    = cast(s32, s[x])
                var magenta = cast(s32, s[64 + x])
                var yellow  = cast(s32, s[128 + x])
                var black   = cast(s32, s[192 + x])

                if chromatic
                {
                    let luma = cyan
                    let kb   = (magenta << 1) - 256
                    let kr   = (yellow << 1) - 256
                    cyan    = 255 - Math.clamp(luma + ((FixCrToR * kr + (1 << 15)) >> 16), 0, 255)
                    magenta = 255 - Math.clamp(luma + ((FixCrToG * kr + FixCbToG * kb + (1 << 15)) >> 16), 0, 255)
                    yellow  = 255 - Math.clamp(luma + ((FixCbToB * kb + (1 << 15)) >> 16), 0, 255)
                }
                else if inverse
                {
                    cyan    = 255 - cyan
                    magenta = 255 - magenta
                    yellow  = 255 - yellow
                    black   = 255 - black
                }

                d[3 * x + 0] = cast(u8, (255 - Math.min(255, yellow + black)))
                d[3 * x + 1] = cast(u8, (255 - Math.min(255, magenta + black)))
                d[3 * x + 2] = cast(u8, (255 - Math.min(255, cyan + black)))
            }

            // Each channel is the remaining light after subtracting the black ink.
            let black     = Math.Simd.load(source + 192) ^ blackMask
            let blackLow  = cast #bit(Math.Simd.U64x2, black)
            let blackPair = cast #bit(Math.Simd.U8x16, Math.Simd.interleaveLow(blackLow, blackLow))
            storeTriplets(destination, Math.Simd.subSaturating(firstGreen, blackPair), Math.Simd.subSaturating(last, black))
            destination += 24
            source      += 64 * 4
        }
    }

    mtd(Rgb: bool) convertH1V2(output0, output1: [*] u8)
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d0  = output0
        var d1  = output1

        var y: [*] u8
        if row < 8
        {
            y = .safeSampleBuf() + row * 8
        }
        else
        {
            y = .safeSampleBuf() + 64 * 1 + (row & 7) * 8
        }

        var c = .safeSampleBuf() + 64 * 2 + (row >> 1) * 8
        for _ in rangeTo(1, .maxMcusPerRow).reversed()
        {
            // One chroma row feeds both luma rows of the minimum coded unit.
            let bias = chromaBias8(c, c + 64)
            storeColor'Rgb(d0, y, bias)
            storeColor'Rgb(d1, y + 8, bias)

            d0 += 24
            d1 += 24
            y  += 64 * 4
            c  += 64 * 4
        }
    }

    mtd(Rgb: bool) convertH2V1(output: [*] u8)
    {
        let row              = .maxMcuSizeY - .mcuLinesLeft
        let blockRow         = row >> 3
        let sampleOffset     = (row & 7) * 8
        let chromaPlaneBytes = .compSampV[0] * 64
        let mcuBytes         = .maxBlocksPerMcu * 64
        let samples          = .safeSampleBuf()
        var destination      = output
        var luma             = samples + blockRow * 128 + sampleOffset
        var cb               = samples + 2 * chromaPlaneBytes + blockRow * 64 + sampleOffset

        for .maxMcusPerRow
        {
            // The matching chroma row covers two horizontally adjacent luma blocks.
            let bias = chromaBias8(cb, cb + chromaPlaneBytes)
            storeColor'Rgb(destination, luma, duplicateBias'false(bias))
            storeColor'Rgb(destination + 24, luma + 64, duplicateBias'true(bias))

            destination += 48
            luma        += mcuBytes
            cb          += mcuBytes
        }
    }

    mtd(Rgb: bool) convertH2V2(output0, output1: [*] u8)
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d0  = output0
        var d1  = output1

        var y: [*] u8
        if row < 8
        {
            y = .safeSampleBuf() + row * 8
        }
        else
        {
            y = .safeSampleBuf() + 64 * 2 + (row & 7) * 8
        }

        var c = .safeSampleBuf() + 64 * 4 + (row >> 1) * 8
        for _ in rangeTo(1, .maxMcusPerRow).reversed()
        {
            // The same eight chroma corrections feed sixteen pixels in both luma rows.
            let bias  = chromaBias8(c, c + 64)
            let left  = duplicateBias'false(bias)
            let right = duplicateBias'true(bias)
            storeColor'Rgb(d0, y, left)
            storeColor'Rgb(d1, y + 8, left)
            storeColor'Rgb(d0 + 24, y + 64, right)
            storeColor'Rgb(d1 + 24, y + 72, right)

            d0 += 48
            d1 += 48
            y  += 64 * 6
            c  += 64 * 6
        }
    }

    // For each group of eight output pixels, load the component block that covers it and
    // repeat its samples according to the horizontal ratio. The frame validated that every
    // ratio divides the MCU sampling grid, so a group never spans two component blocks.
    mtd(Rgb: bool) convertGeneric(output: [*] u8)
    {
        using Math.Simd

        let row = .maxMcuSizeY - .mcuLinesLeft
        let maxSamplingH = .maxMcuSizeX / 8
        let maxSamplingV = .maxMcuSizeY / 8
        const MaxSampling = 4
        var offsets:   [MaxSampling][3] s32
        var indices:   [MaxSampling][3] U8x16
        var blockBase: s32
        for component in 3
        {
            let samplingH       = .compSampH[component]
            let samplingV       = .compSampV[component]
            let horizontalRatio = maxSamplingH / samplingH
            let componentY      = row * samplingV / maxSamplingV
            let rowOffset       = (blockBase + (componentY >> 3) * samplingH) * 64 + (componentY & 7) * 8
            for group in maxSamplingH
            {
                let x = group * 8
                offsets[group][component] = rowOffset + ((x / horizontalRatio) >> 3) * 64
                var lanes: [16] u8
                for lane in 8 do
                    lanes[lane] = cast(u8, (((x + lane) / horizontalRatio) & 7))
                indices[group][component] = cast #bit(U8x16, lanes)
            }

            blockBase += samplingH * samplingV
        }

        var destination = output
        var mcu         = cast(const [*] u8, .safeSampleBuf())
        for .maxMcusPerRow
        {
            for group in maxSamplingH
            {
                let y  = shuffle(load(mcu + offsets[group][0]), indices[group][0])
                let cb = shuffle(load(mcu + offsets[group][1]), indices[group][1])
                let cr = shuffle(load(mcu + offsets[group][2]), indices[group][2])
                storeColorSamples'Rgb(destination, y, chromaBias8Samples(cb, cr))
                destination += 24
            }

            mcu += blockBase * 64
        }
    }
}
