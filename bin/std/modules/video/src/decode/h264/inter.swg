#global namespace H264
#global internal

using Core, Core.Math

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

// Eight unclipped six-tap sums on widened byte lanes. Every sum fits s16: the
// positive taps reach 20 * 510 + 510 = 10710 and the negative ones -2550, so
// the arithmetic never wraps.
#[Swag.Inline]
private func tap6Raw16(inner, outer, edges: Simd.U16x8)->Simd.S16x8
{
    return cast #bit(Simd.S16x8) edges + cast #bit(Simd.S16x8) inner * 20 - cast #bit(Simd.S16x8) outer * 5
}

// Eight six-tap half-samples on widened byte lanes; the caller's saturating
// pack is exactly the scalar clamp.
#[Swag.Inline]
private func tap6Half16(inner, outer, edges: Simd.U16x8)->Simd.S16x8
{
    return (tap6Raw16(inner, outer, edges) + 16) >> 5
}

// One vertical six-tap over four widened sums, with the center rounding shift.
// The 32-bit intermediates stay far inside the lane range: the sums reach
// ±10710, so the filtered value reaches about ±470000.
#[Swag.Inline]
private func tap6CenterQuad(inner, outer, edges: Simd.S32x4)->Simd.S32x4
{
    let sum = edges + inner * 20 - outer * 5
    return (sum + 512) >> 10
}

// One vertical six-tap over eight 16-bit sums, back to 16-bit lanes; the
// shifted result reaches about ±460, so the signed pack never saturates and
// the caller's unsigned pack is exactly the scalar clamp.
#[Swag.Inline]
private func tap6Center8(inner, outer, edges: Simd.S16x8)->Simd.S16x8
{
    let lo = tap6CenterQuad(Simd.widenLow(inner), Simd.widenLow(outer), Simd.widenLow(edges))
    let hi = tap6CenterQuad(Simd.widenHigh(inner), Simd.widenHigh(outer), Simd.widenHigh(edges))
    return Simd.packSigned(lo, hi)
}

// Sixteen six-tap half-samples in one pass: rows spaced by `stride` widen to
// 16-bit lanes, filter, and narrow back through the saturating pack. With a
// stride of one this is the horizontal filter, reading the same bytes the
// scalar loop touches.
#[Swag.Inline]
private func tap6Row16(line: const [*] u8, stride: u64)->Simd.U8x16
{
    let r0 = Simd.load(line)
    let r1 = Simd.load(line + stride)
    let r2 = Simd.load(line + 2 * stride)
    let r3 = Simd.load(line + 3 * stride)
    let r4 = Simd.load(line + 4 * stride)
    let r5 = Simd.load(line + 5 * stride)

    let lo = tap6Half16(Simd.widenLow(r2) + Simd.widenLow(r3), Simd.widenLow(r1) + Simd.widenLow(r4), Simd.widenLow(r0) + Simd.widenLow(r5))
    let hi = tap6Half16(Simd.widenHigh(r2) + Simd.widenHigh(r3), Simd.widenHigh(r1) + Simd.widenHigh(r4), Simd.widenHigh(r0) + Simd.widenHigh(r5))
    return Simd.packUnsigned(lo, hi)
}

