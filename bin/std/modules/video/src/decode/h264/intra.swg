#global namespace H264
#global internal

//! Format: H.264/AVC decoder component.
//! Supported: Progressive 8-bit 4:2:0 and 4:4:4 Baseline, Main, High, and High 4:4:4 Predictive streams with CAVLC/CABAC, I/P/B slices, weighted prediction, cropping, reordering, and deblocking.
//! Not supported: Interlacing, 4:2:2 chroma, bit depths above 8, slice groups, data partitioning, scalable/multiview extensions, and lossless transform bypass.
//! Role: This file owns intra luma and chroma prediction.
//

using Core

// Intra prediction, section 8.3. Every routine predicts straight into the picture plane,
// reading the already reconstructed neighboring samples from it. The diagonal modes follow
// one shared scheme: reference arrays are stored with two lead-in slots, so that index -1 is
// the corner sample and index -2 the first sample of the opposite edge, which is exactly the
// reach of the specification's formulas.

// Luma 4x4 and 8x8 prediction modes.
const IntraVertical       = 0_u32
const IntraHorizontal     = 1_u32
const IntraDc             = 2_u32
const IntraDownLeft       = 3_u32
const IntraDownRight      = 4_u32
const IntraVerticalRight  = 5_u32
const IntraHorizontalDown = 6_u32
const IntraVerticalLeft   = 7_u32
const IntraHorizontalUp   = 8_u32

// Intra 16x16 prediction modes.
const Intra16Vertical   = 0_u32
const Intra16Horizontal = 1_u32
const Intra16Dc         = 2_u32
const Intra16Plane      = 3_u32

// Intra chroma prediction modes.
const IntraChromaDc         = 0_u32
const IntraChromaHorizontal = 1_u32
const IntraChromaVertical   = 2_u32
const IntraChromaPlane      = 3_u32

#[Swag.Inline]
private func fillIntra16x16(dst: [*] u8, stride: u64, value: u8)
{
    let pixels = Simd.splat(value)
    for row in 16_u64
    {
        Simd.store(dst + row * stride, pixels)
    }
}

#[Swag.Inline]
private func copyIntra16x16(dst: [*] u8, stride: u64, pixels: Simd.U8x16)
{
    for row in 16_u64
    {
        Simd.store(dst + row * stride, pixels)
    }
}

#[Swag.Inline]
func storeIntra8Vertical(dst: [*] u8, stride: u64, top: const [*] s32)
{
    for column in 8_u64
    {
        dst[column] = cast(u8, top[column])
    }

    let pixels = Simd.load(dst)
    for row in 1_u64 until 8
    {
        Simd.storeLow8(dst + row * stride, pixels)
    }
}

