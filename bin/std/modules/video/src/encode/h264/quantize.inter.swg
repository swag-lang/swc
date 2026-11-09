//! Format: H.264/AVC inter residual quantization.
//! Supported: Progressive 8-bit inter 4x4 luma blocks at QP 0 through 51.
//! Not supported: Chroma, intra prediction, entropy coding, and rate control.
//! Role: This file prepares quantized luma levels and their locally reconstructed prediction.
//
#global namespace H264
#global private

using Core

// H.264 4x4 forward quantizer multiplication factors by QP modulo six and position class.
// Forward rounding is an encoder choice. The inverse scaling below is decoder normative.
private const InterLuma4x4QuantFactor: [6, 3] u16 = [
    [13_107, 8_066, 5_243],
    [11_916, 7_490, 4_660],
    [10_082, 6_554, 4_194],
    [9_362, 5_825, 3_647],
    [8_192, 5_243, 3_355],
    [7_282, 4_559, 2_893]]

// Raster coefficient position to H.264 4x4 zigzag scan position. Kept here so this
// preparatory helper has no dependency on the current encoder's private scan table.
private const InterLuma4x4ScanPosition: [16] u8 = [0, 1, 5, 6, 2, 4, 7, 12,
                                                    3, 8, 11, 13, 9, 10, 14, 15]

// CAVLC levels follow 4x4 zigzag order; reconstruction remains a tightly packed 4x4 block.
private struct InterLuma4x4Result
{
    levels:        [16] s16
    reconstructed: [16] u8
    nonZero:       u8
}

// Quantizes one inter luma residual and reconstructs it against the supplied reference.
//
// `source` and `prediction` point to the top-left samples of a complete 4x4 block. The
// caller keeps the reference immutable for the whole picture and copies `reconstructed`
// into a separate current-picture buffer after choosing to code these levels.
private func quantizeInterLuma4x4(source, prediction: const [*] u8,
                                  sourceStride, predictionStride: u64, qp: u32,
                                  result: *InterLuma4x4Result)
{
    Swag.assert(qp <= 51)
    var horizontal: [16] s32
    for row in 4'u64
    {
        let src = source + row * sourceStride
        let pred = prediction + row * predictionStride
        let a0 = cast(s32, src[0]) - cast(s32, pred[0])
        let a1 = cast(s32, src[1]) - cast(s32, pred[1])
        let a2 = cast(s32, src[2]) - cast(s32, pred[2])
        let a3 = cast(s32, src[3]) - cast(s32, pred[3])
        let s0 = a0 + a3
        let s1 = a1 + a2
        let s2 = a1 - a2
        let s3 = a0 - a3
        horizontal[row * 4] = s0 + s1
        horizontal[row * 4 + 1] = 2 * s3 + s2
        horizontal[row * 4 + 2] = s0 - s1
        horizontal[row * 4 + 3] = s3 - 2 * s2
        for column in 4'u64 do
            result.reconstructed[row * 4 + column] = pred[column]
    }

    var scaled: [16] s16
    result.nonZero = 0
    let qmod = cast(u64, qp % 6)
    let qdiv = qp / 6
    let qbits = 15 + qdiv
    for column in 4'u64
    {
        let a0 = horizontal[column]
        let a1 = horizontal[4 + column]
        let a2 = horizontal[8 + column]
        let a3 = horizontal[12 + column]
        let s0 = a0 + a3
        let s1 = a1 + a2
        let s2 = a1 - a2
        let s3 = a0 - a3
        let coefficients: [4] s32 = [s0 + s1, 2 * s3 + s2,
                                     s0 - s1, s3 - 2 * s2]
        for row in 4'u64
        {
            let raster = row * 4 + column
            let class = (row & 1) + (column & 1)
            let coefficient = coefficients[row]
            let factor = cast(s64, InterLuma4x4QuantFactor[qmod, class])
            let magnitude = (cast(s64, Math.abs(coefficient)) * factor +
                             (1's64 << (qbits - 1))) >> qbits
            let level = cast(s32, coefficient < 0 ? -magnitude : magnitude)
            // An 8-bit source and prediction bound every transformed coefficient to 9180;
            // even the largest QP-0 factor leaves its level well inside signed 16 bits.
            Swag.assert(magnitude <= Swag.S16.Max)
            let scan = cast(u64, InterLuma4x4ScanPosition[raster])
            result.levels[scan] = cast(s16, level)
            if level do
                result.nonZero += 1
            let scale = cast(u32, Dequant4Scale[qmod * 3 + class]) * 16 << qdiv
            scaled[column * 4 + row] = dequantLevel(level, scale, 4)
        }
    }
    addIdct4x4Scalar(result.reconstructed.buffer, 4, scaled.buffer)
}
