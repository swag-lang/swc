//! Format: H.264/AVC constrained-baseline quantized picture coding.
//! Supported: Progressive 8-bit 4:2:0 I and P pictures, quarter-sample 16x16 motion, P-skip, Intra_16x16 and Intra_4x4 prediction in both, and CAVLC residuals at a fixed QP of 1 through 51, key pictures three steps finer.
//! Not supported: Macroblock partitions, several references, B pictures, CABAC, the 8x8 transform, and rate control.
//! Role: This file codes the pictures of a quantized encoder against its own decoded reference.
//
#global namespace H264
#global internal

using Core, Core.Math

// Forward quantizer factors by QP modulo six and coefficient position class.
const LossyQuantFactor: [6, 3] u16 = [
    [13_107, 8_066, 5_243],
    [11_916, 7_490, 4_660],
    [10_082, 6_554, 4_194],
    [9_362, 5_825, 3_647],
    [8_192, 5_243, 3_355],
    [7_282, 4_559, 2_893]]

// Raster coefficient position to 4x4 zigzag scan position.
const LossyScanPosition: [16] u8 = [0, 1, 5, 6, 2, 4, 7, 12, 3, 8, 11, 13, 9, 10, 14, 15]

// Column and row of each luma 4x4 block, in the order the syntax codes them.
const LossyBlockColumn: [16] u8 = [0, 1, 0, 1, 2, 3, 2, 3, 0, 1, 0, 1, 2, 3, 2, 3]
const LossyBlockRow:    [16] u8 = [0, 0, 1, 1, 0, 0, 1, 1, 2, 2, 3, 3, 2, 2, 3, 3]