#[Swag.Inline]
private func storeIntra8Filtered(dst: [*] u8, low, high: Simd.S32x4)
{
    let words = Simd.packUnsigned(low, high)
    Simd.storeLow8(dst, Simd.packUnsigned(cast #bit(Simd.S16x8, words), cast #bit(Simd.S16x8, words)))
}

// Index layout of the sixteen raw references. Slots 0 through 9 are the top edge with
// the opposite edge's first sample and the corner prepended. Slots 10 through 15 mirror
// that layout for the left edge.
private const Intra4Left = 10_u32

// Each output names three references. The same three-tap filter gives a single sample
// when all three agree, a rounded average when the two outside references agree, and
// a weighted average of three samples otherwise.
private var Intra4Directions = #run buildIntra4Directions()

private func buildIntra4Directions()->[9, 3, 16] u8
{
    var table: #returntype
    for mode in 9_u32
    {
        for row in 4_s32
        {
            for column in 4_s32
            {
                var a, b, c: u32
                switch mode
                {
                case IntraVertical:
                    a = cast(u32, column + 2)
                    b = a
                    c = a

                case IntraHorizontal:
                    a = Intra4Left + cast(u32, row + 2)
                    b = a
                    c = a

                case IntraDownLeft:
                    a = cast(u32, row + column + 2)
                    b = a + 1
                    c = Math.min(a + 2, 9_u32)

                case IntraDownRight:
                    let diagonal = column - row
                    if diagonal > 0
                    {
                        a = cast(u32, diagonal)
                        b = a + 1
                        c = a + 2
                    }
                    else if diagonal < 0
                    {
                        a = Intra4Left + cast(u32, -diagonal)
                        b = a + 1
                        c = a + 2
                    }
                    else
                    {
                        a = Intra4Left + 2
                        b = 1
                        c = 2
                    }

                case IntraVerticalRight, IntraHorizontalDown:
                    let vertical = mode == IntraVerticalRight
                    let major    = vertical ? column : row
                    let minor    = vertical ? row : column
                    let primary  = vertical ? 0_u32 : Intra4Left
                    let opposite = vertical ? Intra4Left : 0_u32
                    let z        = 2 * major - minor
                    if z >= 0 and z & 1 == 0
                    {
                        a = primary + cast(u32, (major - (minor >> 1) + 1))
                        b = a + 1
                        c = a
                    }
                    else if z >= -1
                    {
                        a = primary + cast(u32, (major - (minor >> 1)))
                        b = a + 1
                        c = a + 2
                    }
                    else
                    {
                        b = opposite + cast(u32, -z)
                        a = b + 1
                        c = b - 1
                    }

                case IntraVerticalLeft, IntraHorizontalUp:
                    let vertical = mode == IntraVerticalLeft
                    let minor    = vertical ? row : column
                    let major    = vertical ? column : row
                    let origin   = vertical ? 0_u32 : Intra4Left
                    let limit    = vertical ? 9_u32 : Intra4Left + 5
                    let index    = origin + cast(u32, (2 + major + (minor >> 1)))
                    a = Math.min(index, limit)
                    b = Math.min(index + 1, limit)
                    c = minor & 1 == 0 ? a : Math.min(index + 2, limit)
                }

                let index = cast(u32, row * 4 + column)
                table[mode, 0, index] = cast(u8, a)
                table[mode, 1, index] = cast(u8, b)
                table[mode, 2, index] = cast(u8, c)
            }
        }
    }

    return table
}

#[Swag.Inline]
func readIntra4Edges(dst: const [*] u8, stride: u64, hasLeft, hasTop, hasTopLeft, hasTopRight: bool)->Simd.U8x16
{
    var references: [16] u8
    let above  = dst - stride
    let left   = dst - 1
    let corner = hasTopLeft ? (above - 1)[0] : 128_u8
    let top    = hasTop ? cast(const [*] u32, above)[0] : 0x80808080_u32
    let far    = hasTopRight ? cast(const [*] u32, above + 4)[0] : (top >> 24) * 0x01010101
    cast([*] u32, &references[2])[0] = top
    cast([*] u32, &references[6])[0] = far
    references[12]                   = hasLeft ? left[0] : 128
    references[13]                   = hasLeft ? left[stride] : 128
    references[14]                   = hasLeft ? left[stride * 2] : 128
    references[15]                   = hasLeft ? left[stride * 3] : 128
    references[0]                    = references[12]
    references[1]                    = corner
    references[10]                   = references[2]
    references[11]                   = corner
    return Simd.load(references.buffer)
}

// Predicts one 4x4 luma block, section 8.3.1.2. Missing top-right samples repeat the
// last available top sample.
func intraPredict4x4(mode: u32, dst: [*] u8, stride: u64, hasLeft, hasTop, hasTopLeft, hasTopRight: bool)
{
    if mode > IntraHorizontalUp
    {
        return
    }

    let edges = readIntra4Edges(dst, stride, hasLeft, hasTop, hasTopLeft, hasTopRight)
    storeIntra4x4(dst, stride, intra4Samples(mode, hasLeft, hasTop, edges))
}

// Builds the sixteen prediction samples in raster order.
func intra4Samples(mode: u32, hasLeft, hasTop: bool, edges: Simd.U8x16)->Simd.U8x16
{
    if mode == IntraDc
    {
        const TopMask  = cast(Simd.U8x16, [0_u8, 0, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        const LeftMask = cast(Simd.U8x16, [0_u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255])
        var dc = 128_u32
        if hasLeft and hasTop
        {
            dc = (Simd.sumWide(edges & (TopMask | LeftMask)) + 4) >> 3
        }
        else if hasLeft or hasTop
        {
            dc = (Simd.sumWide(edges & (hasLeft ? LeftMask : TopMask)) + 2) >> 2
        }

        return Simd.splat(cast(u8, dc))
    }

    let left   = Simd.shuffle(edges, Simd.load(&Intra4Directions[mode, 0, 0]))
    let centre = Simd.shuffle(edges, Simd.load(&Intra4Directions[mode, 1, 0]))
    let right  = Simd.shuffle(edges, Simd.load(&Intra4Directions[mode, 2, 0]))
    return lowpassBytes(left, centre, right)
}

#[Swag.Inline]
func storeIntra4x4(dst: [*] u8, stride: u64, pixels: Simd.U8x16)
{
    let rows = cast #bit(Simd.U32x4, pixels)
    cast([*] u32, dst)[0] = rows[0]
    cast([*] u32, dst + stride)[0]     = rows[1]
    cast([*] u32, dst + stride * 2)[0] = rows[2]
    cast([*] u32, dst + stride * 3)[0] = rows[3]
}

// The three-tap filter `(a + 2b + c + 2) >> 2` on bytes: the floored half-sum of the outer
// pair is their rounding average less the bit it rounded up, and averaging that with the
// center rounds exactly as the sum does, as FFmpeg's PRED8x8_LOWPASS writes it.
#[Swag.Inline]
private func lowpassBytes(a, b, c: Simd.U8x16)->Simd.U8x16
{
    let outer = Simd.subSaturating(Simd.average(a, c), (a ^ c) & Simd.splat(1_u8))
    return Simd.average(outer, b)
}

// Predicts one 8x8 luma block, sections 8.3.2.2.1 and 8.3.2.2.
//
// The references are low-pass filtered first, as every 8x8 mode requires.
func intraPredict8x8(mode: u32, dst: [*] u8, stride: u64, hasLeft, hasTop, hasTopLeft, hasTopRight: bool)
{
    // Raw references. The top row is sixteen bytes: its upper eight repeat the eighth when
    // the top-right block is missing, and a missing side reads 128. The row above the block
    // is always inside the padded plane, so it is loaded whatever is available.
    const Replicate7 = cast(Simd.U8x16, [0_u8, 1, 2, 3, 4, 5, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7])
    const LowHalf    = cast(Simd.U8x16, [0xFF_u8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0])
    var rawLeft: [8] s32
    let rawCorner = hasTopLeft ? cast(s32, (dst - stride - 1)[0]) : 128
    for row in 8_u64
    {
        rawLeft[row] = hasLeft ? cast(s32, (dst - 1)[row * stride]) : 128
    }

    let above   = Simd.load(dst - stride)
    let missing = Simd.splat(128_u8)
    let low     = hasTop ? above : missing
    let high    = hasTopRight ? above : (hasTop ? Simd.shuffle(above, Replicate7) : missing)
    let top     = Simd.select(LowHalf, low, high)
    let rawTop0 = hasTop ? cast(s32, above[0]) : 128

    // Filtered references, with the same two-slot lead-in as the 4x4 arrays. The top row
    // filters as one vector: each sample against its neighbours, the first against the corner
    // (or itself without one) and the last against itself, as `(a + 2b + c + 2) >> 2`.
    var tp: [19] s32
    var lp: [10] s32
    let corner   = (rawLeft[0] + 2 * rawCorner + rawTop0 + 2) >> 2
    let first    = Simd.splat(cast(u8, (hasTopLeft ? rawCorner : rawTop0)))
    let previous = Simd.align(first, top, 15)
    let next     = Simd.align(top, Simd.shuffle(top, Simd.splat(15_u8)), 1)
    let filtered = lowpassBytes(previous, top, next)
    let words    = Simd.widenLow(filtered)
    let wordsHi  = Simd.widenHigh(filtered)
    Simd.store(tp.buffer + 2, cast #bit(Simd.S32x4, Simd.widenLow(words)))
    Simd.store(tp.buffer + 6, cast #bit(Simd.S32x4, Simd.widenHigh(words)))
    Simd.store(tp.buffer + 10, cast #bit(Simd.S32x4, Simd.widenLow(wordsHi)))
    Simd.store(tp.buffer + 14, cast #bit(Simd.S32x4, Simd.widenHigh(wordsHi)))
    tp[18] = tp[17]

    lp[2] = ((hasTopLeft ? rawCorner : rawLeft[0]) + 2 * rawLeft[0] + rawLeft[1] + 2) >> 2
    for row in 1_u64 until 7
    {
        lp[2 + row] = (rawLeft[row - 1] + 2 * rawLeft[row] + rawLeft[row + 1] + 2) >> 2
    }

    lp[9] = (rawLeft[6] + 3 * rawLeft[7] + 2) >> 2

    tp[1] = corner
    tp[0] = lp[2]
    lp[1] = corner
    lp[0] = tp[2]

    switch mode
    {
    case IntraVertical:
        storeIntra8Vertical(dst, stride, tp.buffer + 2)

    case IntraHorizontal:
        for row in 8_u64
        {
            Simd.storeLow8(dst + row * stride, Simd.splat(cast(u8, lp[2 + row])))
        }

    case IntraDc:
        var sum   = 0_s32
        var count = 0_s32
        if hasLeft
        {
            for row in 8_u64
            {
                sum += lp[2 + row]
            }

            count += 8
        }

        if hasTop
        {
            for column in 8_u64
            {
                sum += tp[2 + column]
            }

            count += 8
        }

        var average = 128_s32
        if count == 16
        {
            average = (sum + 8) >> 4
        }
        else if count == 8
        {
            average = (sum + 4) >> 3
        }

        let value = Simd.splat(cast(u8, average))
        for row in 8_u64
        {
            Simd.storeLow8(dst + row * stride, value)
        }

    case IntraDownLeft:
        for row in 8_u64
        {
            let low  = (Simd.load(tp.buffer + 2 + row) + Simd.load(tp.buffer + 3 + row) * 2 + Simd.load(tp.buffer + 4 + row) + Simd.splat(2_s32)) >> 2
            let high = (Simd.load(tp.buffer + 6 + row) + Simd.load(tp.buffer + 7 + row) * 2 + Simd.load(tp.buffer + 8 + row) + Simd.splat(2_s32)) >> 2
            storeIntra8Filtered(dst + row * stride, low, high)
        }

    // The three diagonal modes take each row as an eight-sample window of one short line of
    // filtered edge values, so a block costs one pass over the edge and eight row copies
    // instead of a per-sample choice between three formulas.
    case IntraDownRight:

        // Sample (x, y) is the three-tap filter of the edge centered on its diagonal: the
        // edge runs up the left column, through the corner, and along the top row, so row y
        // starts 7 - y values into it.
        var edge: [17] s32
        for index in 8_u64
        {
            edge[index] = lp[9 - index]
        }

        for index in 8_u64
        {
            edge[9 + index] = tp[2 + index]
        }

        edge[8] = lp[1]
        var line: [15] u8
        for index in 15_u64
        {
            line[index] = cast(u8, ((edge[index] + 2 * edge[index + 1] + edge[index + 2] + 2) >> 2))
        }

        for row in 8_u64
        {
            Memory.copy(dst + row * stride, line.buffer + 7 - row, 8)
        }

    case IntraVerticalRight:

        // Rows of one parity shift right by one sample every two rows: the even rows read the
        // two-tap averages of the top row, the odd rows its three-tap filter, and the samples
        // shifted in from the left are the filtered left column, every other one.
        var even: [11] u8
        var odd:  [11] u8
        for index in 3_u64
        {
            let e = 6 - 2 * index
            even[index] = cast(u8, ((lp[e + 1] + 2 * lp[e] + lp[e - 1] + 2) >> 2))
            odd[index]  = cast(u8, ((lp[e + 2] + 2 * lp[e + 1] + lp[e] + 2) >> 2))
        }

        for k in 8_u64
        {
            even[3 + k] = cast(u8, ((tp[k + 1] + tp[k + 2] + 1) >> 1))
            odd[3 + k]  = cast(u8, ((tp[k] + 2 * tp[k + 1] + tp[k + 2] + 2) >> 2))
        }

        for row in 8_u64
        {
            let line = row & 1 == 0 ? even.buffer : odd.buffer
            Memory.copy(dst + row * stride, line + 3 - (row >> 1), 8)
        }

    case IntraHorizontalDown:

        // Row y reads, from 14 - 2y on, the left column's two-tap averages and three-tap
        // filters interleaved from the bottom up, then the filtered top row.
        var line: [22] u8
        for index in 8_u64
        {
            let k = 7 - index
            line[2 * index]     = cast(u8, ((lp[k + 1] + lp[k + 2] + 1) >> 1))
            line[2 * index + 1] = cast(u8, ((lp[k] + 2 * lp[k + 1] + lp[k + 2] + 2) >> 2))
        }

        for e in 2_u64 until 8
        {
            line[14 + e] = cast(u8, ((tp[e + 1] + 2 * tp[e] + tp[e - 1] + 2) >> 2))
        }

        for row in 8_u64
        {
            Memory.copy(dst + row * stride, line.buffer + 14 - 2 * row, 8)
        }

    case IntraVerticalLeft:
        for row in 8_u64
        {
            let start = 2 + (row >> 1)
            if row & 1 == 0
            {
                let low  = (Simd.load(tp.buffer + start) + Simd.load(tp.buffer + start + 1) + Simd.splat(1_s32)) >> 1
                let high = (Simd.load(tp.buffer + start + 4) + Simd.load(tp.buffer + start + 5) + Simd.splat(1_s32)) >> 1
                storeIntra8Filtered(dst + row * stride, low, high)
            }
            else
            {
                let low  = (Simd.load(tp.buffer + start) + Simd.load(tp.buffer + start + 1) * 2 + Simd.load(tp.buffer + start + 2) + Simd.splat(2_s32)) >> 2
                let high = (Simd.load(tp.buffer + start + 4) + Simd.load(tp.buffer + start + 5) * 2 + Simd.load(tp.buffer + start + 6) + Simd.splat(2_s32)) >> 2
                storeIntra8Filtered(dst + row * stride, low, high)
            }
        }

    case IntraHorizontalUp:
        var predicted: [22] u8
        for z in 13_u64
        {
            let index    = z >> 1
            let filtered = z & 1 == 0 ? (lp[2 + index] + lp[3 + index] + 1) >> 1 : (lp[2 + index] + 2 * lp[3 + index] + lp[4 + index] + 2) >> 2
            predicted[z] = cast(u8, filtered)
        }

        predicted[13] = cast(u8, ((lp[8] + 3 * lp[9] + 2) >> 2))
        for z in 14_u64 until 22
        {
            predicted[z] = cast(u8, lp[9])
        }

        for row in 8_u64
        {
            Memory.copy(dst + row * stride, predicted.buffer + 2 * row, 8)
        }
    }
}

// Predicts one 16x16 luma macroblock, section 8.3.3.
func intraPredict16x16(mode: u32, dst: [*] u8, stride: u64, hasLeft, hasTop: bool)
{
    switch mode
    {
    case Intra16Vertical:
        copyIntra16x16(dst, stride, Simd.load(dst - stride))

    case Intra16Horizontal:
        for row in 16_u64
        {
            Simd.store(dst + row * stride, Simd.splat((dst - 1)[row * stride]))
        }

    case Intra16Dc:
        var sum   = 0_s32
        var count = 0_s32
        if hasLeft
        {
            for row in 16_u64
            {
                sum += cast(s32, (dst - 1)[row * stride])
            }

            count += 16
        }

        if hasTop
        {
            for column in 16_u64
            {
                sum += cast(s32, (dst - stride)[column])
            }

            count += 16
        }

        var value = 128_s32
        if count == 32
        {
            value = (sum + 16) >> 5
        }
        else if count == 16
        {
            value = (sum + 8) >> 4
        }

        fillIntra16x16(dst, stride, cast(u8, value))

    case Intra16Plane:
        const Offsets0 = cast(Simd.S32x4, [0_s32, 1, 2, 3])
        const Offsets1 = cast(Simd.S32x4, [4_s32, 5, 6, 7])
        const Offsets2 = cast(Simd.S32x4, [8_s32, 9, 10, 11])
        const Offsets3 = cast(Simd.S32x4, [12_s32, 13, 14, 15])
        var h = cast(s32, (dst - stride)[8]) - cast(s32, (dst - stride)[6])
        var v = cast(s32, (dst - 1)[8 * stride]) - cast(s32, (dst - 1)[6 * stride])
        for k in 2 to 8
        {
            let topRight = cast(s32, (dst - stride)[cast(u64, (7 + k))])
            let topLeft  = k == 8 ? cast(s32, (dst - stride - 1)[0]) : cast(s32, (dst - stride)[cast(u64, (7 - k))])
            h += k * (topRight - topLeft)
            let leftDown = cast(s32, (dst - 1)[cast(u64, (7 + k)) * stride])
            let leftUp   = k == 8 ? cast(s32, (dst - stride - 1)[0]) : cast(s32, (dst - 1)[cast(u64, (7 - k)) * stride])
            v += k * (leftDown - leftUp)
        }

        h = (5 * h + 32) >> 6
        v = (5 * v + 32) >> 6
        var a = 16 * (cast(s32, (dst - 1)[15 * stride]) + cast(s32, (dst - stride)[15]) + 1) - 7 * (v + h)
        for row in 16_u64
        {
            let base = Simd.splat(a)
            a += v
            let values0 = Math.max(Math.min((base + Offsets0 * h) >> 5, Simd.splat(255_s32)), Simd.splat(0_s32))
            let values1 = Math.max(Math.min((base + Offsets1 * h) >> 5, Simd.splat(255_s32)), Simd.splat(0_s32))
            let values2 = Math.max(Math.min((base + Offsets2 * h) >> 5, Simd.splat(255_s32)), Simd.splat(0_s32))
            let values3 = Math.max(Math.min((base + Offsets3 * h) >> 5, Simd.splat(255_s32)), Simd.splat(0_s32))
            let low     = Simd.packUnsigned(values0, values1)
            let high    = Simd.packUnsigned(values2, values3)
            Simd.store(dst + row * stride, Simd.packUnsigned(cast #bit(Simd.S16x8, low), cast #bit(Simd.S16x8, high)))
        }
    }
}

// Predicts one 8x8 chroma plane of a macroblock, section 8.3.4.
func intraPredictChroma(mode: u32, dst: [*] u8, stride: u64, hasLeft, hasTop: bool)
{
    switch mode
    {
    case IntraChromaDc:

        // Each 4x4 quadrant has its own average: the corner ones prefer their aligned edge,
        // the top-left and bottom-right ones average both edges when both exist.
        var sumTopLeft    = 0_s32
        var sumTopRight   = 0_s32
        var sumBottomLeft = 0_s32
        for index in 4_u64
        {
            if hasTop
            {
                sumTopLeft  += cast(s32, (dst - stride)[index])
                sumTopRight += cast(s32, (dst - stride)[4 + index])
            }

            if hasLeft
            {
                sumTopLeft    += cast(s32, (dst - 1)[index * stride])
                sumBottomLeft += cast(s32, (dst - 1)[(4 + index) * stride])
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
        else if hasTop
        {
            dc0 = (sumTopLeft + 2) >> 2
            dc1 = (sumTopRight + 2) >> 2
            dc2 = dc0
            dc3 = dc1
        }
        else if hasLeft
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

        let top    = cast #bit(Simd.U8x16, cast(Simd.U32x4, [cast(u32, dc0) * 0x01010101, cast(u32, dc1) * 0x01010101, 0, 0]))
        let bottom = cast #bit(Simd.U8x16, cast(Simd.U32x4, [cast(u32, dc2) * 0x01010101, cast(u32, dc3) * 0x01010101, 0, 0]))
        for row in 4_u64
        {
            Simd.storeLow8(dst + row * stride, top)
        }

        for row in 4_u64 until 8
        {
            Simd.storeLow8(dst + row * stride, bottom)
        }

    case IntraChromaHorizontal:
        for row in 8_u64
        {
            Simd.storeLow8(dst + row * stride, Simd.splat((dst - 1)[row * stride]))
        }

    case IntraChromaVertical:
        let pixels = Simd.load(dst - stride)
        for row in 8_u64
        {
            Simd.storeLow8(dst + row * stride, pixels)
        }

    case IntraChromaPlane:
        var h = cast(s32, (dst - stride)[4]) - cast(s32, (dst - stride)[2])
        var v = cast(s32, (dst - 1)[4 * stride]) - cast(s32, (dst - 1)[2 * stride])
        for k in 2 to 4
        {
            let topRight = cast(s32, (dst - stride)[cast(u64, (3 + k))])
            let topLeft  = k == 4 ? cast(s32, (dst - stride - 1)[0]) : cast(s32, (dst - stride)[cast(u64, (3 - k))])
            h += k * (topRight - topLeft)
            let leftDown = cast(s32, (dst - 1)[cast(u64, (3 + k)) * stride])
            let leftUp   = k == 4 ? cast(s32, (dst - stride - 1)[0]) : cast(s32, (dst - 1)[cast(u64, (3 - k)) * stride])
            v += k * (leftDown - leftUp)
        }

        h = (17 * h + 16) >> 5
        v = (17 * v + 16) >> 5
        var a = 16 * (cast(s32, (dst - 1)[7 * stride]) + cast(s32, (dst - stride)[7]) + 1) - 3 * (v + h)
        for row in 8_u64
        {
            var b = a
            a += v
            for column in 8_u64
            {
                dst[row * stride + column] = clampPixel(b >> 5)
                b += h
            }
        }
    }
}