// Eight six-tap half-samples in the low lanes: one sixteen-byte load per tap
// covers the thirteen bytes the shifted lanes read.
#[Swag.Inline]
private func tap6Row8(line: const [*] u8, stride: u64)->Simd.U8x16
{
    let r0 = Simd.load(line)
    let r1 = Simd.load(line + stride)
    let r2 = Simd.load(line + 2 * stride)
    let r3 = Simd.load(line + 3 * stride)
    let r4 = Simd.load(line + 4 * stride)
    let r5 = Simd.load(line + 5 * stride)

    let lo = tap6Half16(Simd.widenLow(r2) + Simd.widenLow(r3), Simd.widenLow(r1) + Simd.widenLow(r4), Simd.widenLow(r0) + Simd.widenLow(r5))
    return Simd.packUnsigned(lo, lo)
}

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
    if width == 16
    {
        for row in cast(u64) height do
            Simd.store(dst + row * dstStride, tap6Row16(src + row * srcStride - 2, 1))
        return
    }

    if width == 8 or width == 4
    {
        for row in cast(u64) height
        {
            let half = tap6Row8(src + row * srcStride - 2, 1)
            if width == 8 do
                Simd.storeLow8(dst + row * dstStride, half)
            else do
                Simd.storeLow4(dst + row * dstStride, half)
        }

        return
    }

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
    if width == 16
    {
        for row in cast(u64) height
        {
            let half  = tap6Row16(src + row * srcStride - 2, 1)
            let other = Simd.load(anchor + row * anchorStride)
            Simd.store(dst + row * dstStride, Simd.average(half, other))
        }

        return
    }

    if width == 8 or width == 4
    {
        for row in cast(u64) height
        {
            let half  = tap6Row8(src + row * srcStride - 2, 1)
            let other = Simd.load(anchor + row * anchorStride)
            let mixed = Simd.average(half, other)
            if width == 8 do
                Simd.storeLow8(dst + row * dstStride, mixed)
            else do
                Simd.storeLow4(dst + row * dstStride, mixed)
        }

        return
    }

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
    if width == 16
    {
        for row in cast(u64) height do
            Simd.store(dst + row * dstStride, tap6Row16(src + row * srcStride - 2 * srcStride, srcStride))
        return
    }

    if width == 8 or width == 4
    {
        for row in cast(u64) height
        {
            let half = tap6Row8(src + row * srcStride - 2 * srcStride, srcStride)
            if width == 8 do
                Simd.storeLow8(dst + row * dstStride, half)
            else do
                Simd.storeLow4(dst + row * dstStride, half)
        }

        return
    }

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
    if width == 16
    {
        for row in cast(u64) height
        {
            let half  = tap6Row16(src + row * srcStride - 2 * srcStride, srcStride)
            let other = Simd.load(anchor + row * anchorStride)
            Simd.store(dst + row * dstStride, Simd.average(half, other))
        }

        return
    }

    if width == 8 or width == 4
    {
        for row in cast(u64) height
        {
            let half  = tap6Row8(src + row * srcStride - 2 * srcStride, srcStride)
            let other = Simd.load(anchor + row * anchorStride)
            let mixed = Simd.average(half, other)
            if width == 8 do
                Simd.storeLow8(dst + row * dstStride, mixed)
            else do
                Simd.storeLow4(dst + row * dstStride, mixed)
        }

        return
    }

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
    if width == 16
    {
        halfCenter16(dst, dstStride, src, srcStride, height)
        return
    }

    if width == 8 or width == 4
    {
        halfCenter8(dst, dstStride, src, srcStride, width, height)
        return
    }

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

// Sixteen center half-samples per row: the horizontal sums stay in 16-bit
// lanes, two vectors per row, and the vertical pass widens them on the fly.
private func halfCenter16(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, height: s32)
{
    var sums: [21 * 2] Simd.S16x8 = undefined
    for row in cast(u64) (height + 5)
    {
        let line = src + row * srcStride - 2 * srcStride - 2
        let r0   = Simd.load(line)
        let r1   = Simd.load(line + 1)
        let r2   = Simd.load(line + 2)
        let r3   = Simd.load(line + 3)
        let r4   = Simd.load(line + 4)
        let r5   = Simd.load(line + 5)
        sums[row * 2]     = tap6Raw16(Simd.widenLow(r2) + Simd.widenLow(r3), Simd.widenLow(r1) + Simd.widenLow(r4), Simd.widenLow(r0) + Simd.widenLow(r5))
        sums[row * 2 + 1] = tap6Raw16(Simd.widenHigh(r2) + Simd.widenHigh(r3), Simd.widenHigh(r1) + Simd.widenHigh(r4), Simd.widenHigh(r0) + Simd.widenHigh(r5))
    }

    for row in cast(u64) height
    {
        let lo = tap6Center8(sums[row * 2 + 4] + sums[row * 2 + 6], sums[row * 2 + 2] + sums[row * 2 + 8], sums[row * 2] + sums[row * 2 + 10])
        let hi = tap6Center8(sums[row * 2 + 5] + sums[row * 2 + 7], sums[row * 2 + 3] + sums[row * 2 + 9], sums[row * 2 + 1] + sums[row * 2 + 11])
        Simd.store(dst + row * dstStride, Simd.packUnsigned(lo, hi))
    }
}

