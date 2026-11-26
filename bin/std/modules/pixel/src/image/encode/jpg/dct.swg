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
    func channelOf(source: const [*] u8, lanes: Math.Simd.U8x16)->Math.Simd.S32x4 => cast #bit(Math.Simd.S32x4, Math.Simd.shuffle(Math.Simd.load(source), lanes))

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
    mtd loadFromRGB(xpos: u16, ypos: u16)
    {
        var location = cast(s32, ypos) * .imageX + xpos
        let pixels   = cast(const [*] u8, .bufferRGB.storage())
        let luma     = cast([*] s16, &.duY[0])
        let blue     = cast([*] s16, &.duCb[0])
        let red      = cast([*] s16, &.duCr[0])

        let levelShift = Math.Simd.splat(128's32)
        var pos        = 0

        for 8
        {
            let row  = pixels + cast(u64, location) * #sizeof(ColorRGB)
            let next = row + 4 * #sizeof(ColorRGB)

            let redLow    = channelOf(row, RedLanes)
            let greenLow  = channelOf(row, GreenLanes)
            let blueLow   = channelOf(row, BlueLanes)
            let redHigh   = channelOf(next, RedLanes)
            let greenHigh = channelOf(next, GreenLanes)
            let blueHigh  = channelOf(next, BlueLanes)

            Math.Simd.store(luma + pos,
                            Math.Simd.packSigned(componentOf(redLow, greenLow, blueLow, CoeffYR, CoeffYG, CoeffYB, 32_768) - levelShift,
                                                 componentOf(redHigh, greenHigh, blueHigh, CoeffYR, CoeffYG, CoeffYB, 32_768) - levelShift))
            Math.Simd.store(blue + pos,
                            Math.Simd.packSigned(componentOf(redLow, greenLow, blueLow, CoeffCbR, CoeffCbG, CoeffCbB, 32_767),
                                                 componentOf(redHigh, greenHigh, blueHigh, CoeffCbR, CoeffCbG, CoeffCbB, 32_767)))
            Math.Simd.store(red + pos,
                            Math.Simd.packSigned(componentOf(redLow, greenLow, blueLow, CoeffCrR, CoeffCrG, CoeffCrB, 32_767),
                                                 componentOf(redHigh, greenHigh, blueHigh, CoeffCrR, CoeffCrG, CoeffCrB, 32_767)))

            location += .imageX
            pos      += 8
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

        let z1 = (tmp12 + tmp13) * 0.707106781'f32
        values[2] = tmp13 + z1
        values[6] = tmp13 - z1

        let odd10 = tmp4 + tmp5
        let odd11 = tmp5 + tmp6
        let odd12 = tmp6 + tmp7
        let z5    = (odd10 - odd12) * 0.382683433'f32

        // Match the scalar transform's separately rounded z2 product.
        let z2 = Math.mulAdd(odd10, Math.Simd.splat(0.541196100'f32), z5)
        let z4 = odd12 * 1.306562965'f32 + z5
        let z3 = odd11 * 0.707106781'f32

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
        let biased  = shifted | 0x4B000000'u32
        return cast #bit(Math.Simd.F32x4, biased) - 8421376.0'f32
    }

    // Transforms one block and quantizes it straight into zigzag order.
    //
    // The zigzag is applied while the coefficients are scaled, rather than in a pass of its own.
    func quantization(data: [*] s16, fdtbl: [*] f32, outData: [*] s16)
    {
        var dataFloat: [64] f32
        let coefficients = cast([*] f32, &dataFloat[0])
        for group in 2
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

        for group in 2
        {
            let firstColumn = group * 4
            var lanes: [8] Math.Simd.F32x4
            for row in 8 do
                lanes[row] = Math.Simd.load(coefficients + row * 8 + firstColumn)

            transformFourLines(lanes)

            // Keep multiplication and addition separately rounded as in the scalar transform.
            let rounding = Math.Simd.splat(16384.5'f32)
            for row in 8
            {
                let offset    = row * 8 + firstColumn
                let scaled    = Math.mulAdd(lanes[row], Math.Simd.load(fdtbl + offset), rounding)
                let quantized = Math.Simd.truncateToS32(scaled) - 16384
                for column in 4 do
                    outData[ZigZag[offset + column]] = cast(s16, quantized[column])
            }
        }
    }

    // A coefficient category is the number of bits needed for its absolute magnitude.
    #[Swag.Inline]
    func magnitudeCategory(value: s32)->u8
    {
        let sign      = value >> 31
        let magnitude = cast(u32, ((value ^ sign) - sign))
        return cast(u8, (32 - Math.leadingZeros(magnitude)))
    }

    // Check a few distant pixels before setting up the full comparison. Four-byte
    // reads can cross the final pixel because loadBitmap gives the buffer a readable tail.
    #[Swag.Inline]
    func flatColorBlock(source: const [*] ColorRGB, stride: u64)->bool
    {
        let first = cast(const [*] u32, source)[0] & 0xFF_FFFF
        if (cast(const [*] u32, source + 7)[0] & 0xFF_FFFF) != first or
           (cast(const [*] u32, source + stride * 3 + 4)[0] & 0xFF_FFFF) != first or
           (cast(const [*] u32, source + stride * 7 + 7)[0] & 0xFF_FFFF) != first do
            return false

        const Head = cast(Math.Simd.U8x16, [0'u8, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0])
        const Tail = cast(Math.Simd.U8x16, [2'u8, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2])
        let seed = Math.Simd.load(cast(const [*] u8, source))
        let head = Math.Simd.shuffle(seed, Head)
        let tail = Math.Simd.shuffle(seed, Tail)
        for y in 8'u64
        {
            let row = cast(const [*] u8, source + y * stride)
            if Math.Simd.anyTrue((Math.Simd.load(row) != head) | (Math.Simd.load(row + 8) != tail)) do
                return false
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
        let eob       = hTAC[0x00]
        let m16Zeroes = hTAC[0xF0]

        quantization(componentDU, fdtbl, .du)

        .writeDc(.du[0], dC, hTDC)

        var end0pos = 63
        while (end0pos > 0) and (.du[end0pos] == 0) do
            end0pos -= 1

        if end0pos == 0
        {
            .writePackedCode(eob)
            return
        }

        var i = 1
        while i <= end0pos
        {
            let startpos = i
            while (i <= end0pos) and (.du[i] == 0) do
                i += 1
            var nrzeroes = i - startpos
            if nrzeroes >= 16
            {
                for 1 to nrzeroes / 16 do
                    .writePackedCode(m16Zeroes)
                nrzeroes = nrzeroes % 16
            }

            let coefficient = .du[i]
            let category    = magnitudeCategory(coefficient)
            .writeAmplitude(hTAC[nrzeroes * 16 + category], coefficient, category)
            i += 1
        }

        if end0pos != 63 do
            .writePackedCode(eob)
    }
}
