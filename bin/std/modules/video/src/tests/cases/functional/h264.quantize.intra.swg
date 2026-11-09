#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Wide forward Hadamard must retain a full-range 16x16 DC residual before its quantizer.
#test
{
    var raw: [16] s32
    for &value in raw do
        value[] = 4_080
    var transformed: [16] s32
    H264.forwardIntraDc4x4(raw.buffer, transformed.buffer)
    Swag.require(transformed[0] == 65_280)
    for index in 1'u64 until 16 do
        Swag.require(transformed[index] == 0)
}

// Compare every luma QP with the decoder's Intra_16x16 DC predictor, dequant tables,
// DC Hadamard and per-block inverse transform. Borders are varied independently.
#test
{
    var scaling4: [6 * 16] u8
    var scaling8: [6 * 64] u8
    for &value in scaling4 do
        value[] = 16
    for &value in scaling8 do
        value[] = 16
    var pps: H264.Pps
    pps.buildDequant(Swag.makeSlice(&scaling4[0], scaling4.count),
                     Swag.makeSlice(&scaling8[0], scaling8.count))

    const Stride = 32'u64
    const SourceStride = 20'u64
    const X = 16'u64
    const Y = 16'u64
    for qp in 52'u32
    {
        for seed in 12'u64
        {
            for border in 4'u64
            {
                let hasLeft = (border & 1) != 0
                let hasTop = (border & 2) != 0
                var current: [32 * Stride] u8
                var expected: [32 * Stride] u8
                var source: [16 * SourceStride] u8
                for index in current.count
                {
                    let value = cast(u8, (index * 13 + seed * 37 + border * 17) & 255)
                    current[index] = value
                    expected[index] = value
                }
                for row in 16'u64
                {
                    for column in 16'u64
                    {
                        var sample = cast(u8, (row * 19 + column * 31 + seed * 41) & 255)
                        if seed % 4 == 0 do
                            sample = 0
                        elif seed % 4 == 1 do
                            sample = 255
                        elif seed % 4 == 2 do
                            sample = (row + column) % 2 ? 255 : 0
                        source[row * SourceStride + column] = sample
                    }
                }

                var actual: H264.IntraLuma16x16Result
                H264.quantizeIntraLuma16x16(source.buffer, SourceStride,
                    current.buffer, Stride, X, Y, hasLeft, hasTop, qp, &actual)
                H264.intraPredict16x16(H264.Intra16Dc,
                    expected.buffer + Y * Stride + X, Stride, hasLeft, hasTop)
                Swag.require(actual.prediction == expected[Y * Stride + X])

                var dc: [16] s16
                for scan in 16'u64 do
                    dc[cast(u64, H264.Zigzag4[scan])] = actual.dc[scan]
                H264.hadamard4x4(dc.buffer)
                var hasAc = false
                for block in 16'u64
                {
                    let bx = block & 3
                    let by = block >> 2
                    var coefficients: [16] s16
                    let dcScale = cast(s64, pps.dequant4[0, cast(u64, qp), 0])
                    let dcValue = (cast(s64, dc[block]) * dcScale + 32) >> 6
                    coefficients[0] = cast(s16, Math.clamp(dcValue, -32768, 32767))
                    Swag.require(actual.ac[block * 16] == 0)
                    var nonZeroAc = 0'u8
                    for scan in 1'u64 until 16
                    {
                        let level = actual.ac[block * 16 + scan]
                        if level do
                            nonZeroAc += 1
                        let raster = cast(u64,
                            H264.ResidualOrder[H264.ResidualOrderAc + scan - 1])
                        coefficients[raster] = H264.dequantLevel(level,
                            pps.dequant4[0, cast(u64, qp), raster], 4)
                    }
                    Swag.require(actual.nonZeroAc[block] == nonZeroAc)
                    if nonZeroAc do
                        hasAc = true
                    H264.addIdct4x4(expected.buffer + (Y + by * 4) * Stride + X + bx * 4,
                                     Stride, coefficients.buffer)
                }
                Swag.require(actual.cbpLuma == (hasAc ? 15'u32 : 0'u32))
                for row in 16'u64
                {
                    Swag.require(Memory.compare(actual.reconstructed.buffer + row * 16,
                        expected.buffer + (Y + row) * Stride + X, 16) == 0)
                }
            }
        }
    }
}