// Cost of an isolated unit level by the run of zeros before it, as coefficient elimination
// weighs it: a lone small coefficient far down the scan costs more bits than it repairs.
const LossyRunScore: [16] u8 = [3, 2, 2, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

// Largest whole-sample excursion of a motion vector around its macroblock.
const LossySearchRange = 64's32

// Quantizer steps a key picture is coded finer than the pictures predicted from it.
const LossyKeyQpGain = 3's32

// Bits an intra macroblock of a predicted picture is taken to cost above an inter one.
const LossyIntraBits = 12'u32

// Bits sixteen Intra_4x4 blocks are taken to cost above one Intra_16x16 prediction.
const LossySmallBlocksBits = 12'u32

// Transformed distance under which the Intra_16x16 prediction of a predicted picture is kept untried against Intra_4x4.
const LossySmoothCost = 512'u32

// Width of the regions whose overall translation is estimated before their macroblocks are searched.
const LossyRegionWidth = 256'u64

// What a coded macroblock leaves for its neighbours to predict from.
struct LossyMb
{
    mvX:   s16     // Motion in quarter samples; zero for an intra macroblock.
    mvY:   s16
    inter: bool        // Predicted from the reference picture.
    coded: bool        // Already coded in this picture.
    modes: [16] u8     // Intra_4x4 mode of each block by raster position; DC for any other type.
}

// Quantized levels of one macroblock, in the layout CAVLC writes them.
struct LossyResidual
{
    luma:        [256] s16     // Sixteen blocks by raster position, sixteen zigzag levels each.
    lumaDc:      [16] s16      // Intra_16x16 DC levels in zigzag order.
    chromaDc:    [8] s16       // Two planes of four DC levels.
    chromaAc:    [128] s16     // Two planes of four blocks, sixteen zigzag levels each.
    lumaCount:   [16] u8       // Coded levels per luma block, DC left out for Intra_16x16.
    chromaCount: [8] u8        // Coded AC levels per chroma block.
    cbpLuma:     u32
    cbpChroma:   u32
}

// Codes quantized pictures against the reference a decoder rebuilds from them.
//
// The source is kept planar and padded to whole macroblocks, so a picture whose sides are not
// multiples of sixteen codes its last column and row like any other. Each picture is rebuilt
// in `frames`, with the very arithmetic of the decoder, and becomes the next reference.
struct LossyCoder
{
    frames:        [2] Frame
    currentIndex:  u32
    sourceY:       Array'u8
    sourceU:       Array'u8
    sourceV:       Array'u8
    priorY:        Array'u8
    priorU:        Array'u8
    priorV:        Array'u8
    hasPrior:      bool
    mbs:           Array'LossyMb
    priorMotion:   Array's16     // Motion of the previous picture, two components per macroblock.
    nonZero:       Array'u8
    chromaNonZero: Array'u8
    intraCbpCode:  [48] u8
    mbWidth:       u32
    mbHeight:      u32
    width:         s32
    height:        s32
    baseQp:        u32     // Quantizer of predicted pictures.
    qp:            u32     // Quantizer of the picture being coded.
    lambda:        s32
}

impl LossyCoder
{
    mtd create(width, height: s32, mbWidth, mbHeight, qp: u32)
    {
        .width    = width
        .height   = height
        .mbWidth  = mbWidth
        .mbHeight = mbHeight
        .baseQp   = qp
        .setPictureQp(qp)
        for &frame in .frames do
            frame.prepare(cast(s32, mbWidth), cast(s32, mbHeight), 1)

        let lumaSize   = cast(u64, mbWidth) * 16 * cast(u64, mbHeight) * 16
        let chromaSize = lumaSize / 4
        .sourceY.resize(lumaSize)
        .priorY.resize(lumaSize)
        for plane in [&.sourceU, &.sourceV, &.priorU, &.priorV] do
            plane.resize(chromaSize)

        let count = cast(u64, mbWidth) * mbHeight
        .mbs.resize(count)
        .priorMotion.resize(count * 2)
        .nonZero.resize(count * 16)
        .chromaNonZero.resize(count * 8)
        for code in 48'u64 do
            .intraCbpCode[GolombToIntraCbp[code]] = cast(u8, code)
    }

    // Sets the quantizer of the next picture and the weight of a bit against a unit of distance.
    mtd setPictureQp(qp: u32)
    {
        .qp     = qp
        .lambda = Math.max(1, cast(s32, Math.round(Math.pow(2.0, (cast(f64, qp) - 12) / 6))))
    }

    mtd current()->*Frame   => &.frames[.currentIndex]
    mtd reference()->*Frame => &.frames[1 - .currentIndex]

    mtd const lumaStride()->u64   => cast(u64, .mbWidth) * 16
    mtd const chromaStride()->u64 => cast(u64, .mbWidth) * 8

    // Copies the NV12 picture into padded planes, repeating its last column and row.
    mtd loadSource(frame: const *Nv12Frame)
    {
        let width   = cast(u64, .width)
        let height  = cast(u64, .height)
        let stride  = .lumaStride()
        let rows    = cast(u64, .mbHeight) * 16
        let luma    = frame.luma()
        let chroma  = frame.chroma()
        let targetY = .sourceY.storage()
        for row in rows
        {
            let line = targetY + row * stride
            Memory.copy(line, luma.buffer + Math.min(row, height - 1) * width, width)
            for column in width until stride do
                line[column] = line[width - 1]
        }

        let chromaStride = .chromaStride()
        let chromaWidth  = width / 2
        let chromaHeight = height / 2
        let targetU      = .sourceU.storage()
        let targetV      = .sourceV.storage()
        for row in rows / 2
        {
            let from  = chroma.buffer + Math.min(row, chromaHeight - 1) * width
            let lineU = targetU + row * chromaStride
            let lineV = targetV + row * chromaStride
            for column in chromaWidth
            {
                lineU[column] = from[column * 2]
                lineV[column] = from[column * 2 + 1]
            }

            for column in chromaWidth until chromaStride
            {
                lineU[column] = lineU[chromaWidth - 1]
                lineV[column] = lineV[chromaWidth - 1]
            }
        }
    }

    // Codes one picture into `packet`, one NAL per slice, and makes it the next reference.
    mtd encodeFrame(frame: const *Nv12Frame, key: bool, frameNumber, sliceCount: u32, packet: *Array'u8)
    {
        .loadSource(frame)

        // Everything until the next key picture is predicted from this one, and what does not
        // move keeps its precision for nothing: a key picture is worth a finer quantizer.
        .setPictureQp(key ? cast(u32, Math.max(cast(s32, .baseQp) - LossyKeyQpGain, 1)) : .baseQp)
        for &mb in .mbs
        {
            mb.mvX   = 0
            mb.mvY   = 0
            mb.inter = false
            mb.coded = false
            for &mode in mb.modes do
                mode[] = cast(u8, IntraDc)
        }

        Memory.clear(.nonZero.storage(), .nonZero.count)
        Memory.clear(.chromaNonZero.storage(), .chromaNonZero.count)

        var slices: Array'EncoderSlicePacket
        slices.resize(sliceCount)
        let coder = me
        let slots = slices.storage()
        if sliceCount == 1
        {
            coder.encodeSlice(key, frameNumber, 0, sliceCount, &slots[0].bytes)
        }
        else
        {
            parallel for |coder, key, frameNumber, sliceCount, slots| sliceIndex in cast(u64, sliceCount) do
                coder.encodeSlice(key, frameNumber, cast(u32, sliceIndex), sliceCount, &slots[sliceIndex].bytes)
        }

        for &slice in slices do
            packet.add(slice.bytes.toSlice())

        // The picture just rebuilt is what the next one predicts from, edges included.
        .current().extendEdges()
        for &mb, index in .mbs
        {
            .priorMotion[index * 2]     = mb.mvX
            .priorMotion[index * 2 + 1] = mb.mvY
        }

        .currentIndex = 1 - .currentIndex
        Core.swap(&.sourceY, &.priorY)
        Core.swap(&.sourceU, &.priorU)
        Core.swap(&.sourceV, &.priorV)
        .hasPrior = true
    }

    // One independently coded band of macroblock rows. Every spatial context restarts at its
    // first row, which is what lets the bands of a picture be coded at the same time.
    mtd encodeSlice(key: bool, frameNumber, sliceIndex, sliceCount: u32, packet: *Array'u8)
    {
        let firstRow = sliceIndex * .mbHeight / sliceCount
        let lastRow  = (sliceIndex + 1) * .mbHeight / sliceCount
        var bits: EncoderBits
        bits.unsigned(firstRow * .mbWidth)     // first_mb_in_slice.
        bits.unsigned(key ? 2 : 0)             // I or P slice.
        bits.unsigned(0)     // pic_parameter_set_id.
        bits.bits(key ? 0 : frameNumber, 8)
        if key
        {
            bits.unsigned(0)     // idr_pic_id.
            bits.bit(0)          // no_output_of_prior_pics_flag.
            bits.bit(0)          // long_term_reference_flag.
        }
        else
        {
            bits.bit(0)     // num_ref_idx_active_override_flag.
            bits.bit(0)     // ref_pic_list_modification_flag_l0.
            bits.bit(0)     // adaptive_ref_pic_marking_mode_flag.
        }

        bits.signed(cast(s32, .qp) - 26)     // slice_qp_delta: the whole slice keeps one QP.
        bits.unsigned(2)     // disable_deblocking_filter_idc: filter inside the slice only.
        bits.signed(0)       // slice_alpha_c0_offset_div2.
        bits.signed(0)       // slice_beta_offset_div2.

        // A scroll or a pan moves a whole area by one vector that no local search finds on fine
        // detail; each region of the slice proposes the translation its profiles show.
        var regions: Array'LossyRegionResult
        if not key
        {
            for region in (.lumaStride() + LossyRegionWidth - 1) / LossyRegionWidth do
                regions.add(.regionMotion(firstRow, lastRow, region))
        }

        var skipRun = 0'u32
        for mbY in firstRow until lastRow
        {
            for mbX in .mbWidth
            {
                if key do
                    .encodeIntraMb(&bits, mbX, mbY, firstRow, false)
                else do
                    .encodeInterMb(&bits, mbX, mbY, firstRow, regions[cast(u64, mbX) * 16 / LossyRegionWidth], &skipRun)
            }
        }

        if not key and skipRun do
            bits.unsigned(skipRun)
        bits.trailing()

        // Prediction inside the slice read the samples as they were decoded; the edges are
        // smoothed only now, as a decoder does before it keeps the picture as a reference.
        for mbY in firstRow until lastRow
        {
            for mbX in .mbWidth do
                .deblockMb(mbX, mbY, firstRow)
        }

        appendEncoderNal(packet, key ? 0x65 : 0x41, bits.bytes.toSlice())
    }

    #[Swag.Inline]
    mtd const mbIndex(mbX, mbY: u32)->u64 => cast(u64, mbY) * .mbWidth + mbX
}

// ---------------------------------------------------------------------------------------------
// Transform and quantization
// ---------------------------------------------------------------------------------------------

// Forward 4x4 core transform of `source` minus `prediction`, as raster coefficients.
func lossyForward4x4(source: const [*] u8, sourceStride: u64, prediction: const [*] u8, predictionStride: u64, coefficients: [*] s32)
{
    var horizontal: [16] s32
    for row in 4'u64
    {
        let src  = source + row * sourceStride
        let pred = prediction + row * predictionStride
        let a0   = cast(s32, src[0]) - cast(s32, pred[0])
        let a1   = cast(s32, src[1]) - cast(s32, pred[1])
        let a2   = cast(s32, src[2]) - cast(s32, pred[2])
        let a3   = cast(s32, src[3]) - cast(s32, pred[3])
        let s0   = a0 + a3
        let s1   = a1 + a2
        let s2   = a1 - a2
        let s3   = a0 - a3
        horizontal[row * 4]     = s0 + s1
        horizontal[row * 4 + 1] = 2 * s3 + s2
        horizontal[row * 4 + 2] = s0 - s1
        horizontal[row * 4 + 3] = s3 - 2 * s2
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
        coefficients[column]      = s0 + s1
        coefficients[4 + column]  = 2 * s3 + s2
        coefficients[8 + column]  = s0 - s1
        coefficients[12 + column] = s3 - 2 * s2
    }
}

// Four-point Hadamard in wide lanes: 8-bit residuals may put 65280 in the first
// forward DC coefficient, which the decoder's signed-16-bit inverse helper would clamp.
func forwardIntraDc4x4(input: const [*] s32, output: [*] s32)
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
        rows[at]     = e0 + e3
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
        output[column]      = e0 + e3
        output[4 + column]  = e1 + e2
        output[8 + column]  = e1 - e2
        output[12 + column] = e0 - e3
    }
}

// Quantizes raster `coefficients` from position `first` into zigzag `levels`, and writes what a
// decoder scales them back to into `scaled`, in the column-major order of the inverse transform.
// `rounding` is the dead zone as a fraction of one step, out of 65536. Returns the level count.
func lossyQuantize4x4(coefficients: const [*] s32, first: u64, qp: u32, rounding: s64, levels, scaled: [*] s16)->u32
{
    let qmod   = cast(u64, qp % 6)
    let qdiv   = qp / 6
    let qbits  = 15 + qdiv
    let offset = (rounding << qbits) >> 16
    var count  = 0'u32
    for raster in first until 16
    {
        let row         = raster >> 2
        let column      = raster & 3
        let class       = (row & 1) + (column & 1)
        let coefficient = coefficients[raster]
        let magnitude   = (cast(s64, Math.abs(coefficient)) * cast(s64, LossyQuantFactor[qmod, class]) + offset) >> qbits
        let level       = cast(s32, coefficient < 0 ? -magnitude : magnitude)
        levels[LossyScanPosition[raster]] = cast(s16, level)
        if level do
            count += 1
        let scale = cast(u32, Dequant4Scale[qmod * 3 + class]) * 16 << qdiv
        scaled[column * 4 + row] = dequantLevel(level, scale, 4)
    }

    return count
}

// Returns the largest sum of absolute differences of a 4x4 block whose every coefficient is sure
// to quantize to zero. A coefficient is a sum of the differences weighted by one, two or four
// according to its position, so it cannot exceed that weight times their absolute sum.
func lossyZeroBound(qp: u32, rounding: s64)->u32
{
    let qmod  = cast(u64, qp % 6)
    let qbits = 15 + qp / 6
    let limit = (1's64 << qbits) - ((rounding << qbits) >> 16) - 1
    var bound = Swag.S64.Max
    for class in 3'u64 do
        bound = Math.min(bound, limit / (cast(s64, LossyQuantFactor[qmod, class]) << class))
    return cast(u32, Math.max(bound, 0))
}

// Sum of the differences of a 4x4 block, which is its first coefficient, and of their absolute values.
#[Swag.Inline]
func lossySums4(a: const [*] u8, aStride: u64, b: const [*] u8, bStride: u64, sum: *s32)->u32
{
    var total    = 0's32
    var absolute = 0'u32
    for row in 4'u64
    {
        let pa = a + row * aStride
        let pb = b + row * bStride
        for column in 4'u64
        {
            let delta = cast(s32, pa[column]) - cast(s32, pb[column])
            total    += delta
            absolute += cast(u32, Math.abs(delta))
        }
    }

    sum[] = total
    return absolute
}

// Rounding of intra and inter levels: a third and a sixth of a quantization step.
const LossyIntraRounding = 21_845's64
const LossyInterRounding = 10_923's64

// Returns what eliminating a block of levels would lose, nine or more when it must stay.
func lossyBlockScore(levels: const [*] s16, first: u64)->u32
{
    var score = 0'u32
    var run   = 0'u32
    for scan in first until 16
    {
        let level = levels[scan]
        if not level
        {
            run += 1
            continue
        }

        if level > 1 or level < -1 do
            return 9
        score += LossyRunScore[run]
        run   = 0
    }

    return score
}

// A chroma plane without AC has one flat correction per 4x4 block. Some DC levels only
// change fractions discarded by the inverse transform. Remove them without changing a sample.
func lossyOptimizeChromaDc(levels: [*] s16, scale: s64)
{
    // At this scale a one-level change moves at least one sample, beyond the rounding cell.
    if scale >= 2048 do
        return
    if levels[0] == 0 and levels[1] == 0 and levels[2] == 0 and levels[3] == 0 do
        return

    func samples(levels: const [*] s16, scale: s64)->[4] s32
    {
        let a = cast(s32, levels[0]) + cast(s32, levels[1])
        let b = cast(s32, levels[0]) - cast(s32, levels[1])
        let c = cast(s32, levels[2]) + cast(s32, levels[3])
        let d = cast(s32, levels[2]) - cast(s32, levels[3])
        var result:  #returntype
        let inverse: [4] s32 = [a + c, b + d, a - c, b - d]
        for block in 4'u64 do
            result[block] = cast(s32, (((cast(s64, inverse[block]) * scale) >> 5) + 32) >> 6)
        return result
    }

    let target = samples(levels, scale)

    // Later nonzero coefficients also cost zero-run syntax. Try those first.
    for index in 4'u64
    {
        let scan = 3 - index
        while levels[scan]
        {
            let saved = levels[scan]
            levels[scan] += saved < 0 ? 1's16 : -1's16
            let trial = samples(levels, scale)
            if trial[0] != target[0] or
               trial[1] != target[1] or
               trial[2] != target[2] or
               trial[3] != target[3]
            {
                levels[scan] = saved
                break
            }
        }
    }
}

impl LossyCoder
{
    // Codes the sixteen luma blocks of a macroblock whose prediction stands in the current
    // picture, and leaves the decoded samples in its place. Each block carries its own DC.
    mtd codeLumaBlocks(mbX, mbY: u32, rounding: s64, eliminate: bool, residual: *LossyResidual)
    {
        let frame  = .current()
        let stride = frame.strideLuma
        let pixels = frame.pixLuma(cast(s32, mbX) * 16, cast(s32, mbY) * 16)
        let source = .sourceY.storage() + cast(u64, mbY) * 16 * .lumaStride() + cast(u64, mbX) * 16
        var scaled: [256] s16
        var scores: [4] u32
        let quiet  = lossyZeroBound(.qp, rounding)

        for block in 16'u64
        {
            let bx = block & 3
            let by = block >> 2

            // Most blocks of a well predicted picture differ too little to leave a single level:
            // their transform is not worth computing.
            var first: s32
            if lossySums4(source + by * 4 * .lumaStride() + bx * 4, .lumaStride(), pixels + by * 4 * stride + bx * 4, stride, &first) <= quiet
            {
                residual.lumaCount[block] = 0
                Memory.clear(residual.luma.buffer + block * 16, 16 * #sizeof(s16))
                continue
            }

            var coefficients: [16] s32
            lossyForward4x4(source + by * 4 * .lumaStride() + bx * 4, .lumaStride(), pixels + by * 4 * stride + bx * 4, stride, coefficients.buffer)
            let levels = residual.luma.buffer + block * 16
            residual.lumaCount[block] = cast(u8, lossyQuantize4x4(coefficients.buffer, 0, .qp, rounding, levels, scaled.buffer + block * 16))
            if residual.lumaCount[block] do
                scores[(by >> 1) * 2 + (bx >> 1)] += lossyBlockScore(levels, 0)
        }

        // A quadrant, or the whole macroblock, holding nothing but a few stray unit levels reads
        // the same without them and costs far fewer bits.
        var total = scores[0] + scores[1] + scores[2] + scores[3]
        residual.cbpLuma = 0
        for quad in 4'u64
        {
            let drop = eliminate and (scores[quad] < 4 or total < 6)
            for cell in 4'u64
            {
                let block = ((quad >> 1) * 2 + (cell >> 1)) * 4 + (quad & 1) * 2 + (cell & 1)
                if drop and residual.lumaCount[block]
                {
                    residual.lumaCount[block] = 0
                    for scan in 16'u64 do
                        residual.luma[block * 16 + scan] = 0
                }

                if residual.lumaCount[block] do
                    residual.cbpLuma |= 1'u32 << cast(u32, quad)
            }
        }

        discard total
        for block in 16'u64 where residual.lumaCount[block]
        {
            let bx = block & 3
            let by = block >> 2
            addIdct4x4(pixels + by * 4 * stride + bx * 4, stride, scaled.buffer + block * 16)
        }
    }

    // Codes the luma of an Intra_16x16 macroblock: sixteen AC blocks around one shared DC block.
    mtd codeLuma16(mbX, mbY: u32, residual: *LossyResidual)
    {
        let frame  = .current()
        let stride = frame.strideLuma
        let pixels = frame.pixLuma(cast(s32, mbX) * 16, cast(s32, mbY) * 16)
        let source = .sourceY.storage() + cast(u64, mbY) * 16 * .lumaStride() + cast(u64, mbX) * 16
        var scaled: [256] s16
        var rawDc:  [16] s32

        residual.cbpLuma = 0
        for block in 16'u64
        {
            let bx = block & 3
            let by = block >> 2
            var coefficients: [16] s32
            lossyForward4x4(source + by * 4 * .lumaStride() + bx * 4, .lumaStride(), pixels + by * 4 * stride + bx * 4, stride, coefficients.buffer)
            rawDc[block] = coefficients[0]
            let levels = residual.luma.buffer + block * 16
            levels[0] = 0
            residual.lumaCount[block] = cast(u8, lossyQuantize4x4(coefficients.buffer, 1, .qp, LossyIntraRounding, levels, scaled.buffer + block * 16))
            if residual.lumaCount[block] do
                residual.cbpLuma = 15
        }

        let qmod   = cast(u64, .qp % 6)
        let qdiv   = .qp / 6
        let dcBits = 17 + qdiv
        var transformed: [16] s32
        forwardIntraDc4x4(rawDc.buffer, transformed.buffer)
        var inverse: [16] s16
        for scan in 16'u64
        {
            let raster      = cast(u64, Zigzag4[scan])
            let coefficient = transformed[raster]
            let magnitude   = (cast(s64, Math.abs(coefficient)) * cast(s64, LossyQuantFactor[qmod, 0]) + ((LossyIntraRounding << dcBits) >> 16)) >> dcBits
            residual.lumaDc[scan] = cast(s16, coefficient < 0 ? -magnitude : magnitude)
            inverse[raster]       = residual.lumaDc[scan]
        }

        hadamard4x4(inverse.buffer)
        let dcScale = cast(s64, Dequant4Scale[qmod * 3]) * 16 << qdiv
        for block in 16'u64
        {
            let dcValue = (cast(s64, inverse[block]) * dcScale + 32) >> 6
            scaled[block * 16] = cast(s16, Math.clamp(dcValue, -32768, 32767))
            if not scaled[block * 16] and not residual.lumaCount[block] do
                continue
            let bx = block & 3
            let by = block >> 2
            addIdct4x4(pixels + by * 4 * stride + bx * 4, stride, scaled.buffer + block * 16)
        }
    }

    // Codes both chroma planes of a macroblock whose prediction stands in the current picture.
    mtd codeChroma(mbX, mbY: u32, rounding: s64, residual: *LossyResidual)
    {
        let frame  = .current()
        let stride = frame.strideChroma
        let qpc    = cast(u32, ChromaQp[.qp])
        let qmod   = cast(u64, qpc % 6)
        let qdiv   = qpc / 6
        let dcBits = 16 + qdiv
        var scaled: [128] s16
        var anyDc  = false
        var anyAc  = false
        let quiet  = lossyZeroBound(qpc, rounding)

        for plane in 2'u32
        {
            let pixels  = frame.pixChroma(plane, cast(s32, mbX) * 8, cast(s32, mbY) * 8)
            let plane64 = cast(u64, plane)
            let source  = (plane == 0 ? .sourceU.storage() : .sourceV.storage()) + cast(u64, mbY) * 8 * .chromaStride() + cast(u64, mbX) * 8
            var rawDc: [4] s32
            var planeAc = false
            for block in 4'u64
            {
                let bx     = block & 1
                let by     = block >> 1
                let at     = plane64 * 4 + block
                let levels = residual.chromaAc.buffer + at * 16
                if lossySums4(source + by * 4 * .chromaStride() + bx * 4, .chromaStride(), pixels + by * 4 * stride + bx * 4, stride, &rawDc[block]) <= quiet
                {
                    residual.chromaCount[at] = 0
                    Memory.clear(levels, 16 * #sizeof(s16))
                    continue
                }

                var coefficients: [16] s32
                lossyForward4x4(source + by * 4 * .chromaStride() + bx * 4, .chromaStride(), pixels + by * 4 * stride + bx * 4, stride, coefficients.buffer)
                rawDc[block] = coefficients[0]
                levels[0]    = 0
                residual.chromaCount[at] = cast(u8, lossyQuantize4x4(coefficients.buffer, 1, qpc, rounding, levels, scaled.buffer + at * 16))
                if residual.chromaCount[at] do
                    planeAc = true
            }

            let transformed: [4] s32 = [rawDc[0] + rawDc[1] + rawDc[2] + rawDc[3],
                                        rawDc[0] - rawDc[1] + rawDc[2] - rawDc[3],
                                        rawDc[0] + rawDc[1] - rawDc[2] - rawDc[3],
                                        rawDc[0] - rawDc[1] - rawDc[2] + rawDc[3]]
            var inverse: [4] s16
            for index in 4'u64
            {
                let coefficient = transformed[index]
                let magnitude   = (cast(s64, Math.abs(coefficient)) * cast(s64, LossyQuantFactor[qmod, 0]) + ((rounding << dcBits) >> 16)) >> dcBits
                let level       = cast(s16, coefficient < 0 ? -magnitude : magnitude)
                residual.chromaDc[plane64 * 4 + index] = level
            }

            let dcScale = cast(s64, Dequant4Scale[qmod * 3]) * 16 << qdiv
            let dc      = residual.chromaDc.buffer + plane64 * 4
            if not planeAc do
                lossyOptimizeChromaDc(dc, dcScale)
            anyAc = anyAc or planeAc
            for index in 4'u64
            {
                inverse[index] = dc[index]
                anyDc = anyDc or dc[index] != 0
            }

            hadamard2x2(inverse.buffer)
            for block in 4'u64
            {
                let dcValue = (cast(s64, inverse[block]) * dcScale) >> 5
                scaled[(plane64 * 4 + block) * 16] = cast(s16, Math.clamp(dcValue, -32768, 32767))
            }
        }

        residual.cbpChroma = anyAc ? 2 : (anyDc ? 1 : 0)
        if not residual.cbpChroma do
            return
        for plane in 2'u32
        {
            let pixels = frame.pixChroma(plane, cast(s32, mbX) * 8, cast(s32, mbY) * 8)
            for block in 4'u64
            {
                let at = cast(u64, plane) * 4 + block
                if not scaled[at * 16] and not residual.chromaCount[at] do
                    continue
                addIdct4x4(pixels + (block >> 1) * 4 * stride + (block & 1) * 4, stride, scaled.buffer + at * 16)
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Residual syntax
// ---------------------------------------------------------------------------------------------

impl LossyCoder
{
    mtd const lumaCountAt(mbX, mbY, bx, by: u32)->u32 => .nonZero[.mbIndex(mbX, mbY) * 16 + by * 4 + bx]

    // Returns the CAVLC context of a luma block: the mean count of its left and top neighbours.
    mtd const lumaContext(mbX, mbY, bx, by, firstRow: u32)->u32
    {
        let hasLeft = bx > 0 or mbX > 0
        let hasTop  = by > 0 or mbY > firstRow
        var left    = 0'u32
        var top     = 0'u32
        if bx > 0 do
            left = .lumaCountAt(mbX, mbY, bx - 1, by)
        elif mbX > 0 do
            left = .lumaCountAt(mbX - 1, mbY, 3, by)
        if by > 0 do
            top = .lumaCountAt(mbX, mbY, bx, by - 1)
        elif mbY > firstRow do
            top = .lumaCountAt(mbX, mbY - 1, bx, 3)
        return hasLeft and hasTop ? (left + top + 1) / 2 : left + top
    }

    mtd const chromaCountAt(mbX, mbY, plane, bx, by: u32)->u32 => .chromaNonZero[.mbIndex(mbX, mbY) * 8 + plane * 4 + by * 2 + bx]

    mtd const chromaContext(mbX, mbY, plane, bx, by, firstRow: u32)->u32
    {
        let hasLeft = bx > 0 or mbX > 0
        let hasTop  = by > 0 or mbY > firstRow
        var left    = 0'u32
        var top     = 0'u32
        if bx > 0 do
            left = .chromaCountAt(mbX, mbY, plane, bx - 1, by)
        elif mbX > 0 do
            left = .chromaCountAt(mbX - 1, mbY, plane, 1, by)
        if by > 0 do
            top = .chromaCountAt(mbX, mbY, plane, bx, by - 1)
        elif mbY > firstRow do
            top = .chromaCountAt(mbX, mbY - 1, plane, bx, 1)
        return hasLeft and hasTop ? (left + top + 1) / 2 : left + top
    }

    // Writes the luma blocks the coded block pattern announces, each with its own DC.
    mtd writeLumaBlocks(bits: *EncoderBits, mbX, mbY, firstRow: u32, residual: *LossyResidual)
    {
        for index in 16'u32
        {
            let bx    = cast(u32, LossyBlockColumn[index])
            let by    = cast(u32, LossyBlockRow[index])
            let block = cast(u64, by * 4 + bx)
            let at    = .mbIndex(mbX, mbY) * 16 + block
            if residual.cbpLuma & (1'u32 << (index >> 2)) == 0
            {
                .nonZero[at] = 0
                continue
            }

            discard bits.residual4(residual.luma.buffer + block * 16, .lumaContext(mbX, mbY, bx, by, firstRow))
            .nonZero[at] = residual.lumaCount[block]
        }
    }

    // Writes the DC block of an Intra_16x16 macroblock, then its AC blocks when any is coded.
    mtd writeLuma16(bits: *EncoderBits, mbX, mbY, firstRow: u32, residual: *LossyResidual)
    {
        discard bits.residual4(residual.lumaDc.buffer, .lumaContext(mbX, mbY, 0, 0, firstRow))
        for index in 16'u32
        {
            let bx    = cast(u32, LossyBlockColumn[index])
            let by    = cast(u32, LossyBlockRow[index])
            let block = cast(u64, by * 4 + bx)
            let at    = .mbIndex(mbX, mbY) * 16 + block
            if not residual.cbpLuma
            {
                .nonZero[at] = 0
                continue
            }

            discard bits.residual15(residual.luma.buffer + block * 16 + 1, .lumaContext(mbX, mbY, bx, by, firstRow))
            .nonZero[at] = residual.lumaCount[block]
        }
    }

    mtd writeChroma(bits: *EncoderBits, mbX, mbY, firstRow: u32, residual: *LossyResidual)
    {
        if not residual.cbpChroma do
            return
        for plane in 2'u64 do
            discard bits.chromaDc(residual.chromaDc.buffer + plane * 4)
        if residual.cbpChroma < 2 do
            return
        for plane in 2'u32
        {
            for block in 4'u32
            {
                let at = cast(u64, plane * 4 + block)
                discard bits.residual15(residual.chromaAc.buffer + at * 16 + 1, .chromaContext(mbX, mbY, plane, block & 1, block >> 1, firstRow))
                .chromaNonZero[.mbIndex(mbX, mbY) * 8 + at] = residual.chromaCount[at]
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Deblocking
// ---------------------------------------------------------------------------------------------

impl LossyCoder
{
    // Returns the filter strength of the edge between two luma 4x4 blocks, section 8.7.2.1.
    mtd const edgeStrength(p, q: const *LossyMb, pCount, qCount: u8, mbEdge: bool)->u32
    {
        if not p.inter or not q.inter do
            return mbEdge ? 4 : 3
        if pCount or qCount do
            return 2
        if Math.abs(cast(s32, p.mvX) - cast(s32, q.mvX)) >= 4 or Math.abs(cast(s32, p.mvY) - cast(s32, q.mvY)) >= 4 do
            return 1
        return 0
    }

    // Smooths the block edges of one macroblock in place: the vertical ones, then the horizontal
    // ones, never across the first row of the slice.
    mtd deblockMb(mbX, mbY, firstRow: u32)
    {
        let frame  = .current()
        let index  = .mbIndex(mbX, mbY)
        let mb     = &.mbs[index]
        let counts = .nonZero.storage() + index * 16
        let qpc    = cast(u64, ChromaQp[.qp])
        let alpha  = cast(s32, DeblockAlpha[.qp])
        let beta   = cast(s32, DeblockBeta[.qp])
        let cAlpha = cast(s32, DeblockAlpha[qpc])
        let cBeta  = cast(s32, DeblockBeta[qpc])
        let x      = cast(s32, mbX) * 16
        let y      = cast(s32, mbY) * 16

        for edge in 4'u32
        {
            if edge == 0 and mbX == 0 do
                continue
            let other       = edge == 0 ? &.mbs[index - 1] : mb
            let otherCounts = edge == 0 ? .nonZero.storage() + (index - 1) * 16 : counts
            var strengths: EdgeStrength
            var filtered    = false
            for row in 4'u32
            {
                let q = counts[row * 4 + edge]
                let p = edge == 0 ? otherCounts[row * 4 + 3] : otherCounts[row * 4 + edge - 1]
                strengths.bs[row] = .edgeStrength(other, mb, p, q, edge == 0)
                filtered = filtered or strengths.bs[row] != 0
            }

            if not filtered do
                continue
            if alpha and beta do
                filterLumaVertical(frame.pixLuma(x + cast(s32, edge) * 4, y), frame.strideLuma, &strengths, cast(s32, .qp), alpha, beta)
            if (edge == 0 or edge == 2) and cAlpha and cBeta
            {
                let weak = strengths.bs[0] < 4 and
                           strengths.bs[1] < 4 and
                           strengths.bs[2] < 4 and
                           strengths.bs[3] < 4
                for plane in 2'u32
                {
                    let pix = frame.pixChroma(plane, x / 2 + cast(s32, edge) * 2, y / 2)
                    if weak do
                        filterChromaWeakVertical(pix, frame.strideChroma, &strengths, cast(s32, qpc), cAlpha, cBeta)
                    else do
                        filterChromaStrongVertical(pix, frame.strideChroma, &strengths, cast(s32, qpc), cAlpha, cBeta)
                }
            }
        }

        for edge in 4'u32
        {
            if edge == 0 and mbY == firstRow do
                continue
            let above       = edge == 0 ? index - .mbWidth : index
            let other       = edge == 0 ? &.mbs[above] : mb
            let otherCounts = edge == 0 ? .nonZero.storage() + above * 16 : counts
            var strengths: EdgeStrength
            var filtered    = false
            for column in 4'u32
            {
                let q = counts[edge * 4 + column]
                let p = edge == 0 ? otherCounts[12 + column] : otherCounts[(edge - 1) * 4 + column]
                strengths.bs[column] = .edgeStrength(other, mb, p, q, edge == 0)
                filtered = filtered or strengths.bs[column] != 0
            }

            if not filtered do
                continue
            let weak = strengths.bs[0] < 4 and
                       strengths.bs[1] < 4 and
                       strengths.bs[2] < 4 and
                       strengths.bs[3] < 4
            if alpha and beta
            {
                let pix = frame.pixLuma(x, y + cast(s32, edge) * 4)
                if weak do
                    filterLumaWeakHorizontal(pix, frame.strideLuma, &strengths, cast(s32, .qp), alpha, beta)
                else do
                    filterLumaStrongHorizontal(pix, frame.strideLuma, &strengths, cast(s32, .qp), alpha, beta)
            }

            if (edge == 0 or edge == 2) and cAlpha and cBeta
            {
                for plane in 2'u32
                {
                    let pix = frame.pixChroma(plane, x / 2, y / 2 + cast(s32, edge) * 2)
                    if weak do
                        filterChromaWeakHorizontal(pix, frame.strideChroma, &strengths, cast(s32, qpc), cAlpha, cBeta)
                    else do
                        filterChromaStrongHorizontal(pix, frame.strideChroma, &strengths, cast(s32, qpc), cAlpha, cBeta)
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Intra prediction
// ---------------------------------------------------------------------------------------------

// Sum of absolute differences of a 16-wide block.
func lossySad16(a: const [*] u8, aStride: u64, b: const [*] u8, bStride: u64, rows: u64)->u32
{
    var sum = 0'u32
    for row in rows do
        sum += Simd.sumAbsoluteDifferences(Simd.load(a + row * aStride), Simd.load(b + row * bStride))
    return sum
}

// Exact SAD below a strict winner bound, or the bound itself when this candidate cannot win.
func lossySad16Below(a: const [*] u8, aStride: u64, b: const [*] u8, bStride: u64, rows: u64, bound: u32)->u32
{
    var sum = 0'u32
    for row in rows
    {
        sum += Simd.sumAbsoluteDifferences(Simd.load(a + row * aStride), Simd.load(b + row * bStride))
        if sum >= bound do
            return bound
    }

    return sum
}

// Sum of the absolute Hadamard coefficients of the difference of two 16x16 blocks, halved. It
// follows the bits a residual costs once transformed far closer than a plain difference does: a
// shift of brightness lands in one coefficient per block, and noise spreads over all of them.
func lossySatd16(a: const [*] u8, aStride: u64, b: const [*] u8, bStride: u64)->u32
{
    let ones: Simd.S16x8 = Simd.splat(1's16)
    let alternate        = cast(Simd.S16x8, [1's16, -1, 1, -1, 1, -1, 1, -1])
    var sum              = 0'u32
    for band in 4'u64
    {
        // Four rows of differences, eight columns to a vector: the vertical half of the
        // transform is plain lane arithmetic.
        var delta: [8] Simd.S16x8
        for row in 4'u64
        {
            let va = Simd.load(a + (band * 4 + row) * aStride)
            let vb = Simd.load(b + (band * 4 + row) * bStride)
            delta[row]     = cast #bit(Simd.S16x8, Simd.widenLow(va)) - cast #bit(Simd.S16x8, Simd.widenLow(vb))
            delta[4 + row] = cast #bit(Simd.S16x8, Simd.widenHigh(va)) - cast #bit(Simd.S16x8, Simd.widenHigh(vb))
        }

        for half in 2'u64
        {
            let s0 = delta[half * 4] + delta[half * 4 + 1]
            let s1 = delta[half * 4] - delta[half * 4 + 1]
            let s2 = delta[half * 4 + 2] + delta[half * 4 + 3]
            let s3 = delta[half * 4 + 2] - delta[half * 4 + 3]
            let lines: [4] Simd.S16x8 = [s0 + s2, s1 + s3, s0 - s2, s1 - s3]
            for line in 4'u64
            {
                // The horizontal half: pair sums and pair differences, then |x + y| + |x - y|,
                // which is twice the larger of |x| and |y|.
                var pairs: [8] s32
                Simd.store(pairs.buffer, Simd.mulAddPairs(lines[line], ones))
                Simd.store(pairs.buffer + 4, Simd.mulAddPairs(lines[line], alternate))
                for pair in 4'u64 do
                    sum += cast(u32, Math.max(Math.abs(pairs[pair * 2]), Math.abs(pairs[pair * 2 + 1])))
            }
        }
    }

    return sum
}

// Sum of the absolute Hadamard coefficients of the difference of two 4x4 blocks, halved.
func lossySatd4(a: const [*] u8, aStride: u64, b: const [*] u8, bStride: u64)->u32
{
    var rows: [16] s32
    for row in 4'u64
    {
        let pa = a + row * aStride
        let pb = b + row * bStride
        let d0 = cast(s32, pa[0]) - cast(s32, pb[0])
        let d1 = cast(s32, pa[1]) - cast(s32, pb[1])
        let d2 = cast(s32, pa[2]) - cast(s32, pb[2])
        let d3 = cast(s32, pa[3]) - cast(s32, pb[3])
        let s0 = d0 + d1
        let s1 = d0 - d1
        let s2 = d2 + d3
        let s3 = d2 - d3
        rows[row * 4]     = s0 + s2
        rows[row * 4 + 1] = s1 + s3
        rows[row * 4 + 2] = s0 - s2
        rows[row * 4 + 3] = s1 - s3
    }

    var sum = 0'u32
    for column in 4'u64
    {
        let s0 = rows[column] + rows[4 + column]
        let s1 = rows[column] - rows[4 + column]
        let s2 = rows[8 + column] + rows[12 + column]
        let s3 = rows[8 + column] - rows[12 + column]
        sum += cast(u32, Math.abs(s0 + s2) + Math.abs(s1 + s3) + Math.abs(s0 - s2) + Math.abs(s1 - s3))
    }

    return sum / 2
}

// Sum of absolute differences of a block narrower than a vector.
func lossySadSmall(a: const [*] u8, aStride: u64, b: const [*] u8, bStride: u64, width, rows: u64)->u32
{
    var sum = 0'u32
    for row in rows
    {
        let lineA = a + row * aStride
        let lineB = b + row * bStride
        for column in width do
            sum += cast(u32, Math.abs(cast(s32, lineA[column]) - cast(s32, lineB[column])))
    }

    return sum
}

func lossySadSmallBelow(a: const [*] u8, aStride: u64, b: const [*] u8, bStride: u64, width, rows: u64, bound: u32)->u32
{
    var sum = 0'u32
    for row in rows
    {
        let lineA = a + row * aStride
        let lineB = b + row * bStride
        for column in width
        {
            sum += cast(u32, Math.abs(cast(s32, lineA[column]) - cast(s32, lineB[column])))
            if sum >= bound do
                return bound
        }
    }

    return sum
}

impl LossyCoder
{
    // Predicts the luma of a macroblock in each Intra_16x16 mode its neighbours allow and leaves
    // the closest in the current picture. Returns its transformed distance to the source.
    mtd predictLuma16(mbX, mbY, firstRow: u32, bestMode: *u32)->u32
    {
        let frame   = .current()
        let pixels  = frame.pixLuma(cast(s32, mbX) * 16, cast(s32, mbY) * 16)
        let source  = .sourceY.storage() + cast(u64, mbY) * 16 * .lumaStride() + cast(u64, mbX) * 16
        let hasLeft = mbX > 0
        let hasTop  = mbY > firstRow
        var best    = Swag.U32.Max
        var last    = Intra16Dc
        bestMode[] = Intra16Dc
        for mode in [Intra16Dc, Intra16Vertical, Intra16Horizontal, Intra16Plane]
        {
            if (mode == Intra16Vertical and not hasTop) or
               (mode == Intra16Horizontal and not hasLeft) or
               (mode == Intra16Plane and not (hasTop and hasLeft)) do
                continue
            intraPredict16x16(mode, pixels, frame.strideLuma, hasLeft, hasTop)
            last = mode
            let distance = lossySatd16(source, .lumaStride(), pixels, frame.strideLuma)
            if distance < best
            {
                best       = distance
                bestMode[] = mode
            }
        }

        if last != bestMode[] do
            intraPredict16x16(bestMode[], pixels, frame.strideLuma, hasLeft, hasTop)
        return best
    }

    // Predicts both chroma planes in the mode closest to the source and returns that mode.
    mtd predictChroma(mbX, mbY, firstRow: u32)->u32
    {
        let frame    = .current()
        let hasLeft  = mbX > 0
        let hasTop   = mbY > firstRow
        let offset   = cast(u64, mbY) * 8 * .chromaStride() + cast(u64, mbX) * 8
        var best     = Swag.U32.Max
        var bestMode = IntraChromaDc
        var last     = IntraChromaDc
        for mode in [IntraChromaDc, IntraChromaHorizontal, IntraChromaVertical, IntraChromaPlane]
        {
            if (mode == IntraChromaHorizontal and not hasLeft) or
               (mode == IntraChromaVertical and not hasTop) or
               (mode == IntraChromaPlane and not (hasTop and hasLeft)) do
                continue
            var distance = 0'u32
            for plane in 2'u32
            {
                let pixels = frame.pixChroma(plane, cast(s32, mbX) * 8, cast(s32, mbY) * 8)
                intraPredictChroma(mode, pixels, frame.strideChroma, hasLeft, hasTop)
                distance += lossySadSmall((plane == 0 ? .sourceU.storage() : .sourceV.storage()) + offset, .chromaStride(), pixels, frame.strideChroma, 8, 8)
            }

            last = mode
            if distance < best
            {
                best     = distance
                bestMode = mode
            }
        }

        if last != bestMode
        {
            for plane in 2'u32 do
                intraPredictChroma(bestMode, frame.pixChroma(plane, cast(s32, mbX) * 8, cast(s32, mbY) * 8), frame.strideChroma, hasLeft, hasTop)
        }

        return bestMode
    }

    // Returns the Intra_4x4 mode the syntax expects for a block: the smaller of its left and top
    // neighbours' modes, or DC when either stands outside the slice.
    mtd const predictedMode4(mbX, mbY, bx, by, firstRow: u32)->u32
    {
        if (bx == 0 and mbX == 0) or (by == 0 and mbY == firstRow) do
            return IntraDc
        let left = bx > 0 ? .mbs[.mbIndex(mbX, mbY)].modes[by * 4 + bx - 1] : .mbs[.mbIndex(mbX - 1, mbY)].modes[by * 4 + 3]
        let top  = by > 0 ? .mbs[.mbIndex(mbX, mbY)].modes[(by - 1) * 4 + bx] : .mbs[.mbIndex(mbX, mbY - 1)].modes[12 + bx]
        return Math.min(cast(u32, left), cast(u32, top))
    }

    // Codes the luma of a macroblock as sixteen Intra_4x4 blocks, each predicted from the samples
    // already decoded around it. Returns the summed transformed distance of the predictions, mode
    // bits included.
    mtd codeLuma4(mbX, mbY, firstRow: u32, residual: *LossyResidual)->u32
    {
        let frame  = .current()
        let stride = frame.strideLuma
        let origin = frame.pixLuma(cast(s32, mbX) * 16, cast(s32, mbY) * 16)
        let source = .sourceY.storage() + cast(u64, mbY) * 16 * .lumaStride() + cast(u64, mbX) * 16
        let mb     = &.mbs[.mbIndex(mbX, mbY)]
        var cost   = 0'u32

        residual.cbpLuma = 0
        for index in 16'u32
        {
            let bx        = cast(u32, LossyBlockColumn[index])
            let by        = cast(u32, LossyBlockRow[index])
            let block     = cast(u64, by * 4 + bx)
            let pixels    = origin + cast(u64, by) * 4 * stride + cast(u64, bx) * 4
            let from      = source + cast(u64, by) * 4 * .lumaStride() + cast(u64, bx) * 4
            let hasLeft   = bx > 0 or mbX > 0
            let hasTop    = by > 0 or mbY > firstRow
            let hasCorner = hasLeft and hasTop

            // The samples above and to the right exist only when their block was decoded first.
            var hasTopRight = false
            if by == 0
            {
                hasTopRight = mbY > firstRow and (bx < 3 or mbX + 1 < .mbWidth)
            }
            elif bx < 3
            {
                for other in index where LossyBlockColumn[other] == bx + 1 and LossyBlockRow[other] == by - 1 do
                    hasTopRight = true
            }

            let expected = .predictedMode4(mbX, mbY, bx, by, firstRow)
            var best     = Swag.U32.Max
            var bestMode = IntraDc
            var last     = IntraDc
            for mode in 9'u32
            {
                let needsTop  = mode == IntraVertical or mode == IntraDownLeft or mode == IntraVerticalLeft
                let needsLeft = mode == IntraHorizontal or mode == IntraHorizontalUp
                let needsAll  = mode == IntraDownRight or mode == IntraVerticalRight or mode == IntraHorizontalDown
                if (needsTop and not hasTop) or
                   (needsLeft and not hasLeft) or
                   (needsAll and not hasCorner) do
                    continue
                intraPredict4x4(mode, pixels, stride, hasLeft, hasTop, hasCorner, hasTopRight)
                last = mode
                let distance = lossySatd4(from, .lumaStride(), pixels, stride) + cast(u32, .lambda) * (mode == expected ? 1 : 4)
                if distance < best
                {
                    best     = distance
                    bestMode = mode
                }
            }

            if last != bestMode do
                intraPredict4x4(bestMode, pixels, stride, hasLeft, hasTop, hasCorner, hasTopRight)
            mb.modes[block] = cast(u8, bestMode)
            cost += best

            var coefficients: [16] s32
            var scaled:       [16] s16
            lossyForward4x4(from, .lumaStride(), pixels, stride, coefficients.buffer)
            let levels = residual.luma.buffer + block * 16
            residual.lumaCount[block] = cast(u8, lossyQuantize4x4(coefficients.buffer, 0, .qp, LossyIntraRounding, levels, scaled.buffer))
            if residual.lumaCount[block]
            {
                residual.cbpLuma |= 1'u32 << (index >> 2)
                addIdct4x4(pixels, stride, scaled.buffer)
            }
        }

        return cost
    }

    // Codes one macroblock without the reference picture, as Intra_4x4 or Intra_16x16 whichever
    // predicts it closer. `inP` says the macroblock stands in a P slice. With `known`, the best
    // Intra_16x16 prediction already stands in the picture, in `knownMode` at `knownCost`.
    mtd encodeIntraMb(bits: *EncoderBits, mbX, mbY, firstRow: u32, inP: bool, known = false, knownMode = 0'u32, knownCost = 0'u32)
    {
        let frame  = .current()
        let pixels = frame.pixLuma(cast(s32, mbX) * 16, cast(s32, mbY) * 16)
        let mb     = &.mbs[.mbIndex(mbX, mbY)]
        var residual: LossyResidual

        // The whole-block prediction is measured first, unless the caller already left the best
        // one in the picture with its mode and distance.
        var mode16 = knownMode
        var cost16 = knownCost
        if not known do
            cost16 = .predictLuma16(mbX, mbY, firstRow, &mode16)
        cost16 += cast(u32, .lambda) * 2

        // In a predicted picture an intra macroblock is nearly always a smooth area, which one
        // prediction fits: the sixteen small ones are not even tried when it already comes close.
        var use16 = inP and cost16 < LossySmoothCost
        if not use16
        {
            // Sixteen small predictions follow detail a single one cannot; they are kept unless
            // the whole-block prediction comes as close for fewer mode bits.
            let cost4 = .codeLuma4(mbX, mbY, firstRow, &residual) + cast(u32, .lambda) * LossySmallBlocksBits
            use16 = cost16 <= cost4
            if use16 do
                intraPredict16x16(mode16, pixels, frame.strideLuma, mbX > 0, mbY > firstRow)
        }

        if use16
        {
            for &mode in mb.modes do
                mode[] = cast(u8, IntraDc)
            .codeLuma16(mbX, mbY, &residual)
        }

        let chromaMode = .predictChroma(mbX, mbY, firstRow)
        .codeChroma(mbX, mbY, LossyIntraRounding, &residual)

        mb.mvX   = 0
        mb.mvY   = 0
        mb.inter = false
        mb.coded = true

        let base = inP ? 5'u32 : 0'u32
        if use16
        {
            bits.unsigned(base + 1 + mode16 + residual.cbpChroma * 4 + (residual.cbpLuma ? 12'u32 : 0'u32))
            bits.unsigned(chromaMode)
            bits.signed(0)     // mb_qp_delta.
            .writeLuma16(bits, mbX, mbY, firstRow, &residual)
            .writeChroma(bits, mbX, mbY, firstRow, &residual)
            return
        }

        bits.unsigned(base)
        for index in 16'u32
        {
            let bx       = cast(u32, LossyBlockColumn[index])
            let by       = cast(u32, LossyBlockRow[index])
            let mode     = cast(u32, mb.modes[by * 4 + bx])
            let expected = .predictedMode4(mbX, mbY, bx, by, firstRow)
            if mode == expected
            {
                bits.bit(1)
            }
            else
            {
                bits.bit(0)
                bits.bits(mode < expected ? mode : mode - 1, 3)
            }
        }

        bits.unsigned(chromaMode)
        let pattern = residual.cbpLuma | (residual.cbpChroma << 4)
        bits.unsigned(cast(u32, .intraCbpCode[pattern]))
        if pattern do
            bits.signed(0)     // mb_qp_delta.
        .writeLumaBlocks(bits, mbX, mbY, firstRow, &residual)
        .writeChroma(bits, mbX, mbY, firstRow, &residual)
    }
}

// ---------------------------------------------------------------------------------------------
// Inter prediction
// ---------------------------------------------------------------------------------------------

// A motion vector in quarter samples.
struct LossyVector
{
    x: s32
    y: s32
}

struct LossyRegionResult
{
    vector:         LossyVector
    fullyUnchanged: bool
}

// Returns the bit count of a signed Exp-Golomb code.
func lossySignedBits(value: s32)->s32
{
    var code = cast(u32, value > 0 ? value * 2 - 1 : -value * 2) + 1
    var size = 0's32
    while code
    {
        size += 1
        code >>= 1
    }

    return size * 2 - 1
}

impl LossyCoder
{
    // Returns the motion a neighbour offers for prediction; nothing outside the slice.
    mtd const neighbourMotion(mbX, mbY: s32, firstRow: u32, inter: *bool)->LossyVector
    {
        inter[] = false
        if mbX < 0 or mbX >= cast(s32, .mbWidth) or mbY < cast(s32, firstRow) do
            return {}
        let mb = &.mbs[.mbIndex(cast(u32, mbX), cast(u32, mbY))]
        inter[] = mb.inter
        return {mb.mvX, mb.mvY}
    }

    // Section 8.4.1.3: the 16x16 vector predicted from the left, top and top-right neighbours.
    mtd const predictMotion(mbX, mbY, firstRow: u32)->LossyVector
    {
        let x = cast(s32, mbX)
        let y = cast(s32, mbY)
        var interA, interB, interC: bool
        let a = .neighbourMotion(x - 1, y, firstRow, &interA)
        let b = .neighbourMotion(x, y - 1, firstRow, &interB)

        // The top-right macroblock gives way to the top-left one where the picture ends.
        var c        = .neighbourMotion(x + 1, y - 1, firstRow, &interC)
        let hasRight = mbY > firstRow and x + 1 < cast(s32, .mbWidth)
        if not hasRight do
            c = .neighbourMotion(x - 1, y - 1, firstRow, &interC)

        let availableB = mbY > firstRow
        let availableC = mbY > firstRow and (hasRight or x > 0)
        if x > 0 and not availableB and not availableC do
            return a
        if interA and not interB and not interC do
            return a
        if interB and not interA and not interC do
            return b
        if interC and not interA and not interB do
            return c
        return {Math.max(Math.min(a.x, b.x), Math.min(Math.max(a.x, b.x), c.x)),
                Math.max(Math.min(a.y, b.y), Math.min(Math.max(a.y, b.y), c.y))}
    }

    // Section 8.4.1.1: the vector a skipped macroblock takes without a single bit.
    mtd const skipMotion(mbX, mbY, firstRow: u32, predicted: LossyVector)->LossyVector
    {
        if mbX == 0 or mbY == firstRow do
            return {}
        let left = &.mbs[.mbIndex(mbX - 1, mbY)]
        let top  = &.mbs[.mbIndex(mbX, mbY - 1)]
        if (left.inter and left.mvX == 0 and left.mvY == 0) or (top.inter and top.mvY == 0 and top.mvX == 0) do
            return {}
        return predicted
    }

    // Returns the distance of the source macroblock to the reference displaced by `vector`.
    // An edge macroblock is measured over the samples the picture shows: what pads it to a whole
    // block is nobody's to match.
    mtd blockDistance(mbX, mbY: u32, vector: LossyVector, scratch: [*] u8)->u32
    {
        let source  = .sourceY.storage() + cast(u64, mbY) * 16 * .lumaStride() + cast(u64, mbX) * 16
        let x       = cast(s32, mbX) * 16 + (vector.x >> 2)
        let y       = cast(s32, mbY) * 16 + (vector.y >> 2)
        let frame   = .reference()
        let columns = cast(u64, Math.min(.width - cast(s32, mbX) * 16, 16))
        let rows    = cast(u64, Math.min(.height - cast(s32, mbY) * 16, 16))
        let whole   = vector.x & 3 == 0 and vector.y & 3 == 0
        if not whole do
            mcLuma(scratch, 16, frame, 0, x, y, vector.x & 3, vector.y & 3, 16, 16)
        let other  = whole ? cast(const [*] u8, frame.pixLuma(x, y)) : cast(const [*] u8, scratch)
        let stride = whole ? frame.strideLuma : 16'u64
        if columns == 16 do
            return lossySad16(source, .lumaStride(), other, stride, rows)
        return lossySadSmall(source, .lumaStride(), other, stride, columns, rows)
    }

    mtd blockDistanceBelow(mbX, mbY: u32, vector: LossyVector, scratch: [*] u8, bound: u32)->u32
    {
        if bound == 0 do
            return 0
        let source  = .sourceY.storage() + cast(u64, mbY) * 16 * .lumaStride() + cast(u64, mbX) * 16
        let x       = cast(s32, mbX) * 16 + (vector.x >> 2)
        let y       = cast(s32, mbY) * 16 + (vector.y >> 2)
        let frame   = .reference()
        let columns = cast(u64, Math.min(.width - cast(s32, mbX) * 16, 16))
        let rows    = cast(u64, Math.min(.height - cast(s32, mbY) * 16, 16))
        let whole   = vector.x & 3 == 0 and vector.y & 3 == 0
        if not whole do
            mcLuma(scratch, 16, frame, 0, x, y, vector.x & 3, vector.y & 3, 16, 16)
        let other  = whole ? cast(const [*] u8, frame.pixLuma(x, y)) : cast(const [*] u8, scratch)
        let stride = whole ? frame.strideLuma : 16'u64
        if columns == 16 do
            return lossySad16Below(source, .lumaStride(), other, stride, rows, bound)
        return lossySadSmallBelow(source, .lumaStride(), other, stride, columns, rows, bound)
    }

    mtd const vectorCost(vector, predicted: LossyVector)->u32
    {
        return cast(u32, .lambda * (lossySignedBits(vector.x - predicted.x) + lossySignedBits(vector.y - predicted.y)))
    }

    // Estimates the translation of one region of a slice since the previous picture, in whole
    // samples, from the sums of its rows and then of its columns. The estimate is only a
    // candidate: the search measures it like any other, so a wrong one costs one comparison.
    mtd const regionMotion(firstRow, lastRow: u32, region: u64)->LossyRegionResult
    {
        if not .hasPrior do
            return {{}, false}

        // Side of the cells a row or a column is summed in. One sum per whole row says little
        // about fine detail; a few sums along it tell two rows apart.
        const Cell = 32's64

        let stride  = .lumaStride()
        let total   = cast(s64, stride)
        let height  = cast(s64, .mbHeight) * 16
        let left    = cast(s64, region * LossyRegionWidth)
        let width   = cast(s64, Math.min(LossyRegionWidth, stride - region * LossyRegionWidth))
        let top     = cast(s64, firstRow) * 16
        let rows    = cast(s64, lastRow - firstRow) * 16
        let range   = cast(s64, LossySearchRange)
        let current = .sourceY.storage()
        let prior   = .priorY.storage()

        var unchanged = true
        for row in rows where unchanged
        {
            let offset = cast(u64, top + row) * stride + cast(u64, left)
            if Memory.compare(current + offset, prior + offset, cast(u64, width)) != 0 do
                unchanged = false
        }

        if unchanged
        {
            let chromaStride = .chromaStride()
            let chromaLeft   = cast(u64, left / 2)
            let chromaTop    = cast(u64, top / 2)
            let chromaWidth  = cast(u64, width / 2)
            let chromaRows   = cast(u64, rows / 2)
            let currentU     = .sourceU.storage()
            let currentV     = .sourceV.storage()
            let priorU       = .priorU.storage()
            let priorV       = .priorV.storage()

            for row in chromaRows where unchanged
            {
                let offset = (chromaTop + row) * chromaStride + chromaLeft
                if Memory.compare(currentU + offset, priorU + offset, chromaWidth) != 0 or
                   Memory.compare(currentV + offset, priorV + offset, chromaWidth) != 0 do
                    unchanged = false
            }

            return {{}, unchanged}
        }

        // Row profiles: the sums of each row of the region, cell by cell, here and in the rows
        // of the previous picture a shift can reach.
        let cellsX = (width + Cell - 1) / Cell

        func rowCells(plane: const [*] u8, stride: u64, x, y, width: s64, cells: [*] s32)
        {
            var zero: Simd.U8x16
            let line = plane + cast(u64, y) * stride + cast(u64, x)
            for chunk in cast(u64, width) / 16 do
                cells[chunk / 2] += cast(s32, Simd.sumAbsoluteDifferences(Simd.load(line + chunk * 16), zero))
        }

        var profile: Array's32
        var before:  Array's32
        profile.resize(cast(u64, rows * cellsX))
        before.resize(cast(u64, (rows + 2 * range) * cellsX))
        for row in rows do
            rowCells(current, stride, left, top + row, width, profile.storage() + cast(u64, row * cellsX))
        for row in rows + 2 * range
        {
            let y = top - range + row
            if y >= 0 and y < height do
                rowCells(prior, stride, left, y, width, before.storage() + cast(u64, row * cellsX))
        }

        var bestY     = 0's64
        var bestScore = Swag.S64.Max
        for shift in -range to range
        {
            // Rows the shift takes outside the picture have nothing to be compared with; the
            // others must still be most of the region, and their score is scaled to all of it.
            var score = 0's64
            var valid = 0's64
            for pair in rows / 2
            {
                let row = pair * 2
                let y   = top + row + shift
                if y < 0 or y >= height do
                    continue
                let here  = profile.storage() + cast(u64, row * cellsX)
                let there = before.storage() + cast(u64, (row + range + shift) * cellsX)
                for cell in cast(u64, cellsX) do
                    score += cast(s64, Math.abs(here[cell] - there[cell]))
                valid += 1
            }

            if valid * 4 < rows do
                continue
            score = score * rows / valid

            // Between equal scores the shorter vector wins, and no motion wins over all.
            if score < bestScore or (score == bestScore and Math.abs(shift) < Math.abs(bestY))
            {
                bestScore = score
                bestY     = shift
            }
        }

        if bestScore == 0 and bestY == 0 do
            return {{}, false}

        // Column profiles over the rows the vertical shift pairs up, in cells of rows.
        let cellsY = (rows + Cell - 1) / Cell
        var columns:       Array's32
        var columnsBefore: Array's32
        columns.resize(cast(u64, width * cellsY))
        columnsBefore.resize(cast(u64, (width + 2 * range) * cellsY))
        for sample in rows / 4
        {
            // One row in four tells the columns apart as well as all of them.
            let row = sample * 4
            if top + row + bestY < 0 or top + row + bestY >= height do
                continue
            let cell       = row / Cell
            let line       = current + cast(u64, top + row) * stride + cast(u64, left)
            let lineBefore = prior + cast(u64, top + row + bestY) * stride
            for column in width do
                columns[cast(u64, column * cellsY + cell)] += cast(s32, line[cast(u64, column)])
            for column in width + 2 * range
            {
                let x = left - range + column
                if x >= 0 and x < total do
                    columnsBefore[cast(u64, column * cellsY + cell)] += cast(s32, lineBefore[cast(u64, x)])
            }
        }

        var bestX = 0's64
        bestScore = Swag.S64.Max
        for shift in -range to range
        {
            var score = 0's64
            var valid = 0's64
            for pair in width / 2
            {
                let column = pair * 2
                let x      = left + column + shift
                if x < 0 or x >= total do
                    continue
                let here  = columns.storage() + cast(u64, column * cellsY)
                let there = columnsBefore.storage() + cast(u64, (column + range + shift) * cellsY)
                for cell in cast(u64, cellsY) do
                    score += cast(s64, Math.abs(here[cell] - there[cell]))
                valid += 1
            }

            if valid * 4 < width do
                continue
            score = score * width / valid
            if score < bestScore or (score == bestScore and Math.abs(shift) < Math.abs(bestX))
            {
                bestScore = score
                bestX     = shift
            }
        }

        return {{cast(s32, bestX) * 4, cast(s32, bestY) * 4}, false}
    }

    // Keeps a vector inside the samples the reference picture carries around itself.
    mtd const clampVector(mbX, mbY: u32, vector: LossyVector)->LossyVector
    {
        let x    = cast(s32, mbX) * 16
        let y    = cast(s32, mbY) * 16
        let minX = Math.max(-LossySearchRange, -x - 16) * 4
        let maxX = Math.min(LossySearchRange, cast(s32, .mbWidth) * 16 - x) * 4
        let minY = Math.max(-LossySearchRange, -y - 16) * 4
        let maxY = Math.min(LossySearchRange, cast(s32, .mbHeight) * 16 - y) * 4
        return {Math.clamp(vector.x, minX, maxX), Math.clamp(vector.y, minY, maxY)}
    }

    // Searches the reference picture for the closest 16x16 block: whole samples first, from the
    // vectors its neighbours suggest, then half and quarter samples around the best.
    mtd searchMotion(mbX, mbY, firstRow: u32, predicted, skip, region: LossyVector, bestCost: *u32)->LossyVector
    {
        var scratch: [16 * 16] u8
        var best = LossyVector{}
        var cost = Swag.U32.Max

        // A block the skip vector already predicts within the noise the quantizer discards needs
        // no search: its residual vanishes and it costs no bit at all.
        let quiet   = cast(u32, 96 + .lambda * 24)
        let resting = .blockDistance(mbX, mbY, {}, scratch.buffer)
        let skipped = .clampVector(mbX, mbY, skip)
        if skipped.x == skip.x and skipped.y == skip.y
        {
            // A block at rest stays at rest even when its neighbours drag the skip vector along.
            let trial = skip.x == 0 and skip.y == 0 ? resting : .blockDistance(mbX, mbY, skip, scratch.buffer)
            if trial < quiet and trial <= resting
            {
                bestCost[] = trial
                return skip
            }
        }

        func whole(vector: LossyVector)->LossyVector => {(vector.x + 2) & ~3, (vector.y + 2) & ~3}

        // Candidates: no motion, the predicted and skip vectors, the neighbours, and what this
        // macroblock did in the previous picture.
        var candidates: [9] LossyVector
        var count = 0'u64
        candidates[count] = {}
        count             += 1
        candidates[count] = region
        count             += 1
        candidates[count] = whole(predicted)
        count             += 1
        candidates[count] = whole(skip)
        count             += 1
        var inter: bool
        const Neighbours: [3, 2] s32 = [[-1, 0], [0, -1], [1, -1]]
        for side in 3'u64
        {
            let neighbour = .neighbourMotion(cast(s32, mbX) + Neighbours[side, 0], cast(s32, mbY) + Neighbours[side, 1], firstRow, &inter)
            if inter
            {
                candidates[count] = whole(neighbour)
                count += 1
            }
        }

        let index = .mbIndex(mbX, mbY)
        candidates[count] = whole({.priorMotion[index * 2], .priorMotion[index * 2 + 1]})
        count += 1

        for candidate in count
        {
            let vector = .clampVector(mbX, mbY, candidates[candidate])
            var seen   = false
            for earlier in candidate where candidates[earlier].x == vector.x and candidates[earlier].y == vector.y do
                seen = true
            candidates[candidate] = vector
            if seen do
                continue
            let penalty = .vectorCost(vector, predicted)
            if penalty < cost
            {
                let distance = .blockDistanceBelow(mbX, mbY, vector, scratch.buffer, cost - penalty)
                let trial    = distance + penalty
                if trial < cost
                {
                    cost = trial
                    best = vector
                }
            }
        }

        // A block nothing explains so far may have jumped: a list scrolled by a few lines or a
        // window dragged by a round step lands far from every neighbour's vector, on detail too
        // fine for a search that walks downhill. The usual jumps are simply tried.
        if cost >= quiet * 4
        {
            const Jumps: [24, 2] s32 = [
                [0, -2], [0, 2], [0, -4], [0, 4], [0, -8], [0, 8], [0, -16], [0, 16],
                [0, -32], [0, 32], [0, -48], [0, 48], [0, -64], [0, 64],
                [-16, 0], [16, 0], [-32, 0], [32, 0], [-64, 0], [64, 0],
                [-16, -16], [16, 16], [-16, 16], [16, -16]]
            for jump in 24'u64
            {
                let vector  = .clampVector(mbX, mbY, {Jumps[jump, 0] * 4, Jumps[jump, 1] * 4})
                let penalty = .vectorCost(vector, predicted)
                if penalty < cost
                {
                    let distance = .blockDistanceBelow(mbX, mbY, vector, scratch.buffer, cost - penalty)
                    let trial    = distance + penalty
                    if trial < cost
                    {
                        cost = trial
                        best = vector
                    }
                }
            }
        }

        // Hexagon steps while they improve, then the four closest whole samples.
        const Hexagon: [6, 2] s32 = [[-8, 0], [8, 0], [-4, -8], [4, -8], [-4, 8], [4, 8]]
        for 16
        {
            var moved = best
            for point in 6'u64
            {
                let vector = .clampVector(mbX, mbY, {best.x + Hexagon[point, 0], best.y + Hexagon[point, 1]})
                if vector.x == best.x and vector.y == best.y do
                    continue
                let penalty = .vectorCost(vector, predicted)
                if penalty < cost
                {
                    let distance = .blockDistanceBelow(mbX, mbY, vector, scratch.buffer, cost - penalty)
                    let trial    = distance + penalty
                    if trial < cost
                    {
                        cost  = trial
                        moved = vector
                    }
                }
            }

            if moved.x == best.x and moved.y == best.y do
                break
            best = moved
        }

        // Each refinement halves its step: whole, half, then quarter samples. All eight neighbours
        // are tried down to half samples; at quarter samples the four along the axes find nearly
        // all of what the diagonals would, for half the interpolations.
        const Around: [8, 2] s32 = [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, -1], [-1, 1], [1, 1]]
        for step in [4's32, 2, 1]
        {
            // A match already inside the quantizer's noise gains nothing from finer motion.
            if step < 4 and cost < quiet do
                break
            let centre = best
            for point in (step == 1 ? 4'u64 : 8'u64)
            {
                let vector = .clampVector(mbX, mbY, {centre.x + Around[point, 0] * step, centre.y + Around[point, 1] * step})
                if vector.x == centre.x and vector.y == centre.y do
                    continue
                let penalty = .vectorCost(vector, predicted)
                if penalty < cost
                {
                    let distance = .blockDistanceBelow(mbX, mbY, vector, scratch.buffer, cost - penalty)
                    let trial    = distance + penalty
                    if trial < cost
                    {
                        cost = trial
                        best = vector
                    }
                }
            }
        }

        bestCost[] = cost
        return best
    }

    // Builds the prediction of a macroblock displaced by `vector` in the current picture.
    mtd predictInter(mbX, mbY: u32, vector: LossyVector)
    {
        let frame     = .current()
        let reference = .reference()
        let x         = cast(s32, mbX) * 16
        let y         = cast(s32, mbY) * 16
        mcLuma(frame.pixLuma(x, y), frame.strideLuma, reference, 0, x + (vector.x >> 2), y + (vector.y >> 2), vector.x & 3, vector.y & 3, 16, 16)
        for plane in 2'u32 do
            mcChroma(frame.pixChroma(plane, x / 2, y / 2), frame.strideChroma, reference, plane, x / 2 + (vector.x >> 3), y / 2 + (vector.y >> 3), vector.x & 7, vector.y & 7, 8, 8)
    }

    // Gives the samples of an edge macroblock that lie outside the picture the value of their
    // prediction. Nobody sees them, so the cheapest residual there is none.
    mtd padSourceWithPrediction(mbX, mbY: u32)
    {
        let x        = cast(u64, mbX) * 16
        let y        = cast(u64, mbY) * 16
        let visibleX = Math.min(cast(u64, .width) - Math.min(x, cast(u64, .width)), 16'u64)
        let visibleY = Math.min(cast(u64, .height) - Math.min(y, cast(u64, .height)), 16'u64)
        if visibleX == 16 and visibleY == 16 do
            return

        let frame = .current()
        let luma  = frame.pixLuma(cast(s32, x), cast(s32, y))
        let into  = .sourceY.storage() + y * .lumaStride() + x
        for row in 16'u64
        {
            let first = row < visibleY ? visibleX : 0'u64
            for column in first until 16 do
                into[row * .lumaStride() + column] = luma[row * frame.strideLuma + column]
        }

        for plane in 2'u32
        {
            let chroma = frame.pixChroma(plane, cast(s32, x / 2), cast(s32, y / 2))
            let target = (plane == 0 ? .sourceU.storage() : .sourceV.storage()) + y / 2 * .chromaStride() + x / 2
            for row in 8'u64
            {
                let first = row < visibleY / 2 ? visibleX / 2 : 0'u64
                for column in first until 8 do
                    target[row * .chromaStride() + column] = chroma[row * frame.strideChroma + column]
            }
        }
    }

    // Reports whether the source macroblock repeats the one of the previous picture.
    mtd const repeatsPrior(mbX, mbY: u32)->bool
    {
        if not .hasPrior do
            return false
        let luma = cast(u64, mbY) * 16 * .lumaStride() + cast(u64, mbX) * 16
        for row in 16'u64 where Memory.compare(.sourceY.storage() + luma + row * .lumaStride(), .priorY.storage() + luma + row * .lumaStride(), 16) != 0 do
            return false
        let chroma = cast(u64, mbY) * 8 * .chromaStride() + cast(u64, mbX) * 8
        for row in 8'u64
        {
            let at = chroma + row * .chromaStride()
            if Memory.compare(.sourceU.storage() + at, .priorU.storage() + at, 8) != 0 or
               Memory.compare(.sourceV.storage() + at, .priorV.storage() + at, 8) != 0 do
                return false
        }

        return true
    }

    // Codes one macroblock of a P slice: skipped, predicted from the reference, or intra when
    // nothing in the reference comes close.
    mtd encodeInterMb(bits: *EncoderBits, mbX, mbY, firstRow: u32, region: LossyRegionResult, skipRun: *u32)
    {
        let mb        = &.mbs[.mbIndex(mbX, mbY)]
        let predicted = .predictMotion(mbX, mbY, firstRow)
        let skip      = .skipMotion(mbX, mbY, firstRow, predicted)
        var residual: LossyResidual

        // A source that did not change keeps what the decoder already shows: quantizing it again
        // would only move the picture around its own rounding.
        let still  = region.fullyUnchanged or .repeatsPrior(mbX, mbY)
        var vector = LossyVector{}
        var cost   = 0'u32
        if not still
        {
            vector = .searchMotion(mbX, mbY, firstRow, predicted, skip, region.vector, &cost)

            // What the reference predicts is compared with what the neighbours do, both as the
            // transform will see them. A cut or an uncovered area has no reference to speak of,
            // and a smooth area whose light changed costs one coefficient predicted from its
            // neighbours, where its difference to the reference costs one in every block.
            if cost >= cast(u32, 96 + .lambda * 24)
            {
                var moved: [256] u8
                let source = .sourceY.storage() + cast(u64, mbY) * 16 * .lumaStride() + cast(u64, mbX) * 16
                mcLuma(moved.buffer, 16, .reference(), 0, cast(s32, mbX) * 16 + (vector.x >> 2), cast(s32, mbY) * 16 + (vector.y >> 2), vector.x & 3, vector.y & 3, 16, 16)
                let inter  = lossySatd16(source, .lumaStride(), moved.buffer, 16) + .vectorCost(vector, predicted)
                var mode16 = Intra16Dc
                let intra  = .predictLuma16(mbX, mbY, firstRow, &mode16) + cast(u32, .lambda) * LossyIntraBits
                if intra < inter
                {
                    bits.unsigned(skipRun[])
                    skipRun[] = 0
                    .encodeIntraMb(bits, mbX, mbY, firstRow, true, true, mode16, intra - cast(u32, .lambda) * LossyIntraBits)
                    return
                }
            }
        }

        .predictInter(mbX, mbY, vector)
        if not still
        {
            .padSourceWithPrediction(mbX, mbY)
            .codeLumaBlocks(mbX, mbY, LossyInterRounding, true, &residual)
            .codeChroma(mbX, mbY, LossyInterRounding, &residual)
        }

        mb.mvX   = cast(s16, vector.x)
        mb.mvY   = cast(s16, vector.y)
        mb.inter = true
        mb.coded = true

        let pattern = residual.cbpLuma | (residual.cbpChroma << 4)
        if not pattern and vector.x == skip.x and vector.y == skip.y
        {
            skipRun[] += 1
            return
        }

        bits.unsigned(skipRun[])
        skipRun[] = 0
        bits.unsigned(0)     // P_L0_16x16.
        bits.signed(vector.x - predicted.x)
        bits.signed(vector.y - predicted.y)
        bits.unsigned(cast(u32, InterCbpToGolomb[pattern]))
        if pattern do
            bits.signed(0)     // mb_qp_delta.
        .writeLumaBlocks(bits, mbX, mbY, firstRow, &residual)
        .writeChroma(bits, mbX, mbY, firstRow, &residual)
    }
}
