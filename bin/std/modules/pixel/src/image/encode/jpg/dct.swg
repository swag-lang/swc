//! Format: Joint Photographic Experts Group (JPEG) encoder component.
//! Supported: Baseline Huffman-coded lossy output from 8-bit RGB/BGR images with configurable quality.
//! Not supported: Progressive, arithmetic, lossless, CMYK/YCCK, and alpha output.
//! Role: This file owns forward DCT and quantization.
//
#global namespace Jpg

using Core

impl Encoder
{
    // Lifts one colour channel of four consecutive pixels into four 32-bit lanes.
    #[Swag.Inline]
    func channelOf(samples, lanes: Math.Simd.U8x16)->Math.Simd.S32x4 => cast #bit(Math.Simd.S32x4, Math.Simd.shuffle(samples, lanes))

    // Rounds the fixed-point dot product to the nearest sample. Chroma ties round down so
    // the top half-step (127.5) fits in the signed range of the centered sample.
    #[Swag.Inline]
    func(T) componentOf(red, green, blue: T, coeffRed, coeffGreen, coeffBlue, rounding: s32)->T
    {
        let total = coeffRed * red + coeffGreen * green + coeffBlue * blue
        return (total + rounding) >> 16
    }

    // Reads the eight-by-eight block at the given position as the three components of the format.
    //
    // Each component is a dot product of the pixel, so a row is converted eight pixels at a time
    // and the luma one carries the level shift of the format.
    mtd loadFromRGB(source: const [*] u8, columns, rows: u32)
    {
        using Math.Simd

        #[Swag.Inline]
        func(A: s32, B: s32, Rounding: s32) pairComponent(first, second: S16x8)->S16x8
        {
            const Weights = cast(S16x8, [cast(s16, A), cast(s16, B), cast(s16, A), cast(s16, B),
                                         cast(s16, A), cast(s16, B), cast(s16, A), cast(s16, B)])
            let a    = cast #bit(U16x8, first)
            let b    = cast #bit(U16x8, second)
            let low  = mulAddPairs(cast #bit(S16x8, interleaveLow(a, b)), Weights)
            let high = mulAddPairs(cast #bit(S16x8, interleaveHigh(a, b)), Weights)
            return packSigned((low + Rounding) >> 16, (high + Rounding) >> 16)
        }

        var edge: [32] u8
        let padded = cast([*] u8, edge)
        let luma   = cast([*] s16, &.duY[0])
        let blue   = cast([*] s16, &.duCb[0])
        let red    = cast([*] s16, &.duCr[0])

        let redLanes   = .redLanes
        let greenLanes = .greenLanes
        let blueLanes  = .blueLanes
        var pos        = 0

        for line in 8
        {
            // Rows are stored bottom up. Repeat the last source row or column at a partial block.
            var row = source - Math.min(line, rows - 1) * .stride
            if columns < 8
            {
                let bytes = columns * .pixelSize
                let last  = bytes - .pixelSize
                Memory.copy(padded, row, bytes)
                for column in columns until 8
                {
                    Memory.copy(padded + column * .pixelSize, padded + last, .pixelSize)
                }

                row = padded
            }

            let low         = load(row)
            let high        = load(row + .rightOffset)
            let redPixels   = packSigned(channelOf(low, redLanes), channelOf(high, .redLanesHigh))
            let greenPixels = packSigned(channelOf(low, greenLanes), channelOf(high, .greenLanesHigh))
            let bluePixels  = packSigned(channelOf(low, blueLanes), channelOf(high, .blueLanesHigh))

            // The luma weights sum to 65536 and each chroma row sums to zero.
            // Channel differences keep both weights of each dot product in signed 16-bit lanes.
            let redGreen  = redPixels - greenPixels
            let blueGreen = bluePixels - greenPixels
            let redBlue   = redGreen - blueGreen
            let y         = pairComponent!{CoeffYR, CoeffYB, 32_768}(redGreen, blueGreen) + greenPixels - 128_s16
            let cb        = pairComponent!{CoeffCbR, -CoeffCbG, 32_767}(redBlue, blueGreen)
            let cr        = pairComponent!{-CoeffCrG, -CoeffCrB, 32_767}(redGreen, redBlue)
            store(luma + pos, y)
            store(blue + pos, cb)
            store(red + pos, cr)

            pos += 8
        }
    }

    // Applies one AAN forward transform to each of the vector's four lanes.
    func transformFourLines(values: [*] Math.Simd.F32x4)
    {
        let tmp0 = values[0] + values[7]
        let tmp7 = values[0] - values[7]
        let tmp1 = values[1] + values[6]
        let tmp6 = values[1] - values[6]
        let tmp2 = values[2] + values[5]
        let tmp5 = values[2] - values[5]
        let tmp3 = values[3] + values[4]
        let tmp4 = values[3] - values[4]

        let tmp10 = tmp0 + tmp3
        let tmp13 = tmp0 - tmp3
        let tmp11 = tmp1 + tmp2
        let tmp12 = tmp1 - tmp2
        values[0] = tmp10 + tmp11
        values[4] = tmp10 - tmp11

        let z1 = (tmp12 + tmp13) * 0.707106781_f32
        values[2] = tmp13 + z1
        values[6] = tmp13 - z1

        let odd10 = tmp4 + tmp5
        let odd11 = tmp5 + tmp6
        let odd12 = tmp6 + tmp7
        let z5    = (odd10 - odd12) * 0.382683433_f32

        // Match the scalar transform's separately rounded z2 product.
        let z2 = Math.mulAdd(odd10, Math.Simd.splat(0.541196100_f32), z5)
        let z4 = odd12 * 1.306562965_f32 + z5
        let z3 = odd11 * 0.707106781_f32

        let z11 = tmp7 + z3
        let z13 = tmp7 - z3
        values[5] = z13 + z2
        values[3] = z13 - z2
        values[1] = z11 + z4
        values[7] = z11 - z4
    }

    #[Swag.Inline]
    func transposeFour(values, destination: [*] Math.Simd.F32x4)
    {
        let row0  = cast #bit(Math.Simd.U32x4, values[0])
        let row1  = cast #bit(Math.Simd.U32x4, values[1])
        let row2  = cast #bit(Math.Simd.U32x4, values[2])
        let row3  = cast #bit(Math.Simd.U32x4, values[3])
        let low0  = cast #bit(Math.Simd.U64x2, Math.Simd.interleaveLow(row0, row1))
        let high0 = cast #bit(Math.Simd.U64x2, Math.Simd.interleaveHigh(row0, row1))
        let low1  = cast #bit(Math.Simd.U64x2, Math.Simd.interleaveLow(row2, row3))
        let high1 = cast #bit(Math.Simd.U64x2, Math.Simd.interleaveHigh(row2, row3))
        destination[0] = cast #bit(Math.Simd.F32x4, Math.Simd.interleaveLow(low0, low1))
        destination[1] = cast #bit(Math.Simd.F32x4, Math.Simd.interleaveHigh(low0, low1))
        destination[2] = cast #bit(Math.Simd.F32x4, Math.Simd.interleaveLow(high0, high1))
        destination[3] = cast #bit(Math.Simd.F32x4, Math.Simd.interleaveHigh(high0, high1))
    }

    // Interleave each biased word with the high half of 2^23, then subtract 2^23 + 32768.
    #[Swag.Inline]
    func(High: bool) floatSamples(biased: Math.Simd.U16x8)->Math.Simd.F32x4
    {
        using Math.Simd

        let exponent = splat(0x4B00_u16)
        #static if High
        {
            return cast #bit(F32x4, interleaveHigh(biased, exponent)) - 8421376.0_f32
        }
        else
        {
            return cast #bit(F32x4, interleaveLow(biased, exponent)) - 8421376.0_f32
        }
    }

    #[Swag.Inline]
    func(High: bool) finishHorizontal(dc, even4, evenBase, evenMix, odd10, odd11, odd12, odd7: Math.Simd.U16x8, left, right: [*] Math.Simd.F32x4)
    {
        using Math.Simd

        let base = floatSamples!{High}(evenBase)
        let z1   = floatSamples!{High}(evenMix) * 0.707106781_f32
        let o10  = floatSamples!{High}(odd10)
        let o11  = floatSamples!{High}(odd11)
        let o12  = floatSamples!{High}(odd12)
        let tmp7 = floatSamples!{High}(odd7)
        let z5   = (o10 - o12) * 0.382683433_f32
        let z2   = Math.mulAdd(o10, splat(0.541196100_f32), z5)
        let z4   = o12 * 1.306562965_f32 + z5
        let z3   = o11 * 0.707106781_f32
        let z11  = tmp7 + z3
        let z13  = tmp7 - z3

        var values: [8] F32x4 = [
            floatSamples!{High}(dc), z11 + z4, base + z1, z13 - z2,
            floatSamples!{High}(even4), z13 + z2, base - z1, z11 - z4]
        transposeFour(values, left)
        transposeFour(cast([*] F32x4, values) + 4, right)
    }

    // The integer part of the horizontal pass fits in signed words for centered byte samples.
    // Only the terms that involve an AAN factor need floating point here.
    func transformHorizontal(data: const [*] s16, left, right: [*] Math.Simd.F32x4)
    {
        using Math.Simd

        let input = cast(const [*] U16x8, data)
        var columns: [8] U16x8 = [input[0], input[1], input[2], input[3], input[4], input[5], input[6], input[7]]
        transpose8x8(&columns)
        let x0 = cast #bit(S16x8, columns[0])
        let x1 = cast #bit(S16x8, columns[1])
        let x2 = cast #bit(S16x8, columns[2])
        let x3 = cast #bit(S16x8, columns[3])
        let x4 = cast #bit(S16x8, columns[4])
        let x5 = cast #bit(S16x8, columns[5])
        let x6 = cast #bit(S16x8, columns[6])
        let x7 = cast #bit(S16x8, columns[7])

        let tmp0  = x0 + x7
        let tmp7  = x0 - x7
        let tmp1  = x1 + x6
        let tmp6  = x1 - x6
        let tmp2  = x2 + x5
        let tmp5  = x2 - x5
        let tmp3  = x3 + x4
        let tmp4  = x3 - x4
        let tmp10 = tmp0 + tmp3
        let tmp13 = tmp0 - tmp3
        let tmp11 = tmp1 + tmp2
        let tmp12 = tmp1 - tmp2

        let dc        = tmp10 + tmp11
        let even4     = tmp10 - tmp11
        let evenMix   = tmp12 + tmp13
        let odd10     = tmp4 + tmp5
        let odd11     = tmp5 + tmp6
        let odd12     = tmp6 + tmp7
        let biasedDc  = cast #bit(U16x8, dc) ^ 0x8000_u16
        let biased4   = cast #bit(U16x8, even4) ^ 0x8000_u16
        let biased13  = cast #bit(U16x8, tmp13) ^ 0x8000_u16
        let biasedMix = cast #bit(U16x8, evenMix) ^ 0x8000_u16
        let biased10  = cast #bit(U16x8, odd10) ^ 0x8000_u16
        let biased11  = cast #bit(U16x8, odd11) ^ 0x8000_u16
        let biased12  = cast #bit(U16x8, odd12) ^ 0x8000_u16
        let biased7   = cast #bit(U16x8, tmp7) ^ 0x8000_u16
        finishHorizontal!{false}(biasedDc, biased4, biased13, biasedMix, biased10, biased11, biased12, biased7, left, right)
        finishHorizontal!{true}(biasedDc, biased4, biased13, biasedMix, biased10, biased11, biased12, biased7, left + 4, right + 4)
    }

    // Expands a row's eight occupancy bits to the corresponding entropy-order positions.
    func makeZigzagOccupancyMasks()->[8 * 256] u64
    {
        var result: #returntype
        for row in 8
        {
            for bits in 256
            {
                var mask: u64
                for col in 8 where bits & (1 << col)
                {
                    mask |= 1_u64 << ZigZag[row * 8 + col]
                }

                result[row * 256 + bits] = mask
            }
        }

        return result
    }

    func makeZigzagToBlock()->[64] u8
    {
        var result: #returntype
        for offset in 64
        {
            result[ZigZag[offset]] = cast(u8, offset)
        }

        return result
    }

    const ZigzagOccupancyMasks = #run makeZigzagOccupancyMasks()
    const ZigzagToBlock        = #run makeZigzagToBlock()

    // Stores eight quantized coefficients at once. Only their occupancy is reordered.
    func quantization(data: [*] s16, fdtbl: [*] f32, outData: [*] s16)->u64
    {
        var left, right: [8] Math.Simd.F32x4
        transformHorizontal(data, left, right)
        transformFourLines(left)
        transformFourLines(right)

        var occupied: u64
        let zero     = Math.Simd.splat(0_s16)
        let rounding = Math.Simd.splat(16384.5_f32)
        for row in 8
        {
            let offset = row * 8

            // Keep the scalar transform's separate roundings for scaling and bias.
            let low    = Math.mulAdd(left[row], Math.Simd.load(fdtbl + offset), rounding)
            let high   = Math.mulAdd(right[row], Math.Simd.load(fdtbl + offset + 4), rounding)
            let values = Math.Simd.packSigned(Math.Simd.truncateToS32(low) - 16384,
                                              Math.Simd.truncateToS32(high) - 16384)
            let rowMask = Math.Simd.bitmask(values != zero)
            Math.Simd.store(outData + offset, values)
            occupied |= ZigzagOccupancyMasks[row * 256 + rowMask]
        }

        return occupied & ~1_u64
    }

    // A coefficient category is the number of bits needed for its absolute magnitude.
    #[Swag.Inline]
    func magnitudeCategory(value: s32)->u8
    {
        let sign      = value >> 31
        let magnitude = cast(u32, ((value ^ sign) - sign))
        return cast(u8, (32 - Math.leadingZeros(magnitude)))
    }

    const ShortAcRadius = 128_u32
    const ShortAcRuns   = 4
    const ShortAcWidth  = ShortAcRadius * 2

    func makeShortAcCodes(table: const [*] u32)->[ShortAcRuns * ShortAcWidth] u32
    {
        var result: #returntype
        for run in ShortAcRuns
        {
            for index in ShortAcWidth
            {
                let value     = cast(s32, index) - cast(s32, ShortAcRadius)
                let category  = magnitudeCategory(value)
                let mask      = (1_u32 << category) - 1
                let amplitude = cast #bit(u32, (value + (value >> 31))) & mask
                result[run * ShortAcWidth + index] = table[run * 16 + category] | amplitude
            }
        }

        return result
    }

    const ShortLumaAcCodes   = #run makeShortAcCodes(LumaAcCodes)
    const ShortChromaAcCodes = #run makeShortAcCodes(ChromaAcCodes)

    #[Swag.Inline]
    func rgbWord(source: const [*] u8)->u32
    {
        return cast(u32, cast(const [*] u16, source)[0]) | (cast(u32, source[2]) << 16)
    }

    func flatColorBlock(source: const [*] u8, stride: u64, pixelSize, columns, rows: u32)->bool
    {
        let color = rgbWord(source)
        let last  = (columns - 1) * pixelSize
        if rgbWord(source + last) != color or rgbWord(source - (rows - 1) * stride + last) != color
        {
            return false
        }

        if columns != 8 or rows != 8
        {
            for y in rows
            {
                let row = source - y * stride
                for x in columns where rgbWord(row + x * pixelSize) != color
                {
                    return false
                }
            }

            return true
        }

        if pixelSize == 4
        {
            let rgbMask  = Math.Simd.splat(0xFF_FFFF_u32)
            let repeated = Math.Simd.splat(color)
            for y in 8
            {
                let row = cast(const [*] u32, source - y * stride)
                if Math.Simd.anyTrue(((Math.Simd.load(row) & rgbMask) != repeated) |
                                     ((Math.Simd.load(row + 4) & rgbMask) != repeated))
                {
                    return false
                }
            }
        }
        else
        {
            const Head = cast(Math.Simd.U8x16, [0_u8, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0])
            const Tail = cast(Math.Simd.U8x16, [2_u8, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2])
            let seed = Math.Simd.load(source)
            let head = Math.Simd.shuffle(seed, Head)
            let tail = Math.Simd.shuffle(seed, Tail)
            for y in 8
            {
                let row = source - y * stride
                if Math.Simd.anyTrue((Math.Simd.load(row) != head) | (Math.Simd.load(row + 8) != tail))
                {
                    return false
                }
            }
        }

        return true
    }

    #[Swag.Inline]
    mtd writeDc(dc: s16, prior: *s16, table: const [*] u32)
    {
        let difference = dc - prior[]
        prior[] = dc
        let category = magnitudeCategory(difference)
        .writeAmplitude(table[category], difference, category)
    }

    #[Swag.Inline]
    mtd writeFlatComponent(sample: s32, scale: f32, prior: *s16, dcTable, acTable: const [*] u32)
    {
        // A uniform block has one DC term, scaled by eight in each AAN pass.
        let scaled = cast(f32, sample * 64) * scale
        let value  = cast(s16, (cast(s16, (scaled + 16384.5)) - 16384))
        .writeDc(value, prior, dcTable)
        .writePackedCode(acTable[0])
    }

    mtd processDU(componentDU: [*] s16, fdtbl: [*] f32, dC: *s16, hTDC, hTAC: const [*] u32)
    {
        var occupied = quantization(componentDU, fdtbl, .du)

        .writeDc(.du[0], dC, hTDC)

        let shortCodes = hTAC == cast(const [*] u32, LumaAcCodes) ? cast(const [*] u32, ShortLumaAcCodes) : cast(const [*] u32, ShortChromaAcCodes)
        var next       = 1_u64
        while occupied
        {
            let index = Math.trailingZeros(occupied)
            var run   = index - next
            while run >= 16
            {
                .writePackedCode(hTAC[0xF0])
                run -= 16
            }

            let value      = .du[ZigzagToBlock[index]]
            let shortIndex = cast #bit(u32, (cast(s32, value) + cast(s32, ShortAcRadius)))
            if run < ShortAcRuns and shortIndex < ShortAcWidth
            {
                .writePackedCode(shortCodes[run * ShortAcWidth + shortIndex])
            }
            else
            {
                let category = magnitudeCategory(value)
                .writeAmplitude(hTAC[run * 16 + category], value, category)
            }

            next     = index + 1
            occupied &= occupied - 1
        }

        if next < 64
        {
            .writePackedCode(hTAC[0])
        }
    }
}
