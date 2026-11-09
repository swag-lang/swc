//! Format: H.264/AVC intra luma quantization.
//! Supported: Progressive 8-bit Intra_16x16 luma and 4:2:0 chroma DC prediction at QP 0 through 51.
//! Not supported: Other intra prediction modes, entropy coding, and rate control.
//! Role: This file prepares intra levels and their local reconstruction.
//
#global namespace H264
#global private

using Core

private const IntraLuma4x4QuantFactor: [6, 3] u16 = [
    [13_107, 8_066, 5_243],
    [11_916, 7_490, 4_660],
    [10_082, 6_554, 4_194],
    [9_362, 5_825, 3_647],
    [8_192, 5_243, 3_355],
    [7_282, 4_559, 2_893]]

// Raster position to 4x4 zigzag scan position.
private const IntraLuma4x4ScanPosition: [16] u8 = [0, 1, 5, 6, 2, 4, 7, 12,
                                                    3, 8, 11, 13, 9, 10, 14, 15]

// DC levels follow zigzag order. Each AC group starts with an unused zero slot so it can
// be passed as `ac + block * 16 + 1` to the 15-coefficient CAVLC writer.
private struct IntraLuma16x16Result
{
    dc:            [16] s16
    ac:            [16 * 16] s16
    reconstructed: [16 * 16] u8
    nonZeroAc:     [16] u8
    cbpLuma:       u32          // Intra_16x16 syntax admits 0 or 15, never a partial pattern.
    prediction:    u8
}

// Four-point Hadamard in wide lanes: 8-bit residuals may put 65280 in the first
// forward DC coefficient, which the decoder's signed-16-bit inverse helper would clamp.
private func forwardIntraDc4x4(input: const [*] s32, output: [*] s32)
{
    var rows: [16] s32
    for row in 4'u64
    {
        let at = row * 4
        let c0 = input[at]
        let c1 = input[at + 1]
        let c2 = input[at + 2]
        let c3 = input[at + 3]
        let e0 = c0 + c2
        let e1 = c0 - c2
        let e2 = c1 - c3
        let e3 = c1 + c3
        rows[at] = e0 + e3
        rows[at + 1] = e1 + e2
        rows[at + 2] = e1 - e2
        rows[at + 3] = e0 - e3
    }
    for column in 4'u64
    {
        let c0 = rows[column]
        let c1 = rows[4 + column]
        let c2 = rows[8 + column]
        let c3 = rows[12 + column]
        let e0 = c0 + c2
        let e1 = c0 - c2
        let e2 = c1 - c3
        let e3 = c1 + c3
        output[column] = e0 + e3
        output[4 + column] = e1 + e2
        output[8 + column] = e1 - e2
        output[12 + column] = e0 - e3
    }
}

