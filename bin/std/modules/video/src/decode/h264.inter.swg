#global namespace H264
#global internal

using Core

// Inter prediction, section 8.4.2.2: quarter-sample luma interpolation with the six-tap
// half-sample filter, eighth-sample bilinear chroma interpolation, and the weighted sample
// prediction of section 8.4.2.3.
//
// Every routine reads one reference plane through a base pointer and stride. Motion vectors
// staying within the replicated padding read the plane directly; longer excursions first copy
// a clamped window, so any vector the entropy decoder can produce is safe.

// The six-tap half-sample filter, on unclipped integers.
#[Swag.Inline]
func tap6(a, b, c, d, e, f: s32)->s32 => a - 5 * b + 20 * c + 20 * d - 5 * e + f

// Copies the `width` by `height` window at `x`, `y` with edge clamping, including the two
// extra samples each side the six-tap filter reads.
private func copyClamped(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, x, y, width, height, planeWidth, planeHeight: s32)
{
    for row in cast(u64) height
    {
        let srcY = Math.clamp(y + cast(s32) row, -FramePadding, planeHeight + FramePadding - 1)
        for column in cast(u64) width
        {
            let srcX = Math.clamp(x + cast(s32) column, -FramePadding, planeWidth + FramePadding - 1)
            dst[row * dstStride + column] = src[cast(u64) (srcY + FramePadding) * srcStride + cast(u64) (srcX + FramePadding)]
        }
    }
}

// Produces the clipped horizontal half-sample plane at integer rows.
private func halfHorizontal(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, width, height: s32)
{
    for row in cast(u64) height
    {
        let line = src + row * srcStride - 2
        let out  = dst + row * dstStride
        for column in cast(u64) width
        {
            let sum = tap6(cast(s32) line[column], cast(s32) line[column + 1], cast(s32) line[column + 2], cast(s32) line[column + 3], cast(s32) line[column + 4], cast(s32) line[column + 5])
            out[column] = clampPixel((sum + 16) >> 5)
        }
    }
}

// Produces the horizontal half-samples averaged with `anchor`, in one pass.
private func halfHorizontalAvg(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, anchor: [*] u8, anchorStride: u64, width, height: s32)
{
    for row in cast(u64) height
    {
        let line  = src + row * srcStride - 2
        let out   = dst + row * dstStride
        let other = anchor + row * anchorStride
        for column in cast(u64) width
        {
            let sum  = tap6(cast(s32) line[column], cast(s32) line[column + 1], cast(s32) line[column + 2], cast(s32) line[column + 3], cast(s32) line[column + 4], cast(s32) line[column + 5])
            let half = cast(s32) clampPixel((sum + 16) >> 5)
            out[column] = cast(u8) ((half + cast(s32) other[column] + 1) >> 1)
        }
    }
}

// Produces the clipped vertical half-sample plane at integer columns.
private func halfVertical(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, width, height: s32)
{
    for row in cast(u64) height
    {
        let line = src + row * srcStride - 2 * srcStride
        let out  = dst + row * dstStride
        for column in cast(u64) width
        {
            let sum = tap6(cast(s32) line[column], cast(s32) line[column + srcStride], cast(s32) line[column + 2 * srcStride], cast(s32) line[column + 3 * srcStride], cast(s32) line[column + 4 * srcStride], cast(s32) line[column + 5 * srcStride])
            out[column] = clampPixel((sum + 16) >> 5)
        }
    }
}

// Produces the vertical half-samples averaged with `anchor`, in one pass.
private func halfVerticalAvg(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, anchor: [*] u8, anchorStride: u64, width, height: s32)
{
    for row in cast(u64) height
    {
        let line  = src + row * srcStride - 2 * srcStride
        let out   = dst + row * dstStride
        let other = anchor + row * anchorStride
        for column in cast(u64) width
        {
            let sum  = tap6(cast(s32) line[column], cast(s32) line[column + srcStride], cast(s32) line[column + 2 * srcStride], cast(s32) line[column + 3 * srcStride], cast(s32) line[column + 4 * srcStride], cast(s32) line[column + 5 * srcStride])
            let half = cast(s32) clampPixel((sum + 16) >> 5)
            out[column] = cast(u8) ((half + cast(s32) other[column] + 1) >> 1)
        }
    }
}

