#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The encoder's zigzag levels and local reconstruction must match the decoder's own
// default-matrix scaling and inverse transform at every luma QP.
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

    const SourceStride = 11'u64
    const PredictionStride = 9'u64
    for qp in 52'u32
    {
        for seed in 24'u64
        {
            var source: [4 * SourceStride] u8
            var prediction: [4 * PredictionStride] u8
            for row in 4'u64
            {
                for column in 4'u64
                {
                    let base = cast(u8, (seed * 29 + row * 17 + column * 13) & 255)
                    prediction[row * PredictionStride + column] = base
                    var sample = base
                    switch seed % 6
                    {
                    case 1: sample = cast(u8, Math.min(cast(u32, base) + 16, 255))
                    case 2: sample = cast(u8, Math.max(cast(s32, base) - 23, 0))
                    case 3: sample = cast(u8, (row + column) % 2 ? 255 : 0)
                    case 4: sample = cast(u8, (seed * 41 + row * 59 + column * 7) & 255)
                    case 5: sample = cast(u8, 255 - base)
                    }
                    source[row * SourceStride + column] = sample
                }
            }
            var actual: H264.InterLuma4x4Result
            H264.quantizeInterLuma4x4(source.buffer, prediction.buffer,
                                      SourceStride, PredictionStride, qp, &actual)

            var expected: [16] u8
            var coefficients: [16] s16
            var nonZero = 0'u8
            for row in 4'u64
            {
                for column in 4'u64 do
                    expected[row * 4 + column] = prediction[row * PredictionStride + column]
            }
            for scan in 16'u64
            {
                let level = actual.levels[scan]
                if level do
                    nonZero += 1
                let raster = cast(u64, H264.ResidualOrder[H264.ResidualOrder4x4 + scan])
                coefficients[raster] = H264.dequantLevel(level,
                    pps.dequant4[3, cast(u64, qp), raster], 4)
            }
            H264.addIdct4x4(expected.buffer, 4, coefficients.buffer)
            Swag.require(actual.nonZero == nonZero)
            Swag.require(Memory.compare(actual.reconstructed.buffer, expected.buffer, 16) == 0)
        }
    }
}

// QP0 keeps the established half-step forward quantizer; increasing QP scales the
// coefficient level and reconstructs a representable flat inter residual.
#test
{
    var source: [16] u8
    var prediction: [16] u8
    for index in 16'u64
    {
        source[index] = 116
        prediction[index] = 100
    }
    var result: H264.InterLuma4x4Result
    H264.quantizeInterLuma4x4(source.buffer, prediction.buffer, 4, 4, 0, &result)
    Swag.require(result.levels[0] == 102 and result.nonZero == 1)
    for pixel in result.reconstructed do
        Swag.require(pixel == 116)

    H264.quantizeInterLuma4x4(source.buffer, prediction.buffer, 4, 4, 6, &result)
    Swag.require(result.levels[0] == 51 and result.nonZero == 1)
    for pixel in result.reconstructed do
        Swag.require(pixel == 116)

    H264.quantizeInterLuma4x4(source.buffer, prediction.buffer, 4, 4, 30, &result)
    Swag.require(result.levels[0] == 3 and result.nonZero == 1)
    for pixel in result.reconstructed do
        Swag.require(pixel == 115)
}

// Opposite full-range predictions exercise the largest forward levels and the decoder's
// signed-16-bit inverse clamp at both ends of the legal luma QP range.
#test
{
    const Qps: [2] u32 = [0, 51]
    for qp in Qps
    {
        for pattern in 4'u64
        {
            var source: [16] u8
            var prediction: [16] u8
            for pixel in 16'u64
            {
                var high = true
                if pattern == 1 do
                    high = false
                elif pattern == 2 do
                    high = (pixel / 4 + pixel % 4) % 2 == 0
                elif pattern == 3 do
                    high = ((pixel * 37 + 11) & 4) != 0
                source[pixel] = high ? 255 : 0
                prediction[pixel] = high ? 0 : 255
            }
            var actual: H264.InterLuma4x4Result
            H264.quantizeInterLuma4x4(source.buffer, prediction.buffer, 4, 4, qp, &actual)
            var expected: [16] u8
            var coefficients: [16] s16
            for pixel in 16'u64 do
                expected[pixel] = prediction[pixel]
            for scan in 16'u64
            {
                let raster = cast(u64, H264.ResidualOrder[H264.ResidualOrder4x4 + scan])
                let class = ((raster & 3) & 1) + (((raster >> 2) & 3) & 1)
                let scale = cast(u32, H264.Dequant4Scale[(qp % 6) * 3 + class]) * 16 << (qp / 6)
                coefficients[raster] = H264.dequantLevel(actual.levels[scan], scale, 4)
            }
            H264.addIdct4x4(expected.buffer, 4, coefficients.buffer)
            Swag.require(Memory.compare(expected.buffer, actual.reconstructed.buffer, 16) == 0)
            Swag.require(actual.nonZero != 0)
        }
    }
}
