#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Per-plane NV12 quantization must agree with the decoder's chroma DC Hadamard, AC table,
// QPc mapping and inverse transform, including both chroma matrix-list indices.
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

    const Stride = 20'u64
    const Offsets: [3] s32 = [-12, 0, 12]
    for qp in 52'u32
    {
        for offset in Offsets
        {
            for seed in 18'u64
            {
                var source: [8 * Stride] u8
                var prediction: [8 * Stride] u8
                for row in 8'u64
                {
                    for column in 8'u64
                    {
                        for plane in 2'u64
                        {
                            let pos = row * Stride + column * 2 + plane
                            let base = cast(u8, (seed * 29 + row * 31 + column * 17 + plane * 43) & 255)
                            prediction[pos] = base
                            var sample = base
                            if seed % 6 == 1 do
                                sample = cast(u8, Math.min(cast(u32, base) + 16, 255))
                            elif seed % 6 == 2 do
                                sample = cast(u8, Math.max(cast(s32, base) - 23, 0))
                            elif seed % 6 == 3 do
                                sample = cast(u8, (row + column + plane) % 2 ? 255 : 0)
                            elif seed % 6 == 4 do
                                sample = cast(u8, (seed * 41 + row * 59 + column * 7 + plane * 19) & 255)
                            elif seed % 6 == 5 do
                                sample = cast(u8, 255 - base)
                            source[pos] = sample
                        }
                    }
                }
                for plane in 2'u64
                {
                    var actual: H264.InterChroma8x8Result
                    H264.quantizeInterChroma8x8(source.buffer + plane,
                                                prediction.buffer + plane,
                                                Stride, Stride, qp, offset, &actual)
                    let qpc = cast(u64, H264.ChromaQp[cast(u64,
                        Math.clamp(cast(s32, qp) + offset, 0, 51))])
                    Swag.require(actual.qpc == qpc)
                    var expected: [64] u8
                    for row in 8'u64
                    {
                        for column in 8'u64 do
                            expected[row * 8 + column] = prediction[row * Stride + column * 2 + plane]
                    }
                    var dc = actual.dc
                    H264.hadamard2x2(dc.buffer)
                    var codedPattern = 0'u8
                    for block in 4'u64
                    {
                        let bx = block & 1
                        let by = block >> 1
                        var coeffs: [16] s16
                        let dcValue = (cast(s64, dc[block]) *
                                       cast(s64, pps.dequant4[4 + plane, qpc, 0])) >> 5
                        coeffs[0] = cast(s16, Math.clamp(dcValue, -32768, 32767))
                        var nonZeroAc = 0'u8
                        for scan in 1'u64 until 16
                        {
                            let level = actual.ac[block * 16 + scan]
                            if level do
                                nonZeroAc += 1
                            let raster = cast(u64, H264.ResidualOrder[H264.ResidualOrderAc + scan - 1])
                            coeffs[raster] = H264.dequantLevel(level,
                                pps.dequant4[4 + plane, qpc, raster], 4)
                        }
                        Swag.require(actual.ac[block * 16] == 0)
                        Swag.require(actual.nonZeroAc[block] == nonZeroAc)
                        if nonZeroAc do
                            codedPattern = 2
                        H264.addIdct4x4(expected.buffer + by * 4 * 8 + bx * 4, 8,
                                         coeffs.buffer)
                    }
                    for level in actual.dc where level != 0 and codedPattern == 0 do
                        codedPattern = 1
                    Swag.require(actual.cbp == codedPattern)
                    Swag.require(Memory.compare(expected.buffer, actual.reconstructed.buffer, 64) == 0)
                }
            }
        }
    }
}

// The non-linear QPc plateau and opposing full-range UV planes exercise low and high QP.
#test
{
    var source: [8 * 16] u8
    var prediction: [8 * 16] u8
    for row in 8'u64
    {
        for column in 8'u64
        {
            source[row * 16 + column * 2] = 255
            source[row * 16 + column * 2 + 1] = (row + column) % 2 ? 255 : 0
            prediction[row * 16 + column * 2] = 0
            prediction[row * 16 + column * 2 + 1] = source[row * 16 + column * 2 + 1] != 0 ? 0 : 255
        }
    }
    var result: H264.InterChroma8x8Result
    H264.quantizeInterChroma8x8(source.buffer + 1, prediction.buffer + 1,
                                16, 16, 0, 0, &result)
    Swag.require(result.qpc == 0 and result.cbp == 2)
    H264.quantizeInterChroma8x8(source.buffer, prediction.buffer, 16, 16, 29, 0, &result)
    Swag.require(result.qpc == 29 and result.cbp == 1)
    H264.quantizeInterChroma8x8(source.buffer, prediction.buffer, 16, 16, 30, 0, &result)
    Swag.require(result.qpc == 29)
    H264.quantizeInterChroma8x8(source.buffer, prediction.buffer, 16, 16, 31, 0, &result)
    Swag.require(result.qpc == 30)
    H264.quantizeInterChroma8x8(source.buffer + 1, prediction.buffer + 1,
                                16, 16, 51, 0, &result)
    Swag.require(result.qpc == 39 and result.cbp == 2)
}
