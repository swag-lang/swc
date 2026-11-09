//! Format: H.264/AVC inter residual quantization.
//! Supported: Progressive 8-bit inter 4x4 luma and 4:2:0 chroma blocks at QP 0 through 51.
//! Not supported: Intra prediction, entropy coding, and rate control.
//! Role: This file prepares quantized inter levels and their locally reconstructed prediction.
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

    let qmod = cast(u64, qp % 6)
    let qdiv = qp / 6
    let qbits = 15 + qdiv
    // A constant 4x4 residual has only a DC coefficient (16 times its delta).
    // Keep the same quantizer and decoder inverse scale as the general path.
    let rowDc = horizontal[0]
    if horizontal[1] == 0 and horizontal[2] == 0 and horizontal[3] == 0 and
       horizontal[4] == rowDc and horizontal[5] == 0 and horizontal[6] == 0 and horizontal[7] == 0 and
       horizontal[8] == rowDc and horizontal[9] == 0 and horizontal[10] == 0 and horizontal[11] == 0 and
       horizontal[12] == rowDc and horizontal[13] == 0 and horizontal[14] == 0 and horizontal[15] == 0
    {
        let coefficient = rowDc * 4
        let magnitude = (cast(s64, Math.abs(coefficient)) *
                         cast(s64, InterLuma4x4QuantFactor[qmod, 0]) +
                         (1's64 << (qbits - 1))) >> qbits
        let level = cast(s32, coefficient < 0 ? -magnitude : magnitude)
        for index in 16'u64 do
            result.levels[index] = 0
        result.levels[0] = cast(s16, level)
        result.nonZero = level ? 1 : 0
        if level
        {
            let scale = cast(u32, Dequant4Scale[qmod * 3]) * 16 << qdiv
            let dc = dequantLevel(level, scale, 4)
            addDc4x4(result.reconstructed.buffer, 4, dc)
        }
        return
    }

    var scaled: [16] s16
    result.nonZero = 0
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
    if result.nonZero == 1 and result.levels[0] do
        addDc4x4(result.reconstructed.buffer, 4, scaled[0])
    elif result.nonZero do
        addIdct4x4Scalar(result.reconstructed.buffer, 4, scaled.buffer)
}

// One chroma plane of an inter 8x8 macroblock. AC levels are in the 4x4 zigzag order
// expected by residual15, with the unused DC slot at each block start set to zero.
private struct InterChroma8x8Result
{
    dc:            [4] s16
    ac:            [4 * 16] s16
    reconstructed: [64] u8
    nonZeroAc:     [4] u8
    cbp:           u8
    qpc:           u8
}

// Quantizes and reconstructs one Cb or Cr 8x8 inter plane from NV12 byte positions.
//
// Both input pointers address that plane's first byte in an interleaved UV row, so samples
// are two bytes apart. `result.reconstructed` is a packed single-plane 8x8 block; the
// caller places those samples into its separate current-picture NV12 buffer. The PPS chroma
// QP offset is applied before the non-linear 4:2:0 QPc map. The caller uses the Cb or Cr
// offset for the respective plane.
private func quantizeInterChroma8x8(source, prediction: const [*] u8,
                                    sourceStride, predictionStride: u64,
                                    lumaQp: u32, chromaQpOffset: s32,
                                    result: *InterChroma8x8Result)
{
    Swag.assert(lumaQp <= 51)
    let qpIndex = cast(u64, Math.clamp(cast(s32, lumaQp) + chromaQpOffset, 0, 51))
    let qpc = cast(u32, ChromaQp[qpIndex])
    result.qpc = cast(u8, qpc)
    result.cbp = 0
    let qmod = cast(u64, qpc % 6)
    let qdiv = qpc / 6
    let qbits = 15 + qdiv
    var rawDc: [4] s32
    var scaled: [4 * 16] s16
    for block in 4'u64
    {
        let bx = block & 1
        let by = block >> 1
        let base = block * 16
        var horizontal: [16] s32
        result.nonZeroAc[block] = 0
        result.ac[base] = 0
        for row in 4'u64
        {
            let src = source + (by * 4 + row) * sourceStride + bx * 8
            let pred = prediction + (by * 4 + row) * predictionStride + bx * 8
            let a0 = cast(s32, src[0]) - cast(s32, pred[0])
            let a1 = cast(s32, src[2]) - cast(s32, pred[2])
            let a2 = cast(s32, src[4]) - cast(s32, pred[4])
            let a3 = cast(s32, src[6]) - cast(s32, pred[6])
            let s0 = a0 + a3
            let s1 = a1 + a2
            let s2 = a1 - a2
            let s3 = a0 - a3
            horizontal[row * 4] = s0 + s1
            horizontal[row * 4 + 1] = 2 * s3 + s2
            horizontal[row * 4 + 2] = s0 - s1
            horizontal[row * 4 + 3] = s3 - 2 * s2
            for column in 4'u64 do
                result.reconstructed[(by * 4 + row) * 8 + bx * 4 + column] = pred[column * 2]
        }
        // Screen color changes commonly leave a constant residual within each 4x4
        // chroma block. Its forward transform has only DC; the shared 2x2 DC
        // Hadamard below still handles different deltas in adjacent blocks.
        let rowDc = horizontal[0]
        if horizontal[1] == 0 and horizontal[2] == 0 and horizontal[3] == 0 and
           horizontal[4] == rowDc and horizontal[5] == 0 and horizontal[6] == 0 and horizontal[7] == 0 and
           horizontal[8] == rowDc and horizontal[9] == 0 and horizontal[10] == 0 and horizontal[11] == 0 and
           horizontal[12] == rowDc and horizontal[13] == 0 and horizontal[14] == 0 and horizontal[15] == 0
        {
            rawDc[block] = rowDc * 4
            for scan in 1'u64 until 16
            {
                result.ac[base + scan] = 0
                scaled[base + scan] = 0
            }
            continue
        }
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
                let coefficient = coefficients[row]
                if not raster
                {
                    rawDc[block] = coefficient
                    continue
                }
                let class = (row & 1) + (column & 1)
                let factor = cast(s64, InterLuma4x4QuantFactor[qmod, class])
                let magnitude = (cast(s64, Math.abs(coefficient)) * factor +
                                 (1's64 << (qbits - 1))) >> qbits
                Swag.assert(magnitude <= Swag.S16.Max)
                let level = cast(s32, coefficient < 0 ? -magnitude : magnitude)
                let scan = cast(u64, InterLuma4x4ScanPosition[raster])
                result.ac[base + scan] = cast(s16, level)
                if level
                {
                    result.nonZeroAc[block] += 1
                    result.cbp = 2
                }
                let scale = cast(u32, Dequant4Scale[qmod * 3 + class]) * 16 << qdiv
                scaled[base + column * 4 + row] = dequantLevel(level, scale, 4)
            }
        }
    }

    let d0 = rawDc[0]
    let d1 = rawDc[1]
    let d2 = rawDc[2]
    let d3 = rawDc[3]
    let transformed: [4] s32 = [d0 + d1 + d2 + d3, d0 - d1 + d2 - d3,
                                 d0 + d1 - d2 - d3, d0 - d1 - d2 + d3]
    let dcBits = qbits + 1
    for index in 4'u64
    {
        let coefficient = transformed[index]
        let magnitude = (cast(s64, Math.abs(coefficient)) *
                         cast(s64, InterLuma4x4QuantFactor[qmod, 0]) +
                         (1's64 << (dcBits - 1))) >> dcBits
        Swag.assert(magnitude <= Swag.S16.Max)
        let level = cast(s32, coefficient < 0 ? -magnitude : magnitude)
        result.dc[index] = cast(s16, level)
        if level and result.cbp == 0 do
            result.cbp = 1
    }

    // Every destination sample already contains its prediction. When all
    // quantized coefficients vanish, the inverse transform adds only zeros.
    if not result.cbp do
        return
    var inverseDc = result.dc
    hadamard2x2(inverseDc.buffer)
    let dcScale = cast(s64, Dequant4Scale[qmod * 3]) * 16 << qdiv
    if result.cbp == 1
    {
        var dc: [4] s32
        for block in 4'u64
        {
            let value = (cast(s64, inverseDc[block]) * dcScale) >> 5
            dc[block] = cast(s32, Math.clamp(value, -32768, 32767))
        }
        addDc8x8Quad(result.reconstructed.buffer, 8, dc[0], dc[1], dc[2], dc[3])
        return
    }
    for block in 4'u64
    {
        let dcValue = (cast(s64, inverseDc[block]) * dcScale) >> 5
        scaled[block * 16] = cast(s16, Math.clamp(dcValue, -32768, 32767))
        if dcValue == 0 and not result.nonZeroAc[block] do
            continue
        let bx = block & 1
        let by = block >> 1
        if not result.nonZeroAc[block] do
            addDc4x4(result.reconstructed.buffer + by * 4 * 8 + bx * 4,
                     8, scaled[block * 16])
        else do
            addIdct4x4Scalar(result.reconstructed.buffer + by * 4 * 8 + bx * 4,
                             8, scaled.buffer + block * 16)
    }
}