// Predicts Intra_16x16 DC from the already reconstructed left and top macroblocks,
// quantizes the sixteen 4x4 residuals and returns the picture those levels decode to.
// `source` addresses the source block; `reconstructedPlane` addresses the entire current
// luma plane so its neighbours at (`x`, `y`) are available. The caller writes this result
// into that plane only after choosing its coded macroblock syntax.
private func quantizeIntraLuma16x16(source: const [*] u8, sourceStride: u64,
                                    reconstructedPlane: const [*] u8,
                                    reconstructedStride, x, y: u64,
                                    hasLeft, hasTop: bool, qp: u32,
                                    result: *IntraLuma16x16Result)
{
    Swag.assert(qp <= 51)
    var sum = 0's32
    if hasLeft
    {
        for row in 16'u64 do
            sum += cast(s32, reconstructedPlane[(y + row) * reconstructedStride + x - 1])
    }
    if hasTop
    {
        for column in 16'u64 do
            sum += cast(s32, reconstructedPlane[(y - 1) * reconstructedStride + x + column])
    }
    var predictor = 128's32
    if hasLeft and hasTop do
        predictor = (sum + 16) >> 5
    elif hasLeft or hasTop do
        predictor = (sum + 8) >> 4
    result.prediction = cast(u8, predictor)
    result.cbpLuma = 0

    let qmod = cast(u64, qp % 6)
    let qdiv = qp / 6
    let qbits = 15 + qdiv
    // A flat source has sixteen equal forward DC values, so the 4x4 Hadamard
    // leaves only its first coefficient. The inverse also broadcasts one level.
    let sourceValue = source[0]
    var flatSource = true
    for row in 16'u64
    {
        for column in 16'u64 where source[row * sourceStride + column] != sourceValue
        {
            flatSource = false
            break
        }
        if not flatSource do
            break
    }
    if flatSource
    {
        let coefficient = 256 * (cast(s32, sourceValue) - predictor)
        let dcBits = qbits + 2
        let magnitude = (cast(s64, Math.abs(coefficient)) *
                         cast(s64, IntraLuma4x4QuantFactor[qmod, 0]) +
                         (1's64 << (dcBits - 1))) >> dcBits
        let level = cast(s16, coefficient < 0 ? -magnitude : magnitude)
        result.dc[0] = level
        for scan in 1'u64 until 16 do
            result.dc[scan] = 0
        for block in 16'u64 do
            result.nonZeroAc[block] = 0
        for scan in 256'u64 do
            result.ac[scan] = 0
        let dcScale = cast(s64, Dequant4Scale[qmod * 3]) * 16 << qdiv
        let dcValue = cast(s32, Math.clamp((cast(s64, level) * dcScale + 32) >> 6,
                                           -32768, 32767))
        let reconstructed = cast(u8, Math.clamp(predictor + ((dcValue + 32) >> 6),
                                                 0, 255))
        for index in 256'u64 do
            result.reconstructed[index] = reconstructed
        return
    }
    var rawDc: [16] s32
    var scaled: [16 * 16] s16
    for by in 4'u64
    {
        for bx in 4'u64
        {
            let block = by * 4 + bx
            let base = block * 16
            result.nonZeroAc[block] = 0
            result.ac[base] = 0
            var horizontal: [16] s32
            for row in 4'u64
            {
                let src = source + (by * 4 + row) * sourceStride + bx * 4
                let a0 = cast(s32, src[0]) - predictor
                let a1 = cast(s32, src[1]) - predictor
                let a2 = cast(s32, src[2]) - predictor
                let a3 = cast(s32, src[3]) - predictor
                let s0 = a0 + a3
                let s1 = a1 + a2
                let s2 = a1 - a2
                let s3 = a0 - a3
                horizontal[row * 4] = s0 + s1
                horizontal[row * 4 + 1] = 2 * s3 + s2
                horizontal[row * 4 + 2] = s0 - s1
                horizontal[row * 4 + 3] = s3 - 2 * s2
                for column in 4'u64 do
                    result.reconstructed[(by * 4 + row) * 16 + bx * 4 + column] =
                        cast(u8, predictor)
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
                    let factor = cast(s64, IntraLuma4x4QuantFactor[qmod, class])
                    let magnitude = (cast(s64, Math.abs(coefficient)) * factor +
                                     (1's64 << (qbits - 1))) >> qbits
                    Swag.assert(magnitude <= Swag.S16.Max)
                    let level = cast(s32, coefficient < 0 ? -magnitude : magnitude)
                    let scan = cast(u64, IntraLuma4x4ScanPosition[raster])
                    result.ac[base + scan] = cast(s16, level)
                    if level
                    {
                        result.nonZeroAc[block] += 1
                        result.cbpLuma = 15
                    }
                    let scale = cast(u32, Dequant4Scale[qmod * 3 + class]) * 16 << qdiv
                    scaled[base + column * 4 + row] = dequantLevel(level, scale, 4)
                }
            }
        }
    }

    var transformedDc: [16] s32
    forwardIntraDc4x4(rawDc.buffer, transformedDc.buffer)
    let dcBits = qbits + 2
    for scan in 16'u64
    {
        let raster = cast(u64, Zigzag4[scan])
        let coefficient = transformedDc[raster]
        let magnitude = (cast(s64, Math.abs(coefficient)) *
                         cast(s64, IntraLuma4x4QuantFactor[qmod, 0]) +
                         (1's64 << (dcBits - 1))) >> dcBits
        Swag.assert(magnitude <= Swag.S16.Max)
        result.dc[scan] = cast(s16, coefficient < 0 ? -magnitude : magnitude)
    }
    var inverseDc: [16] s16
    for scan in 16'u64 do
        inverseDc[cast(u64, Zigzag4[scan])] = result.dc[scan]
    hadamard4x4(inverseDc.buffer)
    let dcScale = cast(s64, Dequant4Scale[qmod * 3]) * 16 << qdiv
    for block in 16'u64
    {
        let dcValue = (cast(s64, inverseDc[block]) * dcScale + 32) >> 6
        scaled[block * 16] = cast(s16, Math.clamp(dcValue, -32768, 32767))
        let bx = block & 3
        let by = block >> 2
        addIdct4x4Scalar(result.reconstructed.buffer + by * 4 * 16 + bx * 4,
                         16, scaled.buffer + block * 16)
    }
}

// A constant source leaves only the four quadrant DC coefficients. This is the
// same 2x2 Hadamard, quantizer and inverse as the inter chroma DC path, without
// constructing four 4x4 forward transforms or their AC coefficients.
private func quantizeFlatIntraChroma8x8(sourceValue: u8, predictors: const [*] s32,
                                        lumaQp: u32, chromaQpOffset: s32,
                                        result: *InterChroma8x8Result)
{
    let qpIndex = cast(u64, Math.clamp(cast(s32, lumaQp) + chromaQpOffset, 0, 51))
    let qpc = cast(u32, ChromaQp[qpIndex])
    result.qpc = cast(u8, qpc)
    result.cbp = 0
    let qmod = cast(u64, qpc % 6)
    let qdiv = qpc / 6
    let dcBits = 16 + qdiv
    var rawDc: [4] s32
    for block in 4'u64
    {
        rawDc[block] = 16 * (cast(s32, sourceValue) - predictors[block])
        result.nonZeroAc[block] = 0
        for scan in 16'u64 do
            result.ac[block * 16 + scan] = 0
    }
    for row in 8'u64
    {
        for column in 8'u64
        {
            let block = (row >= 4 ? 2'u64 : 0'u64) + (column >= 4 ? 1'u64 : 0'u64)
            result.reconstructed[row * 8 + column] = cast(u8, predictors[block])
        }
    }
    let d0 = rawDc[0]
    let d1 = rawDc[1]
    let d2 = rawDc[2]
    let d3 = rawDc[3]
    let transformed: [4] s32 = [d0 + d1 + d2 + d3, d0 - d1 + d2 - d3,
                                 d0 + d1 - d2 - d3, d0 - d1 - d2 + d3]
    for index in 4'u64
    {
        let coefficient = transformed[index]
        let magnitude = (cast(s64, Math.abs(coefficient)) *
                         cast(s64, InterLuma4x4QuantFactor[qmod, 0]) +
                         (1's64 << (dcBits - 1))) >> dcBits
        let level = cast(s32, coefficient < 0 ? -magnitude : magnitude)
        result.dc[index] = cast(s16, level)
        if level do
            result.cbp = 1
    }
    if not result.cbp do
        return
    var inverseDc = result.dc
    hadamard2x2(inverseDc.buffer)
    let dcScale = cast(s64, Dequant4Scale[qmod * 3]) * 16 << qdiv
    var dc: [4] s32
    for block in 4'u64
    {
        let value = (cast(s64, inverseDc[block]) * dcScale) >> 5
        dc[block] = cast(s32, Math.clamp(value, -32768, 32767))
    }
    addDc8x8Quad(result.reconstructed.buffer, 8, dc[0], dc[1], dc[2], dc[3])
}

// Builds the four quadrant DC predictions of one intra chroma plane from already
// reconstructed neighbouring macroblocks, then reuses the inter 8x8 transform,
// quantizer and inverse. The default intra/inter scaling matrices are identical here.
// `sourceUv` addresses the target interleaved 8x8 block, while `reconstructedUv`
// addresses the whole current chroma plane. `x` and `y` are luma coordinates;
// `plane` is zero for Cb or one for Cr.
private func quantizeIntraChroma8x8(sourceUv: const [*] u8, sourceStride: u64,
                                    reconstructedUv: const [*] u8,
                                    reconstructedStride, x, y: u64, plane: u32,
                                    hasLeft, hasTop: bool, lumaQp: u32,
                                    chromaQpOffset: s32, result: *InterChroma8x8Result)
{
    Swag.assert(plane < 2)
    let lane = cast(u64, plane)
    var sumTopLeft = 0's32
    var sumTopRight = 0's32
    var sumBottomLeft = 0's32
    for index in 4'u64
    {
        if hasTop
        {
            let above = (y / 2 - 1) * reconstructedStride + x + lane
            sumTopLeft += cast(s32, reconstructedUv[above + index * 2])
            sumTopRight += cast(s32, reconstructedUv[above + (4 + index) * 2])
        }
        if hasLeft
        {
            let left = y / 2 * reconstructedStride + x - 2 + lane
            sumTopLeft += cast(s32, reconstructedUv[left + index * reconstructedStride])
            sumBottomLeft += cast(s32, reconstructedUv[left + (4 + index) * reconstructedStride])
        }
    }

    var dc0, dc1, dc2, dc3: s32
    if hasTop and hasLeft
    {
        dc0 = (sumTopLeft + 4) >> 3
        dc1 = (sumTopRight + 2) >> 2
        dc2 = (sumBottomLeft + 2) >> 2
        dc3 = (sumTopRight + sumBottomLeft + 4) >> 3
    }
    elif hasTop
    {
        dc0 = (sumTopLeft + 2) >> 2
        dc1 = (sumTopRight + 2) >> 2
        dc2 = dc0
        dc3 = dc1
    }
    elif hasLeft
    {
        dc0 = (sumTopLeft + 2) >> 2
        dc1 = dc0
        dc2 = (sumBottomLeft + 2) >> 2
        dc3 = dc2
    }
    else
    {
        dc0 = 128
        dc1 = 128
        dc2 = 128
        dc3 = 128
    }

    let predictors: [4] s32 = [dc0, dc1, dc2, dc3]
    let sourceValue = sourceUv[lane]
    var flatSource = true
    for row in 8'u64
    {
        for column in 8'u64 where
            sourceUv[row * sourceStride + column * 2 + lane] != sourceValue
        {
            flatSource = false
            break
        }
        if not flatSource do
            break
    }
    if flatSource
    {
        quantizeFlatIntraChroma8x8(sourceValue, predictors.buffer,
                                    lumaQp, chromaQpOffset, result)
        return
    }

    var prediction: [8 * 16] u8
    for row in 8'u64
    {
        for column in 8'u64
        {
            let quadrant = (row >= 4 ? 2'u32 : 0'u32) + (column >= 4 ? 1'u32 : 0'u32)
            prediction[row * 16 + column * 2 + lane] = cast(u8, predictors[quadrant])
        }
    }
    quantizeInterChroma8x8(sourceUv + lane,
                           prediction.buffer + lane, sourceStride, 16,
                           lumaQp, chromaQpOffset, result)
}