// Produces the clipped center half-sample plane, filtering the unclipped horizontal sums
// vertically.
private func halfCenter(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, width, height: s32)
{
    // Horizontal six-tap sums for every row the vertical filter reads.
    var sums: [21 * 16] s32 = undefined
    let sumStride           = cast(u64) width
    for row in cast(u64) (height + 5)
    {
        let line = src + row * srcStride - 2 * srcStride - 2
        for column in cast(u64) width do
            sums[row * sumStride + column] = tap6(cast(s32) line[column], cast(s32) line[column + 1], cast(s32) line[column + 2], cast(s32) line[column + 3], cast(s32) line[column + 4], cast(s32) line[column + 5])
    }

    for row in cast(u64) height
    {
        let base = (row + 2) * sumStride
        let out  = dst + row * dstStride
        for column in cast(u64) width
        {
            let sum = tap6(sums[base - 2 * sumStride + column], sums[base - sumStride + column], sums[base + column], sums[base + sumStride + column], sums[base + 2 * sumStride + column], sums[base + 3 * sumStride + column])
            out[column] = clampPixel((sum + 512) >> 10)
        }
    }
}

// Averages two planes with upward rounding.
//
// `(x | y) - (((x ^ y) & 0xFE...) >> 1)` is the rounding-up byte average on independent
// lanes, so a whole row averages in one or two word operations.
func averagePlanes(dst: [*] u8, dstStride: u64, a: [*] u8, aStride: u64, b: [*] u8, bStride: u64, width, height: s32)
{
    const Mask64 = 0xFEFE_FEFE_FEFE_FEFE'u64
    const Mask32 = 0xFEFE_FEFE'u32

    var pd = dst
    var pa = a
    var pb = b
    switch width
    {
    case 16:
        for cast(u64) height
        {
            let a0 = (cast(const [*] u64) pa)[0]
            let b0 = (cast(const [*] u64) pb)[0]
            let a1 = (cast(const [*] u64) pa)[1]
            let b1 = (cast(const [*] u64) pb)[1]
            (cast([*] u64) pd)[0] = (a0 | b0) - (((a0 ^ b0) & Mask64) >> 1)
            (cast([*] u64) pd)[1] = (a1 | b1) - (((a1 ^ b1) & Mask64) >> 1)
            pd                    += dstStride
            pa                    += aStride
            pb                    += bStride
        }

    case 8:
        for cast(u64) height
        {
            let a0 = (cast(const [*] u64) pa)[0]
            let b0 = (cast(const [*] u64) pb)[0]
            (cast([*] u64) pd)[0] = (a0 | b0) - (((a0 ^ b0) & Mask64) >> 1)
            pd += dstStride
            pa += aStride
            pb += bStride
        }

    case 4:
        for cast(u64) height
        {
            let a0 = (cast(const [*] u32) pa)[0]
            let b0 = (cast(const [*] u32) pb)[0]
            (cast([*] u32) pd)[0] = (a0 | b0) - (((a0 ^ b0) & Mask32) >> 1)
            pd += dstStride
            pa += aStride
            pb += bStride
        }

    default:
        for cast(u64) height
        {
            for column in cast(u64) width do
                pd[column] = cast(u8) ((cast(s32) pa[column] + cast(s32) pb[column] + 1) >> 1)
            pd += dstStride
            pa += aStride
            pb += bStride
        }
    }
}

