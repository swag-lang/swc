#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A uniform inter residual has one quantized DC level. Check every QP, signed
// residuals and predictions at byte limits against the decoder inverse transform.
#test
{
    const Prediction: [4] u8 = [0, 255, 80, 173]
    const Source: [4] u8 = [255, 0, 85, 150]
    for qp in 52'u32
    {
        for pattern in 4'u64
        {
            var source: [16] u8
            var prediction: [16] u8
            for index in 16'u64
            {
                source[index] = Source[pattern]
                prediction[index] = Prediction[pattern]
            }
            var actual: H264.InterLuma4x4Result
            H264.quantizeInterLuma4x4(source.buffer, prediction.buffer, 4, 4, qp, &actual)
            for index in 15'u64 do
                Swag.require(actual.levels[index + 1] == 0)

            let delta = cast(s32, Source[pattern]) - cast(s32, Prediction[pattern])
            let coefficient = delta * 16
            let qmod = cast(u64, qp % 6)
            let qbits = 15 + qp / 6
            let magnitude = (cast(s64, Math.abs(coefficient)) *
                             cast(s64, H264.InterLuma4x4QuantFactor[qmod, 0]) +
                             (1's64 << (qbits - 1))) >> qbits
            let level = cast(s16, coefficient < 0 ? -magnitude : magnitude)
            Swag.require(actual.levels[0] == level)
            Swag.require(actual.nonZero == (level ? 1 : 0))

            var reconstructed: [16] u8
            for index in 16'u64 do
                reconstructed[index] = prediction[index]
            var coefficients: [16] s16
            let scale = cast(u32, H264.Dequant4Scale[qmod * 3]) * 16 << (qp / 6)
            coefficients[0] = H264.dequantLevel(level, scale, 4)
            H264.addIdct4x4Scalar(reconstructed.buffer, 4, coefficients.buffer)
            Swag.require(Memory.compare(actual.reconstructed.buffer,
                                        reconstructed.buffer, 16) == 0)
        }
    }
}

// A weak checkerboard is not a constant residual, but higher QPs retain only
// DC. The decoder transform remains the reconstruction oracle for that path.
#test
{
    var dcOnlySeen = false
    var acSeen = false
    for qp in 52'u32
    {
        for pattern in 3'u64
        {
            var source: [16] u8
            var prediction: [16] u8
            for index in 16'u64
            {
                let pred = pattern == 0 ? 100'u8 : (pattern == 1 ? 240'u8 : 15'u8)
                prediction[index] = pred
                if pattern == 0 do
                    source[index] = index & 1 ? 117 : 115
                elif pattern == 1 do
                    source[index] = index & 1 ? 255 : 253
                else do
                    source[index] = index & 1 ? 2 : 0
            }
            var actual: H264.InterLuma4x4Result
            H264.quantizeInterLuma4x4(source.buffer, prediction.buffer, 4, 4, qp, &actual)
            if actual.nonZero == 1 and actual.levels[0] do
                dcOnlySeen = true
            if actual.nonZero > 1 do
                acSeen = true

            var expected = prediction
            var coefficients: [16] s16
            for scan in 16'u64
            {
                let raster = cast(u64, H264.ResidualOrder[H264.ResidualOrder4x4 + scan])
                let class = (raster & 1) + ((raster >> 2) & 1)
                let scale = cast(u32, H264.Dequant4Scale[(qp % 6) * 3 + class]) * 16 << (qp / 6)
                coefficients[raster] = H264.dequantLevel(actual.levels[scan], scale, 4)
            }
            H264.addIdct4x4Scalar(expected.buffer, 4, coefficients.buffer)
            Swag.require(Memory.compare(actual.reconstructed.buffer, expected.buffer, 16) == 0)
        }
    }
    Swag.require(dcOnlySeen and acSeen)
}

// Flat chroma may differ in each quadrant; only the per-block AC is zero.
// Reconstructing through the decoder checks the shared 2x2 DC transform and QPc map.
#test
{
    const Offsets: [3] s32 = [-12, 0, 12]
    for qp in 52'u32
    {
        for offset in Offsets
        {
            for pattern in 4'u64
            {
                var source: [8 * 16] u8
                var prediction: [8 * 16] u8
                var expected: [64] u8
                for row in 8'u64
                {
                    for column in 8'u64
                    {
                        let block = (row / 4) * 2 + column / 4
                        var pred = 0'u8
                        var src = 255'u8
                        if pattern == 1
                        {
                            pred = 255
                            src = 0
                        }
                        elif pattern == 2
                        {
                            pred = 100
                            src = block & 1 ? 180 : 20
                        }
                        elif pattern == 3
                        {
                            pred = 125
                            src = block & 2 ? 127 : 123
                        }
                        source[row * 16 + column * 2] = src
                        prediction[row * 16 + column * 2] = pred
                        expected[row * 8 + column] = pred
                    }
                }
                var actual: H264.InterChroma8x8Result
                H264.quantizeInterChroma8x8(source.buffer, prediction.buffer,
                                            16, 16, qp, offset, &actual)
                for nonZero in actual.nonZeroAc do
                    Swag.require(nonZero == 0)
                for level in actual.ac do
                    Swag.require(level == 0)
                Swag.require(actual.cbp <= 1)

                var dc = actual.dc
                H264.hadamard2x2(dc.buffer)
                let qpc = cast(u64, actual.qpc)
                let scale = cast(s64, H264.Dequant4Scale[(qpc % 6) * 3]) * 16 << (qpc / 6)
                for block in 4'u64
                {
                    var coefficients: [16] s16
                    let value = (cast(s64, dc[block]) * scale) >> 5
                    coefficients[0] = cast(s16, Math.clamp(value, -32768, 32767))
                    let bx = block & 1
                    let by = block >> 1
                    H264.addIdct4x4Scalar(expected.buffer + by * 4 * 8 + bx * 4,
                                           8, coefficients.buffer)
                }
                Swag.require(Memory.compare(actual.reconstructed.buffer, expected.buffer, 64) == 0)
            }
        }
    }
}
