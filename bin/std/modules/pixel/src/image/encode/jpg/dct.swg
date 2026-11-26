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
        var edge: [32] u8
        let padded = cast([*] u8, edge)
        let luma   = cast([*] s16, &.duY[0])
        let blue   = cast([*] s16, &.duCb[0])
        let red    = cast([*] s16, &.duCr[0])

        let levelShift = Math.Simd.splat(128_s32)
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

            let low       = Math.Simd.load(row)
            let high      = Math.Simd.load(row + .rightOffset)
            let redLow    = channelOf(low, redLanes)
            let greenLow  = channelOf(low, greenLanes)
            let blueLow   = channelOf(low, blueLanes)
            let redHigh   = channelOf(high, .redLanesHigh)
            let greenHigh = channelOf(high, .greenLanesHigh)
            let blueHigh  = channelOf(high, .blueLanesHigh)

            Math.Simd.store(luma + pos,
                            Math.Simd.packSigned(componentOf(redLow, greenLow, blueLow, CoeffYR, CoeffYG, CoeffYB, 32_768) - levelShift,
                                                 componentOf(redHigh, greenHigh, blueHigh, CoeffYR, CoeffYG, CoeffYB, 32_768) - levelShift))
            Math.Simd.store(blue + pos,
                            Math.Simd.packSigned(componentOf(redLow, greenLow, blueLow, CoeffCbR, CoeffCbG, CoeffCbB, 32_767),
                                                 componentOf(redHigh, greenHigh, blueHigh, CoeffCbR, CoeffCbG, CoeffCbB, 32_767)))
            Math.Simd.store(red + pos,
                            Math.Simd.packSigned(componentOf(redLow, greenLow, blueLow, CoeffCrR, CoeffCrG, CoeffCrB, 32_767),
                                                 componentOf(redHigh, greenHigh, blueHigh, CoeffCrR, CoeffCrG, CoeffCrB, 32_767)))

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
    func transposeFour(values: [*] Math.Simd.F32x4)
    {
        let row0  = cast #bit(Math.Simd.U32x4, values[0])
        let row1  = cast #bit(Math.Simd.U32x4, values[1])
        let row2  = cast #bit(Math.Simd.U32x4, values[2])
        let row3  = cast #bit(Math.Simd.U32x4, values[3])
        let low0  = cast #bit(Math.Simd.U64x2, Math.Simd.interleaveLow(row0, row1))
        let high0 = cast #bit(Math.Simd.U64x2, Math.Simd.interleaveHigh(row0, row1))
        let low1  = cast #bit(Math.Simd.U64x2, Math.Simd.interleaveLow(row2, row3))
        let high1 = cast #bit(Math.Simd.U64x2, Math.Simd.interleaveHigh(row2, row3))
        values[0] = cast #bit(Math.Simd.F32x4, Math.Simd.interleaveLow(low0, low1))
        values[1] = cast #bit(Math.Simd.F32x4, Math.Simd.interleaveHigh(low0, low1))
        values[2] = cast #bit(Math.Simd.F32x4, Math.Simd.interleaveLow(high0, high1))
        values[3] = cast #bit(Math.Simd.F32x4, Math.Simd.interleaveHigh(high0, high1))
    }

    // Every shifted 16-bit sample fits exactly in the fraction at 2^23.
    #[Swag.Inline]
    func floatSamples(samples: Math.Simd.S32x4)->Math.Simd.F32x4
    {
        let shifted = cast #bit(Math.Simd.U32x4, (samples + 32768))
        let biased  = shifted | 0x4B000000_u32
        return cast #bit(Math.Simd.F32x4, biased) - 8421376.0_f32
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
                for col in 8 where bits & (1 << col) do
                    mask |= 1'u64 << ZigZag[row * 8 + col]
                result[row * 256 + bits] = mask
            }
        }

        return result
    }

    func makeZigzagToBlock()->[64] u8
    {
        var result: #returntype
        for offset in 64 do
            result[ZigZag[offset]] = cast(u8, offset)
        return result
    }

    const ZigzagOccupancyMasks = #run makeZigzagOccupancyMasks()
    const ZigzagToBlock        = #run makeZigzagToBlock()

    // Stores eight quantized coefficients at once. Only their occupancy is reordered.
    func quantization(data: [*] s16, fdtbl: [*] f32, outData: [*] s16)->u64
    {
        var dataFloat: [64] f32
        for i in 64
        {
            dataFloat[i] = data[i]
        }

        var dataptr = cast([*] f32, &dataFloat[0])
        for _ in rangeTo(0, 7).reversed()
        {
            var lanes: [8] Math.Simd.F32x4
            let block = cast([*] Math.Simd.F32x4, lanes)
            for row in 4
            {
                let samples = Math.Simd.load(data + group * 32 + row * 8)
                block[row]     = floatSamples(Math.Simd.widenLow(samples))
                block[row + 4] = floatSamples(Math.Simd.widenHigh(samples))
            }

            transposeFour(block)
            transposeFour(block + 4)
            transformFourLines(block)
            transposeFour(block)
            transposeFour(block + 4)
            for row in 4
            {
                let destination = coefficients + group * 32 + row * 8
                Math.Simd.store(destination, block[row])
                Math.Simd.store(destination + 4, block[row + 4])
            }
        }

        var left, right: [8] Math.Simd.F32x4
        for row in 8
        {
            left[row]  = Math.Simd.load(coefficients + row * 8)
            right[row] = Math.Simd.load(coefficients + row * 8 + 4)
        }

        transformFourLines(left)
        transformFourLines(right)

        var occupied: u64
        let zero     = Math.Simd.splat(0's16)
        let rounding = Math.Simd.splat(16384.5'f32)
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

        return occupied & ~1'u64
    }

    // A coefficient category is the number of bits needed for its absolute magnitude.
    #[Swag.Inline]
    func magnitudeCategory(value: s32)->u8
    {
        let sign      = value >> 31
        let magnitude = cast(u32, ((value ^ sign) - sign))
        return cast(u8, (32 - Math.leadingZeros(magnitude)))
    }

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

        var next = 1'u64
        while occupied
        {
            let index = Math.trailingZeros(occupied)
            var run   = index - next
            while run >= 16
            {
                .writePackedCode(hTAC[0xF0])
                run -= 16
            }

            let value    = .du[ZigzagToBlock[index]]
            let category = magnitudeCategory(value)
            .writeAmplitude(hTAC[run * 16 + category], value, category)
            next     = index + 1
            occupied &= occupied - 1
        }

        if next < 64 do
            .writePackedCode(hTAC[0])
    }
}