// Motion-compensates one luma block into `dst`.
//
// `x`, `y` is the full-sample position in the reference frame, `fracX`, `fracY` the
// quarter-sample phase, already split from the motion vector by the caller.
func mcLuma(dst: [*] u8, dstStride: u64, reference: *Frame, x, y, fracX, fracY, width, height: s32)
{
    let planeWidth  = reference.mbWidth * 16
    let planeHeight = reference.mbHeight * 16

    // A window outside the replicated padding goes through a clamped copy first.
    var window:    [21 * 24] u8 = undefined
    var src:       [*] u8       = undefined
    var srcStride: u64
    if x - 2 < -FramePadding or y - 2 < -FramePadding or x + width + 3 > planeWidth + FramePadding or y + height + 3 > planeHeight + FramePadding
    {
        copyClamped(@dataof(window), 21, reference.luma.buffer!, reference.strideLuma, x - 2, y - 2, width + 5, height + 5, planeWidth, planeHeight)
        src       = @dataof(window) + 2 * 21 + 2
        srcStride = 21
    }
    else
    {
        src       = reference.luma.buffer! + cast(u64) (y + FramePadding) * reference.strideLuma + cast(u64) (x + FramePadding)
        srcStride = reference.strideLuma
    }

    if fracX == 0 and fracY == 0
    {
        copyPlane(dst, dstStride, src, srcStride, width, height)
        return
    }

    // Each remaining position needs at most one intermediate plane: the averaging half of
    // section 8.4.2.2.1 rides in the last filter pass instead of a pass of its own.
    var planeA: [16 * 16] u8 = undefined
    if fracY == 0
    {
        if fracX == 2 do
            halfHorizontal(dst, dstStride, src, srcStride, width, height)
        else do
            halfHorizontalAvg(dst, dstStride, src, srcStride, fracX == 1 ? src : src + 1, srcStride, width, height)
        return
    }

    if fracX == 0
    {
        if fracY == 2 do
            halfVertical(dst, dstStride, src, srcStride, width, height)
        else do
            halfVerticalAvg(dst, dstStride, src, srcStride, fracY == 1 ? src : src + srcStride, srcStride, width, height)
        return
    }

    if fracX == 2 and fracY == 2
    {
        halfCenter(dst, dstStride, src, srcStride, width, height)
        return
    }

    if fracX == 2
    {
        // Positions f and q: the center half against the nearest horizontal half row.
        halfCenter(@dataof(planeA), 16, src, srcStride, width, height)
        halfHorizontalAvg(dst, dstStride, fracY == 1 ? src : src + srcStride, srcStride, @dataof(planeA), 16, width, height)
        return
    }

    if fracY == 2
    {
        // Positions i and k: the center half against the nearest vertical half column.
        halfCenter(@dataof(planeA), 16, src, srcStride, width, height)
        halfVerticalAvg(dst, dstStride, fracX == 1 ? src : src + 1, srcStride, @dataof(planeA), 16, width, height)
        return
    }

    // Diagonal quarter positions e, g, p, r: nearest horizontal half against nearest
    // vertical half.
    halfHorizontal(@dataof(planeA), 16, fracY == 1 ? src : src + srcStride, srcStride, width, height)
    halfVerticalAvg(dst, dstStride, fracX == 1 ? src : src + 1, srcStride, @dataof(planeA), 16, width, height)
}

// Copies one byte plane. Block widths are 4, 8, or 16, so whole rows move as words;
// x86-64 reads and writes them unaligned.
func copyPlane(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, width, height: s32)
{
    var d = dst
    var s = src
    switch width
    {
    case 16:
        for cast(u64) height
        {
            (cast([*] u64) d)[0] = (cast(const [*] u64) s)[0]
            (cast([*] u64) d)[1] = (cast(const [*] u64) s)[1]
            d                    += dstStride
            s                    += srcStride
        }

    case 8:
        for cast(u64) height
        {
            (cast([*] u64) d)[0] = (cast(const [*] u64) s)[0]
            d += dstStride
            s += srcStride
        }

    case 4:
        for cast(u64) height
        {
            (cast([*] u32) d)[0] = (cast(const [*] u32) s)[0]
            d += dstStride
            s += srcStride
        }

    default:
        for cast(u64) height
        {
            for column in cast(u64) width do
                d[column] = s[column]
            d += dstStride
            s += srcStride
        }
    }
}

