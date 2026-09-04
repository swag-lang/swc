//! Format: Joint Photographic Experts Group (JPEG) decoder component.
//! Supported: Baseline and progressive Huffman-coded grayscale, YCbCr, directly sampled RGB, and CMYK or YCCK images.
//! Not supported: Arithmetic coding, lossless JPEG, and unsupported chroma sampling layouts.
//! Role: This file owns inverse DCT and sample reconstruction.
//
#global namespace Jpg

using Swag, Core, Core.Errors

// Byte permutations that weave a blue/green pair and a red vector into eight BGR triplets.
//
// A table byte of 0x80 clears the destination byte, so the contribution of each source vector is
// combined with a bitwise or.

private
{
    const TripletLowBG  = cast(Math.Simd.U8x16) [0'u8, 8, 0x80, 1, 9, 0x80, 2, 10, 0x80, 3, 11, 0x80, 4, 12, 0x80, 5]
    const TripletLowR   = cast(Math.Simd.U8x16) [0x80'u8, 0x80, 0, 0x80, 0x80, 1, 0x80, 0x80, 2, 0x80, 0x80, 3, 0x80, 0x80, 4, 0x80]
    const TripletHighBG = cast(Math.Simd.U8x16) [13'u8, 0x80, 6, 14, 0x80, 7, 15, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80]
    const TripletHighR  = cast(Math.Simd.U8x16) [0x80'u8, 5, 0x80, 0x80, 6, 0x80, 0x80, 7, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80]
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
        let samples = cast #bit(Math.Simd.S32x4) Math.Simd.widenLow(Math.Simd.widenLow(Math.Simd.load(source)))
        return (samples << 1) - Math.Simd.splat(256's32)
    }

    // Centers the four low or four high chroma samples of an already widened group of eight.
    func centeredChromaLow(samples: Math.Simd.U16x8)->Math.Simd.S32x4  => (cast #bit(Math.Simd.S32x4) Math.Simd.widenLow(samples) << 1) - Math.Simd.splat(256's32)
    func centeredChromaHigh(samples: Math.Simd.U16x8)->Math.Simd.S32x4 => (cast #bit(Math.Simd.S32x4) Math.Simd.widenHigh(samples) << 1) - Math.Simd.splat(256's32)

    // The three corrections, in the fixed point the decoded value is defined in.
    func redBias(kr: Math.Simd.S32x4)->Math.Simd.S32x4       => (Math.Simd.splat(FixCrToR) * kr + Math.Simd.splat(1's32 << 15)) >> 16
    func blueBias(kb: Math.Simd.S32x4)->Math.Simd.S32x4      => (Math.Simd.splat(FixCbToB) * kb + Math.Simd.splat(1's32 << 15)) >> 16
    func greenBias(kr, kb: Math.Simd.S32x4)->Math.Simd.S32x4 => (Math.Simd.splat(FixCrToG) * kr + Math.Simd.splat(FixCbToG) * kb + Math.Simd.splat(1's32 << 15)) >> 16

    // Narrows four corrections to eight lanes, each repeated over the pixel pair it covers.
    func duplicatedLanes(value: Math.Simd.S32x4)->Math.Simd.S16x8
    {
        let packed = cast #bit(Math.Simd.U16x8) Math.Simd.packSigned(value, value)
        return cast #bit(Math.Simd.S16x8) Math.Simd.interleaveLow(packed, packed)
    }

    // Joins the low eight bytes of two planes into one vector.
    func joinLow8(low, high: const [*] u8)->Math.Simd.U8x16
    {
        let joined = Math.Simd.interleaveLow(cast #bit(Math.Simd.U64x2) Math.Simd.load(low), cast #bit(Math.Simd.U64x2) Math.Simd.load(high))
        return cast #bit(Math.Simd.U8x16) joined
    }

    // Corrections of four chroma samples, each covering two horizontally adjacent pixels.
    func chromaBias4(cb, cr: const [*] u8)->ChromaBias
    {
        let kb = centeredChroma(cb)
        let kr = centeredChroma(cr)

        var result: retval
        result.rc = duplicatedLanes(redBias(kr))
        result.gc = duplicatedLanes(greenBias(kr, kb))
        result.bc = duplicatedLanes(blueBias(kb))
        return result
    }

    // Corrections of eight chroma samples, one per pixel.
    func chromaBias8(cb, cr: const [*] u8)->ChromaBias
    {
        let blues = Math.Simd.widenLow(Math.Simd.load(cb))
        let reds  = Math.Simd.widenLow(Math.Simd.load(cr))

        let kbLow  = centeredChromaLow(blues)
        let kbHigh = centeredChromaHigh(blues)
        let krLow  = centeredChromaLow(reds)
        let krHigh = centeredChromaHigh(reds)

        var result: retval
        result.rc = Math.Simd.packSigned(redBias(krLow), redBias(krHigh))
        result.gc = Math.Simd.packSigned(greenBias(krLow, kbLow), greenBias(krHigh, kbHigh))
        result.bc = Math.Simd.packSigned(blueBias(kbLow), blueBias(kbHigh))
        return result
    }

    // Writes the twenty-four bytes of eight interleaved BGR pixels.
    func storeTriplets(destination: [*] u8, blueGreen, red: Math.Simd.U8x16)
    {
        Math.Simd.store(destination, Math.Simd.shuffle(blueGreen, TripletLowBG) | Math.Simd.shuffle(red, TripletLowR))
        Math.Simd.storeLow8(destination + 16, Math.Simd.shuffle(blueGreen, TripletHighBG) | Math.Simd.shuffle(red, TripletHighR))
    }

    // Converts eight luma samples and their chroma corrections into eight BGR pixels.
    //
    // The saturating narrowing is the clamp the conversion needs: a corrected sample outside the
    // byte range lands on its nearest end.
    func storeBgr(destination: [*] u8, luma: const [*] u8, bias: ChromaBias)
    {
        let y         = cast #bit(Math.Simd.S16x8) Math.Simd.widenLow(Math.Simd.load(luma))
        let blueGreen = Math.Simd.packUnsigned(y + bias.bc, y + bias.gc)
        let red       = Math.Simd.packUnsigned(y + bias.rc, y + bias.rc)
        storeTriplets(destination, blueGreen, red)
    }
}

// The transform coefficients, paired the way a multiply-add of adjacent lanes consumes them.
//
// Each pair belongs to two input lines: the even part reads lines 0 and 4, then 2 and 6, and the
// odd part reads lines 1 and 3, then 5 and 7. Every constant below is the sum the scalar form of
// the transform reaches for that line, so both forms compute the same integers.

private
{
    const EvenSum        = cast(Math.Simd.S16x8) [8192's16, 8192, 8192, 8192, 8192, 8192, 8192, 8192]
    const EvenDifference = cast(Math.Simd.S16x8) [8192's16, -8192, 8192, -8192, 8192, -8192, 8192, -8192]
    const EvenUpper      = cast(Math.Simd.S16x8) [10703's16, 4433, 10703, 4433, 10703, 4433, 10703, 4433]
    const EvenLower      = cast(Math.Simd.S16x8) [4433's16, -10704, 4433, -10704, 4433, -10704, 4433, -10704]

    const Odd0From13 = cast(Math.Simd.S16x8) [2260's16, -6436, 2260, -6436, 2260, -6436, 2260, -6436]
    const Odd0From57 = cast(Math.Simd.S16x8) [9633's16, -11363, 9633, -11363, 9633, -11363, 9633, -11363]
    const Odd1From13 = cast(Math.Simd.S16x8) [6437's16, -11362, 6437, -11362, 6437, -11362, 6437, -11362]
    const Odd1From57 = cast(Math.Simd.S16x8) [2261's16, 9633, 2261, 9633, 2261, 9633, 2261, 9633]
    const Odd2From13 = cast(Math.Simd.S16x8) [9633's16, -2259, 9633, -2259, 9633, -2259, 9633, -2259]
    const Odd2From57 = cast(Math.Simd.S16x8) [-11362's16, -6436, -11362, -6436, -11362, -6436, -11362, -6436]
    const Odd3From13 = cast(Math.Simd.S16x8) [11363's16, 9633, 11363, 9633, 11363, 9633, 11363, 9633]
    const Odd3From57 = cast(Math.Simd.S16x8) [6437's16, 2260, 6437, 2260, 6437, 2260, 6437, 2260]
}

#[Swag.Inline]

private
{
    // Pairs the lanes of two vectors, low halves and high halves.
    func pairLow(x, y: Math.Simd.S16x8)->Math.Simd.S16x8  => cast #bit(Math.Simd.S16x8) Math.Simd.interleaveLow(cast #bit(Math.Simd.U16x8) x, cast #bit(Math.Simd.U16x8) y)
    func pairHigh(x, y: Math.Simd.S16x8)->Math.Simd.S16x8 => cast #bit(Math.Simd.S16x8) Math.Simd.interleaveHigh(cast #bit(Math.Simd.U16x8) x, cast #bit(Math.Simd.U16x8) y)

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

        let b0 = Math.Simd.interleaveLow(cast #bit(Math.Simd.U32x4) a0, cast #bit(Math.Simd.U32x4) a2)
        let b1 = Math.Simd.interleaveHigh(cast #bit(Math.Simd.U32x4) a0, cast #bit(Math.Simd.U32x4) a2)
        let b2 = Math.Simd.interleaveLow(cast #bit(Math.Simd.U32x4) a1, cast #bit(Math.Simd.U32x4) a3)
        let b3 = Math.Simd.interleaveHigh(cast #bit(Math.Simd.U32x4) a1, cast #bit(Math.Simd.U32x4) a3)
        let b4 = Math.Simd.interleaveLow(cast #bit(Math.Simd.U32x4) a4, cast #bit(Math.Simd.U32x4) a6)
        let b5 = Math.Simd.interleaveHigh(cast #bit(Math.Simd.U32x4) a4, cast #bit(Math.Simd.U32x4) a6)
        let b6 = Math.Simd.interleaveLow(cast #bit(Math.Simd.U32x4) a5, cast #bit(Math.Simd.U32x4) a7)
        let b7 = Math.Simd.interleaveHigh(cast #bit(Math.Simd.U32x4) a5, cast #bit(Math.Simd.U32x4) a7)

        v[0] = cast #bit(Math.Simd.S16x8) Math.Simd.interleaveLow(cast #bit(Math.Simd.U64x2) b0, cast #bit(Math.Simd.U64x2) b4)
        v[1] = cast #bit(Math.Simd.S16x8) Math.Simd.interleaveHigh(cast #bit(Math.Simd.U64x2) b0, cast #bit(Math.Simd.U64x2) b4)
        v[2] = cast #bit(Math.Simd.S16x8) Math.Simd.interleaveLow(cast #bit(Math.Simd.U64x2) b1, cast #bit(Math.Simd.U64x2) b5)
        v[3] = cast #bit(Math.Simd.S16x8) Math.Simd.interleaveHigh(cast #bit(Math.Simd.U64x2) b1, cast #bit(Math.Simd.U64x2) b5)
        v[4] = cast #bit(Math.Simd.S16x8) Math.Simd.interleaveLow(cast #bit(Math.Simd.U64x2) b2, cast #bit(Math.Simd.U64x2) b6)
        v[5] = cast #bit(Math.Simd.S16x8) Math.Simd.interleaveHigh(cast #bit(Math.Simd.U64x2) b2, cast #bit(Math.Simd.U64x2) b6)
        v[6] = cast #bit(Math.Simd.S16x8) Math.Simd.interleaveLow(cast #bit(Math.Simd.U64x2) b3, cast #bit(Math.Simd.U64x2) b7)
        v[7] = cast #bit(Math.Simd.S16x8) Math.Simd.interleaveHigh(cast #bit(Math.Simd.U64x2) b3, cast #bit(Math.Simd.U64x2) b7)
    }

    // Transforms four lines, and leaves their eight results unscaled: the caller owns the rounding
    // and the width, which is what separates the two passes.
    func transformHalf(pair04, pair26, pair13, pair57: Math.Simd.S16x8, result: [*] Math.Simd.S32x4)
    {
        let tmp0 = Math.Simd.mulAddPairs(pair04, EvenSum)
        let tmp1 = Math.Simd.mulAddPairs(pair04, EvenDifference)
        let tmp3 = Math.Simd.mulAddPairs(pair26, EvenUpper)
        let tmp2 = Math.Simd.mulAddPairs(pair26, EvenLower)

        let tmp10 = tmp0 + tmp3
        let tmp13 = tmp0 - tmp3
        let tmp11 = tmp1 + tmp2
        let tmp12 = tmp1 - tmp2

        let odd0 = Math.Simd.mulAddPairs(pair13, Odd0From13) + Math.Simd.mulAddPairs(pair57, Odd0From57)
        let odd1 = Math.Simd.mulAddPairs(pair13, Odd1From13) + Math.Simd.mulAddPairs(pair57, Odd1From57)
        let odd2 = Math.Simd.mulAddPairs(pair13, Odd2From13) + Math.Simd.mulAddPairs(pair57, Odd2From57)
        let odd3 = Math.Simd.mulAddPairs(pair13, Odd3From13) + Math.Simd.mulAddPairs(pair57, Odd3From57)

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
        transformHalf(pairLow(v[0], v[4]), pairLow(v[2], v[6]), pairLow(v[1], v[3]), pairLow(v[5], v[7]), low)
        transformHalf(pairHigh(v[0], v[4]), pairHigh(v[2], v[6]), pairHigh(v[1], v[3]), pairHigh(v[5], v[7]), high)
    }
}

impl Decoder
{
    // Turns one dequantized block into eight-bit samples.
    //
    // This is the integer transform of the specification, run on all eight lines at once: the pass
    // over lines keeps two extra fraction bits, and the pass over columns removes them together
    // with the eight bits of the transform itself. Since a pass combines the values of one line,
    // the block is transposed between the two so that every line lives in its own lane.
    func idct(data: [*] s16, buf: [*] u8)
    {
        // A block that carries nothing but its average is the common case of a photograph, and the
        // whole transform then reduces to one repeated sample.
        let words = cast(const [*] u64) data
        var mixed = words[0] & 0xFFFFFFFF_FFFF0000
        for i in 1 to 15 do
            mixed |= words[i]

        if mixed == 0
        {
            // The pass over lines would have scaled the average before the pass over columns
            // removed that scale again, and it stores the product as a sixteen-bit value.
            let scaled = cast(s32) cast(s16) (cast(s32) data[0] << Pass1Bits)
            let flat   = Math.Simd.splat(clamp(descale(scaled, Pass1Bits + 3) + 128))
            for i in 4 do
                Math.Simd.store(buf + i * 16, flat)
            return
        }

        var v:    [8] Math.Simd.S16x8
        var low:  [8] Math.Simd.S32x4
        var high: [8] Math.Simd.S32x4

        for i in 8 do
            v[i] = Math.Simd.load(cast(const [*] s16) (data + i * 8))

        transpose(v)
        transformLines(v, low, high)

        // The pass over lines keeps the two extra fraction bits the second pass will remove.
        let linePass  = ConstBits - Pass1Bits
        let lineRound = Math.Simd.splat(1's32 << (linePass - 1))
        for i in 8 do
            v[i] = Math.Simd.packSigned((low[i] + lineRound) >> linePass, (high[i] + lineRound) >> linePass)

        transpose(v)
        transformLines(v, low, high)

        // The pass over columns leaves eight-bit samples: the level shift of the format, then the
        // saturating narrowing that is exactly its clamp.
        let columnPass  = ConstBits + Pass1Bits + 3
        let columnRound = Math.Simd.splat(1's32 << (columnPass - 1))
        let levelShift  = Math.Simd.splat(128's32)
        for i in 8
        {
            let samples = Math.Simd.packSigned(((low[i] + columnRound) >> columnPass) + levelShift, ((high[i] + columnRound) >> columnPass) + levelShift)
            Math.Simd.storeLow8(buf + i * 8, Math.Simd.packUnsigned(samples, samples))
        }
    }

    mtd transformRow()
    {
        var psrcPtr = .blockSeg[0]!
        var pdstPtr = .pSampleBuf!

        for .maxBlocksPerRow
        {
            idct(psrcPtr, pdstPtr)

            // Baseline Huffman decoding skips zero coefficients, so leave each disposable block
            // clear for the next MCU row instead of tracking and clearing stale coefficients.
            Memory.clear(psrcPtr, 64'u64 * #sizeof(s16))
            psrcPtr += 64
            pdstPtr += 64
        }
    }

    mtd findEoi() fail
    {
        if !.progressiveFlag
        {
            .bitsLeft = 16
            .getBits1(16)
            .getBits1(16)
            .processMarkers()
        }

        .totalBytesRead -= .inBufLeft
    }

    mtd convertGrayscale()
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d   = .scanLine0.buffer!
        var s   = .safeSampleBuf() + row * 8
        for i in rangeTo(1, .maxMcusPerRow).reversed()
        {
            (cast([*] u64) d)[0] = (cast(const [*] u64) s)[0]

            s += 64
            d += 8
        }
    }

    mtd convertH1V1()
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d   = .scanLine0.buffer!
        var s   = .safeSampleBuf() + row * 8
        for i in rangeTo(1, .maxMcusPerRow).reversed()
        {
            storeBgr(d, s, chromaBias8(s + 64, s + 128))

            d += 24
            s += 64 * 3
        }
    }

    mtd convertRgbH1V1()
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d   = .scanLine0.buffer!
        var s   = .safeSampleBuf() + row * 8
        for i in rangeTo(1, .maxMcusPerRow).reversed()
        {
            // The three components already are the blue, green and red planes of the pixels, so
            // only the interleave is left to do.
            let blueGreen = joinLow8(s + 128, s + 64)
            storeTriplets(d, blueGreen, Math.Simd.load(cast(const [*] u8) s))

            d += 24
            s += 64 * 3
        }
    }

    // Turns one row of a four-component unit into blue-green-red triplets.
    //
    // Four components are the inks of a printed page, in one of two spellings. The luminance and
    // chrominance form carries the three chromatic inks the way a photograph carries colour, and
    // its definition already complements them: converting the three back yields the complement of
    // each ink, and the black channel is stored plainly. The direct form spells the four inks
    // themselves, complemented when the file carries the Adobe marker, which is what that
    // producer writes and what the marker is read for here.
    //
    // The scalar form is deliberate: this layout is unsubsampled, so the vector helpers of the
    // luma paths have no group of pixels to share one chroma correction over.
    mtd convertCmykH1V1()
    {
        let row       = .maxMcuSizeY - .mcuLinesLeft
        let chromatic = .adobeTransform == 2
        let inverse   = .hasAdobeMarker and !chromatic
        var d         = .scanLine0.buffer!
        var s         = .safeSampleBuf() + row * 8
        for i in rangeTo(1, .maxMcusPerRow).reversed()
        {
            for x in 8
            {
                var cyan    = cast(s32) s[x]
                var magenta = cast(s32) s[64 + x]
                var yellow  = cast(s32) s[128 + x]
                var black   = cast(s32) s[192 + x]

                if chromatic
                {
                    let luma = cyan
                    let kb   = (magenta << 1) - 256
                    let kr   = (yellow << 1) - 256
                    cyan    = 255 - Math.clamp(luma + ((FixCrToR * kr + (1 << 15)) >> 16), 0, 255)
                    magenta = 255 - Math.clamp(luma + ((FixCrToG * kr + FixCbToG * kb + (1 << 15)) >> 16), 0, 255)
                    yellow  = 255 - Math.clamp(luma + ((FixCbToB * kb + (1 << 15)) >> 16), 0, 255)
                }
                elif inverse
                {
                    cyan    = 255 - cyan
                    magenta = 255 - magenta
                    yellow  = 255 - yellow
                    black   = 255 - black
                }

                d[3 * x + 0] = cast(u8) (255 - Math.min(255, yellow + black))
                d[3 * x + 1] = cast(u8) (255 - Math.min(255, magenta + black))
                d[3 * x + 2] = cast(u8) (255 - Math.min(255, cyan + black))
            }

            d += 24
            s += 64 * 4
        }
    }

    mtd convertH1V2()
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d0  = .scanLine0.buffer!
        var d1  = .scanLine1.buffer!

        var y: [*] u8
        if row < 8 do
            y = .safeSampleBuf() + row * 8
        else do
            y = .safeSampleBuf() + 64 * 1 + (row & 7) * 8

        var c = .safeSampleBuf() + 64 * 2 + (row >> 1) * 8
        for i in rangeTo(1, .maxMcusPerRow).reversed()
        {
            // One chroma row feeds both luma rows of the minimum coded unit.
            let bias = chromaBias8(c, c + 64)
            storeBgr(d0, y, bias)
            storeBgr(d1, y + 8, bias)

            d0 += 24
            d1 += 24
            y  += 64 * 4
            c  += 64 * 4
        }
    }

    mtd convertH2V1()
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d0  = .scanLine0.buffer!
        var y   = .safeSampleBuf() + row * 8
        var c   = .safeSampleBuf() + 2 * 64 + row * 8

        for i in rangeTo(1, .maxMcusPerRow).reversed()
        {
            // The two luma blocks of the unit are consecutive, and four chroma samples cover each.
            for l in 2
            {
                storeBgr(d0, y, chromaBias4(c, c + 64))

                d0 += 24
                c  += 4
                y  += 64
            }

            y += 64 * 4 - 64 * 2
            c += 64 * 4 - 8
        }
    }

    mtd convertH2V2()
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d0  = .scanLine0.buffer!
        var d1  = .scanLine1.buffer!

        var y: [*] u8
        if row < 8 do
            y = .safeSampleBuf() + row * 8
        else do
            y = .safeSampleBuf() + 64 * 2 + (row & 7) * 8

        var c = .safeSampleBuf() + 64 * 4 + (row >> 1) * 8
        for i in rangeTo(1, .maxMcusPerRow).reversed()
        {
            // Four chroma samples cover eight pixels of two luma rows at once.
            for l in 2
            {
                let bias = chromaBias4(c, c + 64)
                storeBgr(d0, y, bias)
                storeBgr(d1, y + 8, bias)

                d0 += 24
                d1 += 24
                c  += 4
                y  += 64
            }

            y += 64 * 6 - 64 * 2
            c += 64 * 6 - 8
        }
    }

    #[Swag.Inline]
    mtd componentSample(mcu: const [*] u8, component, blockBase, pixelX, pixelY, maxSamplingH, maxSamplingV: s32)->u8
    {
        let componentX = pixelX * .compSampH[component] / maxSamplingH
        let componentY = pixelY * .compSampV[component] / maxSamplingV
        let block      = blockBase + (componentY >> 3) * .compSampH[component] + (componentX >> 3)
        return mcu[block * 64 + (componentY & 7) * 8 + (componentX & 7)]
    }

    // Converts any legal three-component sampling layout not covered by the SIMD specializations.
    // The entropy stream keeps every block in MCU component order; these ratios map one output
    // sample back to the exact component block and sample that covers it.
    mtd convertGeneric()
    {
        let row          = .maxMcuSizeY - .mcuLinesLeft
        let maxSamplingH = .maxMcuSizeX / 8
        let maxSamplingV = .maxMcuSizeY / 8
        let cbBase       = .compSampH[0] * .compSampV[0]
        let crBase       = cbBase + .compSampH[1] * .compSampV[1]
        var destination  = .scanLine0.buffer!
        var mcu          = cast(const [*] u8) .safeSampleBuf()
        for .maxMcusPerRow
        {
            for x in .maxMcuSizeX
            {
                let y  = cast(s32) .componentSample(mcu, 0, 0, x, row, maxSamplingH, maxSamplingV)
                let cb = cast(s32) .componentSample(mcu, 1, cbBase, x, row, maxSamplingH, maxSamplingV) * 2 - 256
                let cr = cast(s32) .componentSample(mcu, 2, crBase, x, row, maxSamplingH, maxSamplingV) * 2 - 256
                destination[0] = clamp(y + ((FixCbToB * cb + (1 << 15)) >> 16))
                destination[1] = clamp(y + ((FixCrToG * cr + FixCbToG * cb + (1 << 15)) >> 16))
                destination[2] = clamp(y + ((FixCrToR * cr + (1 << 15)) >> 16))
                destination    += 3
            }

            mcu += .maxBlocksPerMcu * 64
        }
    }
}