// Same shape for the narrower blocks: one sum vector per row, the low lanes
// carrying the block.
private func halfCenter8(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, width, height: s32)
{
    var sums: [21] Simd.S16x8 = undefined
    for row in cast(u64) (height + 5)
    {
        let line = src + row * srcStride - 2 * srcStride - 2
        let r0   = Simd.load(line)
        let r1   = Simd.load(line + 1)
        let r2   = Simd.load(line + 2)
        let r3   = Simd.load(line + 3)
        let r4   = Simd.load(line + 4)
        let r5   = Simd.load(line + 5)
        sums[row] = tap6Raw16(Simd.widenLow(r2) + Simd.widenLow(r3), Simd.widenLow(r1) + Simd.widenLow(r4), Simd.widenLow(r0) + Simd.widenLow(r5))
    }

    for row in cast(u64) height
    {
        let half   = tap6Center8(sums[row + 2] + sums[row + 3], sums[row + 1] + sums[row + 4], sums[row] + sums[row + 5])
        let packed = Simd.packUnsigned(half, half)
        if width == 8 do
            Simd.storeLow8(dst + row * dstStride, packed)
        else do
            Simd.storeLow4(dst + row * dstStride, packed)
    }
}

// Averages two planes with upward rounding.
//
// A sixteen-wide row is one packed rounding average; the narrower rows keep
// the word trick: `(x | y) - (((x ^ y) & 0xFE...) >> 1)` is the rounding-up
// byte average on independent lanes.
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
            let va = Simd.load(pa)
            let vb = Simd.load(pb)
            Simd.store(pd, Simd.average(va, vb))
            pd += dstStride
            pa += aStride
            pb += bStride
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

    // A window outside the replicated padding goes through a clamped copy first. The
    // right bound uses the sixteen-byte span of the packed row loads whatever the
    // block width, so the narrow filters may read wide.
    var window:    [21 * 24] u8 = undefined
    var src:       [*] u8       = undefined
    var srcStride: u64
    if x - 2 < -FramePadding or y - 2 < -FramePadding or x + 19 > planeWidth + FramePadding or y + height + 3 > planeHeight + FramePadding
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
            Simd.store(d, Simd.load(s))
            d += dstStride
            s += srcStride
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

    // The right bound uses the sixteen-byte span of the packed row loads whatever the
    // block width, so the narrow blends may read wide.
    var window:    [9 * 12] u8 = undefined
    var src:       [*] u8      = undefined
    var srcStride: u64
    if x < -FramePadding or y < -FramePadding or x + 17 > planeWidth + FramePadding or y + height + 1 > planeHeight + FramePadding
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
        if width == 8 or width == 4
        {
            for cast(u64) height
            {
                let a = Simd.widenLow(Simd.load(line))
                let b = Simd.widenLow(Simd.load(line + 1))
                storeChromaBlend(out, width, a * cast(u16) wl + b * cast(u16) wr)
                out  += dstStride
                line += srcStride
            }

            return
        }

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
        if width == 8 or width == 4
        {
            for cast(u64) height
            {
                let a = Simd.widenLow(Simd.load(line))
                let b = Simd.widenLow(Simd.load(line + srcStride))
                storeChromaBlend(out, width, a * cast(u16) wt + b * cast(u16) wb)
                out  += dstStride
                line += srcStride
            }

            return
        }

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
    if width == 8 or width == 4
    {
        for cast(u64) height
        {
            let below = line + srcStride
            let a     = Simd.widenLow(Simd.load(line))
            let b     = Simd.widenLow(Simd.load(line + 1))
            let c     = Simd.widenLow(Simd.load(below))
            let d     = Simd.widenLow(Simd.load(below + 1))
            storeChromaBlend(out, width, a * cast(u16) wlt + b * cast(u16) wrt + c * cast(u16) wlb + d * cast(u16) wrb)
            out  += dstStride
            line += srcStride
        }

        return
    }

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

// Rounds, narrows, and stores one row of blended chroma lanes. The weights of
// one blend sum to 64, so the accumulators peak at 64 * 255 + 32, well inside
// the unsigned lanes, and the shifted lanes are plain bytes.
#[Swag.Inline]
private func storeChromaBlend(out: [*] u8, width: s32, value: Simd.U16x8)
{
    let bytes  = cast #bit(Simd.S16x8) ((value + 32) >> 6)
    let packed = Simd.packUnsigned(bytes, bytes)
    if width == 8 do
        Simd.storeLow8(out, packed)
    else do
        Simd.storeLow4(out, packed)
}