// Motion-compensates one chroma block into `dst`, section 8.4.2.2.2.
//
// `x`, `y` is the full-sample chroma position, `fracX`, `fracY` the eighth-sample phase.
func mcChroma(dst: [*] u8, dstStride: u64, reference: *Frame, plane: u32, x, y, fracX, fracY, width, height: s32)
{
    let planeWidth  = reference.mbWidth * 8
    let planeHeight = reference.mbHeight * 8
    let base        = plane == 0 ? reference.cb.buffer! : reference.cr.buffer!

    var window:    [9 * 12] u8 = undefined
    var src:       [*] u8      = undefined
    var srcStride: u64
    if x < -FramePadding or y < -FramePadding or x + width + 1 > planeWidth + FramePadding or y + height + 1 > planeHeight + FramePadding
    {
        copyClamped(@dataof(window), 9, base, reference.strideChroma, x, y, width + 1, height + 1, planeWidth, planeHeight)
        src       = @dataof(window)
        srcStride = 9
    }
    else
    {
        src       = base + cast(u64) (y + FramePadding) * reference.strideChroma + cast(u64) (x + FramePadding)
        srcStride = reference.strideChroma
    }

    // A zero phase on both axes is a plain copy, and a zero phase on one axis collapses the
    // bilinear blend to a two-tap filter; the skipped macroblocks of a still scene all take
    // the copy path.
    if fracX == 0 and fracY == 0
    {
        copyPlane(dst, dstStride, src, srcStride, width, height)
        return
    }

    var out  = dst
    var line = src
    if fracY == 0
    {
        let wl = (8 - fracX) * 8
        let wr = fracX * 8
        for cast(u64) height
        {
            for column in cast(u64) width do
                out[column] = cast(u8) ((wl * cast(s32) line[column] + wr * cast(s32) line[column + 1] + 32) >> 6)
            out  += dstStride
            line += srcStride
        }

        return
    }

    if fracX == 0
    {
        let wt = (8 - fracY) * 8
        let wb = fracY * 8
        for cast(u64) height
        {
            for column in cast(u64) width do
                out[column] = cast(u8) ((wt * cast(s32) line[column] + wb * cast(s32) line[column + srcStride] + 32) >> 6)
            out  += dstStride
            line += srcStride
        }

        return
    }

    let wlt = (8 - fracX) * (8 - fracY)
    let wrt = fracX * (8 - fracY)
    let wlb = (8 - fracX) * fracY
    let wrb = fracX * fracY
    for cast(u64) height
    {
        let below = line + srcStride
        for column in cast(u64) width
        {
            let value = wlt * cast(s32) line[column] + wrt * cast(s32) line[column + 1] + wlb * cast(s32) below[column] + wrb * cast(s32) below[column + 1]
            out[column] = cast(u8) ((value + 32) >> 6)
        }

        out  += dstStride
        line += srcStride
    }
}

// Applies one explicit weight to a predicted block, section 8.4.2.3.2.
func weightUni(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, width, height: s32, logDenom, weight, offset: s32)
{
    // A zero denominator shifts by nothing with no rounding term, so one expression serves
    // both spellings of section 8.4.2.3.2.
    let rounding = logDenom > 0 ? 1's32 << cast(u32) (logDenom - 1) : 0's32
    var out      = dst
    var line     = src
    for cast(u64) height
    {
        for column in cast(u64) width do
            out[column] = clampPixel(((cast(s32) line[column] * weight + rounding) >> cast(u32) logDenom) + offset)
        out  += dstStride
        line += srcStride
    }
}

// Combines two predicted blocks with explicit or implicit weights.
func weightBi(dst: [*] u8, dstStride: u64, src0, src1: [*] u8, srcStride: u64, width, height: s32, logDenom, weight0, weight1, offset0, offset1: s32)
{
    let rounding = 1's32 << cast(u32) logDenom
    let offset   = (offset0 + offset1 + 1) >> 1
    var out      = dst
    var line0    = src0
    var line1    = src1
    for cast(u64) height
    {
        for column in cast(u64) width do
            out[column] = clampPixel(((cast(s32) line0[column] * weight0 + cast(s32) line1[column] * weight1 + rounding) >> cast(u32) (logDenom + 1)) + offset)
        out   += dstStride
        line0 += srcStride
        line1 += srcStride
    }
}