// Intra chroma DC uses quadrant-specific neighbour averages. Its reused 8x8 quantizer
// must still agree with the decoder's intra Cb/Cr tables and inverse at every QPc.
#test
{
    var scaling4: [6 * 16] u8
    var scaling8: [6 * 64] u8
    for &value in scaling4 do
        value[] = 16
    for &value in scaling8 do
        value[] = 16
    var pps: H264.Pps
    pps.buildDequant(Swag.makeSlice(&scaling4[0], scaling4.count),
                     Swag.makeSlice(&scaling8[0], scaling8.count))

    const Stride = 32'u64
    const SourceStride = 20'u64
    const X = 16'u64
    const Y = 16'u64
    const Offsets: [3] s32 = [-12, 0, 12]
    for qp in 52'u32
    {
        for offset in Offsets
        {
            for seed in 8'u64
            {
                for border in 4'u64
                {
                    let hasLeft = (border & 1) != 0
                    let hasTop = (border & 2) != 0
                    var current: [16 * Stride] u8
                    var source: [8 * SourceStride] u8
                    for row in 16'u64
                    {
                        for column in 16'u64
                        {
                            for plane in 2'u64
                            {
                                current[row * Stride + column * 2 + plane] = cast(u8,
                                    (row * 19 + column * 31 + plane * 43 + seed * 17) & 255)
                            }
                        }
                    }
                    for row in 8'u64
                    {
                        for column in 8'u64
                        {
                            for plane in 2'u64
                            {
                                var sample = cast(u8, (row * 47 + column * 23 + seed * 41 +
                                                       plane * 29) & 255)
                                if seed % 4 == 0 do
                                    sample = 0
                                elif seed % 4 == 1 do
                                    sample = 255
                                elif seed % 4 == 2 do
                                    sample = (row + column + plane) % 2 ? 255 : 0
                                source[row * SourceStride + column * 2 + plane] = sample
                            }
                        }
                    }
                    for plane in 2'u64
                    {
                        var actual: H264.InterChroma8x8Result
                        H264.quantizeIntraChroma8x8(source.buffer, SourceStride,
                            current.buffer, Stride, X, Y, cast(u32, plane),
                            hasLeft, hasTop, qp, offset, &actual)
                        let qpc = cast(u64, H264.ChromaQp[cast(u64,
                            Math.clamp(cast(s32, qp) + offset, 0, 51))])
                        Swag.require(actual.qpc == qpc)

                        var expected: [16 * 16] u8
                        for row in 16'u64
                        {
                            for column in 16'u64 do
                                expected[row * 16 + column] =
                                    current[row * Stride + column * 2 + plane]
                        }
                        H264.intraPredictChroma(H264.IntraChromaDc,
                            expected.buffer + 8 * 16 + 8, 16, hasLeft, hasTop)
                        var dc = actual.dc
                        H264.hadamard2x2(dc.buffer)
                        var codedPattern = 0'u8
                        for block in 4'u64
                        {
                            let bx = block & 1
                            let by = block >> 1
                            var coeffs: [16] s16
                            let dcValue = (cast(s64, dc[block]) *
                                cast(s64, pps.dequant4[1 + plane, qpc, 0])) >> 5
                            coeffs[0] = cast(s16, Math.clamp(dcValue, -32768, 32767))
                            var nonZeroAc = 0'u8
                            for scan in 1'u64 until 16
                            {
                                let level = actual.ac[block * 16 + scan]
                                if level do
                                    nonZeroAc += 1
                                let raster = cast(u64,
                                    H264.ResidualOrder[H264.ResidualOrderAc + scan - 1])
                                coeffs[raster] = H264.dequantLevel(level,
                                    pps.dequant4[1 + plane, qpc, raster], 4)
                            }
                            Swag.require(actual.nonZeroAc[block] == nonZeroAc)
                            if nonZeroAc do
                                codedPattern = 2
                            H264.addIdct4x4(expected.buffer + (8 + by * 4) * 16 + 8 + bx * 4,
                                16, coeffs.buffer)
                        }
                        for level in actual.dc where level != 0 and codedPattern == 0 do
                            codedPattern = 1
                        Swag.require(actual.cbp == codedPattern)
                        for row in 8'u64
                        {
                            Swag.require(Memory.compare(actual.reconstructed.buffer + row * 8,
                                expected.buffer + (8 + row) * 16 + 8, 8) == 0)
                        }
                    }
                }
            }
        }
    }
}