// Applies one explicit weight to a predicted block, section 8.4.2.3.2.
#[Swag.Inline]
private func storeWeightedRow(dst: [*] u8, width: s32, value: Simd.U8x16)
{
    switch width
    {
    case 16: Simd.store(dst, value)
    case 8:  Simd.storeLow8(dst, value)
    case 4:  Simd.storeLow4(dst, value)
    case 2:  dst[as u16] = (cast #bit(Simd.U16x8) value)[0]
    default: Debug.assert(false)
    }
}

#[Swag.Inline]
private func weightUniRow(pixels: Simd.U8x16, logDenom, weight, offset: s32)->Simd.U8x16
{
    let rounding = logDenom > 0 ? 1's16 << cast(u32) (logDenom - 1) : 0's16
    let weights  = Simd.splat(cast(s16) weight)
    let bias     = Simd.splat(rounding)
    let offsets  = Simd.splat(cast(s16) offset)
    let low      = ((cast #bit(Simd.S16x8) Simd.widenLow(pixels)) * weights + bias) >> cast(u32) logDenom
    let high     = ((cast #bit(Simd.S16x8) Simd.widenHigh(pixels)) * weights + bias) >> cast(u32) logDenom
    return Simd.packUnsigned(low + offsets, high + offsets)
}

func weightUni(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, width, height: s32, logDenom, weight, offset: s32)
{
    if srcStride >= 16 and (width == 2 or width == 4 or width == 8 or width == 16)
    {
        var out  = dst
        var line = src
        for cast(u64) height
        {
            storeWeightedRow(out, width, weightUniRow(Simd.load(line), logDenom, weight, offset))
            out  += dstStride
            line += srcStride
        }

        return
    }

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
#[Swag.Inline]
private func weightBiQuads(a, b: Simd.S32x4, weight0, weight1, rounding, shift, offset: s32)->Simd.S32x4
{
    return ((a * weight0 + b * weight1 + rounding) >> cast(u32) shift) + offset
}

#[Swag.Inline]
private func weightBiRow(pixels0, pixels1: Simd.U8x16, logDenom, weight0, weight1, offset0, offset1: s32)->Simd.U8x16
{
    let rounding = 1's32 << cast(u32) logDenom
    let offset   = (offset0 + offset1 + 1) >> 1
    let shift    = logDenom + 1
    let p0Low    = Simd.widenLow(pixels0)
    let p0High   = Simd.widenHigh(pixels0)
    let p1Low    = Simd.widenLow(pixels1)
    let p1High   = Simd.widenHigh(pixels1)
    let r0       = weightBiQuads(cast #bit(Simd.S32x4) Simd.widenLow(p0Low), cast #bit(Simd.S32x4) Simd.widenLow(p1Low), weight0, weight1, rounding, shift, offset)
    let r1       = weightBiQuads(cast #bit(Simd.S32x4) Simd.widenHigh(p0Low), cast #bit(Simd.S32x4) Simd.widenHigh(p1Low), weight0, weight1, rounding, shift, offset)
    let r2       = weightBiQuads(cast #bit(Simd.S32x4) Simd.widenLow(p0High), cast #bit(Simd.S32x4) Simd.widenLow(p1High), weight0, weight1, rounding, shift, offset)
    let r3       = weightBiQuads(cast #bit(Simd.S32x4) Simd.widenHigh(p0High), cast #bit(Simd.S32x4) Simd.widenHigh(p1High), weight0, weight1, rounding, shift, offset)
    let low      = Simd.packUnsigned(r0, r1)
    let high     = Simd.packUnsigned(r2, r3)
    return Simd.packUnsigned(cast #bit(Simd.S16x8) low, cast #bit(Simd.S16x8) high)
}

func weightBi(dst: [*] u8, dstStride: u64, src0, src1: [*] u8, srcStride: u64, width, height: s32, logDenom, weight0, weight1, offset0, offset1: s32)
{
    if srcStride >= 16 and (width == 2 or width == 4 or width == 8 or width == 16)
    {
        var out   = dst
        var line0 = src0
        var line1 = src1
        for cast(u64) height
        {
            storeWeightedRow(out, width, weightBiRow(Simd.load(line0), Simd.load(line1), logDenom, weight0, weight1, offset0, offset1))
            out   += dstStride
            line0 += srcStride
            line1 += srcStride
        }

        return
    }

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
