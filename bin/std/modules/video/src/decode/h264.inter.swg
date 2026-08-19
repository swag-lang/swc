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
        for column in cast(u64) width
        {
            let sum = tap6(cast(s32) line[column], cast(s32) line[column + 1], cast(s32) line[column + 2], cast(s32) line[column + 3], cast(s32) line[column + 4], cast(s32) line[column + 5])
            dst[row * dstStride + column] = clampPixel((sum + 16) >> 5)
        }
    }
}

// Produces the clipped vertical half-sample plane at integer columns.
private func halfVertical(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, width, height: s32)
{
    for row in cast(u64) height
    {
        let line = src + row * srcStride - 2 * srcStride
        for column in cast(u64) width
        {
            let sum = tap6(cast(s32) line[column], cast(s32) line[column + srcStride], cast(s32) line[column + 2 * srcStride], cast(s32) line[column + 3 * srcStride], cast(s32) line[column + 4 * srcStride], cast(s32) line[column + 5 * srcStride])
            dst[row * dstStride + column] = clampPixel((sum + 16) >> 5)
        }
    }
}

// Produces the clipped center half-sample plane, filtering the unclipped horizontal sums
// vertically.
private func halfCenter(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, width, height: s32)
{
    // Horizontal six-tap sums for every row the vertical filter reads.
    var sums: [21 * 16] s32 = undefined
    let sumStride = cast(u64) width
    for row in cast(u64) (height + 5)
    {
        let line = src + row * srcStride - 2 * srcStride - 2
        for column in cast(u64) width do
            sums[row * sumStride + column] = tap6(cast(s32) line[column], cast(s32) line[column + 1], cast(s32) line[column + 2], cast(s32) line[column + 3], cast(s32) line[column + 4], cast(s32) line[column + 5])
    }

    for row in cast(u64) height
    {
        let base = (row + 2) * sumStride
        for column in cast(u64) width
        {
            let sum = tap6(sums[base - 2 * sumStride + column], sums[base - sumStride + column], sums[base + column], sums[base + sumStride + column], sums[base + 2 * sumStride + column], sums[base + 3 * sumStride + column])
            dst[row * dstStride + column] = clampPixel((sum + 512) >> 10)
        }
    }
}

// Averages two planes with upward rounding.
private func averagePlanes(dst: [*] u8, dstStride: u64, a: [*] u8, aStride: u64, b: [*] u8, bStride: u64, width, height: s32)
{
    for row in cast(u64) height
    {
        for column in cast(u64) width do
            dst[row * dstStride + column] = cast(u8) ((cast(s32) a[row * aStride + column] + cast(s32) b[row * bStride + column] + 1) >> 1)
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
    var window: [21 * 24] u8 = undefined
    var src: [*] u8 = undefined
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
        for row in cast(u64) height
        {
            for column in cast(u64) width do
                dst[row * dstStride + column] = src[row * srcStride + column]
        }

        return
    }

    var planeA: [16 * 16] u8 = undefined
    var planeB: [16 * 16] u8 = undefined
    if fracY == 0
    {
        // Horizontal half-samples, averaged with the nearest integer sample off the halves.
        halfHorizontal(@dataof(planeA), 16, src, srcStride, width, height)
        if fracX == 2
        {
            copyPlane(dst, dstStride, @dataof(planeA), 16, width, height)
            return
        }

        let anchor = fracX == 1 ? src : src + 1
        averagePlanes(dst, dstStride, @dataof(planeA), 16, anchor, srcStride, width, height)
        return
    }

    if fracX == 0
    {
        halfVertical(@dataof(planeA), 16, src, srcStride, width, height)
        if fracY == 2
        {
            copyPlane(dst, dstStride, @dataof(planeA), 16, width, height)
            return
        }

        let anchor = fracY == 1 ? src : src + srcStride
        averagePlanes(dst, dstStride, @dataof(planeA), 16, anchor, srcStride, width, height)
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
        halfHorizontal(@dataof(planeB), 16, fracY == 1 ? src : src + srcStride, srcStride, width, height)
        averagePlanes(dst, dstStride, @dataof(planeA), 16, @dataof(planeB), 16, width, height)
        return
    }

    if fracY == 2
    {
        // Positions i and k: the center half against the nearest vertical half column.
        halfCenter(@dataof(planeA), 16, src, srcStride, width, height)
        halfVertical(@dataof(planeB), 16, fracX == 1 ? src : src + 1, srcStride, width, height)
        averagePlanes(dst, dstStride, @dataof(planeA), 16, @dataof(planeB), 16, width, height)
        return
    }

    // Diagonal quarter positions e, g, p, r: nearest horizontal half against nearest
    // vertical half.
    halfHorizontal(@dataof(planeA), 16, fracY == 1 ? src : src + srcStride, srcStride, width, height)
    halfVertical(@dataof(planeB), 16, fracX == 1 ? src : src + 1, srcStride, width, height)
    averagePlanes(dst, dstStride, @dataof(planeA), 16, @dataof(planeB), 16, width, height)
}

// Copies one byte plane.
func copyPlane(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, width, height: s32)
{
    for row in cast(u64) height
    {
        for column in cast(u64) width do
            dst[row * dstStride + column] = src[row * srcStride + column]
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

    var window: [9 * 12] u8 = undefined
    var src: [*] u8 = undefined
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

    let weightRight  = fracX
    let weightBottom = fracY
    let weightLeft   = 8 - fracX
    let weightTop    = 8 - fracY
    for row in cast(u64) height
    {
        let line = src + row * srcStride
        for column in cast(u64) width
        {
            let value = weightLeft * weightTop * cast(s32) line[column] +
                        weightRight * weightTop * cast(s32) line[column + 1] +
                        weightLeft * weightBottom * cast(s32) line[column + srcStride] +
                        weightRight * weightBottom * cast(s32) line[column + srcStride + 1]
            dst[row * dstStride + column] = cast(u8) ((value + 32) >> 6)
        }
    }
}

// Applies one explicit weight to a predicted block, section 8.4.2.3.2.
func weightUni(dst: [*] u8, dstStride: u64, src: [*] u8, srcStride: u64, width, height: s32, logDenom, weight, offset: s32)
{
    for row in cast(u64) height
    {
        for column in cast(u64) width
        {
            let sample = cast(s32) src[row * srcStride + column]
            var value: s32
            if logDenom > 0 do
                value = ((sample * weight + (1 << cast(u32) (logDenom - 1))) >> cast(u32) logDenom) + offset
            else do
                value = sample * weight + offset
            dst[row * dstStride + column] = clampPixel(value)
        }
    }
}

// Combines two predicted blocks with explicit or implicit weights.
func weightBi(dst: [*] u8, dstStride: u64, src0, src1: [*] u8, srcStride: u64, width, height: s32, logDenom, weight0, weight1, offset0, offset1: s32)
{
    let rounding = 1's32 << cast(u32) logDenom
    let offset   = (offset0 + offset1 + 1) >> 1
    for row in cast(u64) height
    {
        for column in cast(u64) width
        {
            let value = ((cast(s32) src0[row * srcStride + column] * weight0 + cast(s32) src1[row * srcStride + column] * weight1 + rounding) >> cast(u32) (logDenom + 1)) + offset
            dst[row * dstStride + column] = clampPixel(value)
        }
    }
}
