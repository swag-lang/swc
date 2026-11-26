//! Format: WebP still-image decoder component.
//! Supported: RIFF WebP containing lossy VP8 or lossless VP8L still images, including supported alpha chunks.
//! Not supported: Animated WebP and unsupported alpha preprocessing or compression methods.
//! Role: This file owns VP8 in-loop filtering.
//
#global namespace Webp

using Core, Math.Simd

func vp8Abs(value: s32)->s32 => value < 0 ? -value : value

func vp8Clamp15(value: s32)->s32 => vp8Clip(value, -16, 15)

func vp8Clamp127(value: s32)->s32 => vp8Clip(value, -128, 127)

func vp8Filter2(pixels: [*] u8, level, index, iStep, jStep: s32)
{
    var offset = index
    for 16
    {
        let p1 = cast(s32, pixels[offset - 2 * jStep])
        let p0 = cast(s32, pixels[offset - 1 * jStep])
        let q0 = cast(s32, pixels[offset])
        let q1 = cast(s32, pixels[offset + 1 * jStep])
        if 2 * vp8Abs(p0 - q0) + vp8Abs(p1 - q1) / 2 <= level
        {
            let a  = 3 * (q0 - p0) + vp8Clamp127(p1 - q1)
            let a1 = vp8Clamp15((a + 4) >> 3)
            let a2 = vp8Clamp15((a + 3) >> 3)
            pixels[offset - jStep] = vp8Clip8(p0 + a2)
            pixels[offset]         = vp8Clip8(q0 - a1)
        }

        offset += iStep
    }
}

#[Swag.Inline]
func vp8ByteDifference(first, second: U8x16)->U8x16
{
    return subSaturating(first, second) | subSaturating(second, first)
}

#[Swag.Inline]
func vp8RoundByteDelta(delta: S8x16, bias: s8)->S8x16
{
    let biased = addSaturating(delta, splat(bias))
    return packSigned(widenLow(biased) >> 3, widenHigh(biased) >> 3)
}

#[Swag.Inline]
func(INNER: bool) vp8FilterByteSamples(samples: [*] U8x16, edgeLimit, inLimit, hevLimit: U8x16)->bool
{
    let p3 = samples[0]
    let p2 = samples[1]
    let p1 = samples[2]
    let p0 = samples[3]
    let q0 = samples[4]
    let q1 = samples[5]
    let q2 = samples[6]
    let q3 = samples[7]

    let cross = vp8ByteDifference(p0, q0)

    // Clearing each low bit lets the word shift halve every byte independently.
    let outer     = vp8ByteDifference(p1, q1) & splat(0xFE'u8)
    let halfOuter = cast #bit(U8x16, (cast #bit(U16x8, outer) >> 1))
    let across    = addSaturating(addSaturating(cross, cross), halfOuter)
    let gap       = Math.max(vp8ByteDifference(p1, p0), vp8ByteDifference(q1, q0))
    let insideP   = Math.max(vp8ByteDifference(p3, p2), vp8ByteDifference(p2, p1))
    let insideQ   = Math.max(vp8ByteDifference(q3, q2), vp8ByteDifference(q2, q1))
    let inside    = Math.max(gap, Math.max(insideP, insideQ))
    let active    = (across <= edgeLimit) & (inside <= inLimit)
    if not anyTrue(active) do
        return false

    let notHev = gap <= hevLimit
    let wide   = active & notHev
    let sign   = splat(0x80'u8)
    let sp1    = cast #bit(S8x16, (p1 ^ sign))
    let sp0    = cast #bit(S8x16, (p0 ^ sign))
    let sq0    = cast #bit(S8x16, (q0 ^ sign))
    let sq1    = cast #bit(S8x16, (q1 ^ sign))

    // An active lane has |q0 - p0| <= edgeLimit / 2, at most 96. Adding the
    // same signed step three times preserves the clipped VP8 delta.
    let step = subSaturating(sq0, sp0)
    var base = subSaturating(sp1, sq1)
    #static if INNER do
        base &= cast #bit(S8x16, ~notHev)
    let delta = addSaturating(addSaturating(addSaturating(base, step), step), step)

    #static if INNER
    {
        let adjust = delta & cast #bit(S8x16, active)
        let a1     = vp8RoundByteDelta(adjust, 4)
        let a2     = vp8RoundByteDelta(adjust, 3)
        let half   = average(cast #bit(U8x16, a1) ^ sign, splat(0'u8)) - splat(64'u8)
        let a3     = cast #bit(S8x16, (half & wide))
        samples[2] = cast #bit(U8x16, addSaturating(sp1, a3)) ^ sign
        samples[3] = cast #bit(U8x16, addSaturating(sp0, a2)) ^ sign
        samples[4] = cast #bit(U8x16, subSaturating(sq0, a1)) ^ sign
        samples[5] = cast #bit(U8x16, subSaturating(sq1, a3)) ^ sign
    }
    else
    {
        let narrow = delta & cast #bit(S8x16, (active & ~notHev))
        let strong = delta & cast #bit(S8x16, wide)
        let lo     = widenLow(strong) * 9
        let hi     = widenHigh(strong) * 9
        let loBias = lo + 63
        let hiBias = hi + 63
        let w2     = packSigned(loBias >> 7, hiBias >> 7)
        let w1     = packSigned((loBias + lo) >> 7, (hiBias + hi) >> 7)
        let w0     = packSigned((loBias + 2 * lo) >> 7, (hiBias + 2 * hi) >> 7)
        let a1     = w0 + vp8RoundByteDelta(narrow, 4)
        let a2     = w0 + vp8RoundByteDelta(narrow, 3)
        let sp2    = cast #bit(S8x16, (p2 ^ sign))
        let sq2    = cast #bit(S8x16, (q2 ^ sign))
        samples[1] = cast #bit(U8x16, addSaturating(sp2, w2)) ^ sign
        samples[2] = cast #bit(U8x16, addSaturating(sp1, w1)) ^ sign
        samples[3] = cast #bit(U8x16, addSaturating(sp0, a2)) ^ sign
        samples[4] = cast #bit(U8x16, subSaturating(sq0, a1)) ^ sign
        samples[5] = cast #bit(U8x16, subSaturating(sq1, w1)) ^ sign
        samples[6] = cast #bit(U8x16, subSaturating(sq2, w2)) ^ sign
    }

    return true
}

func(INNER: bool) vp8FilterHorizontalLuma(edge: [*] u8, stride, level, iLevel, hLevel: s32)
{
    let first = edge - 4 * stride
    var samples: [8] U8x16
    for row in 8 do
        samples[row] = load(first + row * stride)

    if not vp8FilterByteSamples'INNER(&samples[0], splat(cast(u8, level)), splat(cast(u8, iLevel)), splat(cast(u8, hLevel))) do
        return

    const Start = INNER ? 2 : 1
    for row in Start until 8 - Start do
        store(first + row * stride, samples[row])
}

func(INNER: bool) vp8FilterHorizontalChroma(cb, cr: [*] u8, stride, level, iLevel, hLevel: s32)
{
    let cbFirst = cb - 4 * stride
    let crFirst = cr - 4 * stride
    var samples: [8] U8x16
    for row in 8
    {
        let cbRow = cast(const [*] u64, cbFirst + row * stride)[0]
        let crRow = cast(const [*] u64, crFirst + row * stride)[0]
        samples[row] = cast #bit(U8x16, interleaveLow(splat(cbRow), splat(crRow)))
    }

    if not vp8FilterByteSamples'INNER(&samples[0], splat(cast(u8, level)), splat(cast(u8, iLevel)), splat(cast(u8, hLevel))) do
        return

    const Start = INNER ? 2 : 1
    for row in Start until 8 - Start
    {
        let lanes = cast #bit(U64x2, samples[row])
        cast([*] u64, cbFirst + row * stride)[0] = lanes[0]
        cast([*] u64, crFirst + row * stride)[0] = lanes[1]
    }
}

// A byte tile holds eight rows, with two rows in each vector. Its transpose
// has the same layout, with each row becoming one edge sample position.
#[Swag.Inline]
private func vp8TransposeByteTile(tile: *[4] U8x16)
{
    let a           = cast #bit(U16x8, interleaveLow(tile[][0], align(tile[][0], tile[][0], 8)))
    let b           = cast #bit(U16x8, interleaveLow(tile[][1], align(tile[][1], tile[][1], 8)))
    let c           = cast #bit(U16x8, interleaveLow(tile[][2], align(tile[][2], tile[][2], 8)))
    let d           = cast #bit(U16x8, interleaveLow(tile[][3], align(tile[][3], tile[][3], 8)))
    let leftTop     = cast #bit(U32x4, interleaveLow(a, b))
    let rightTop    = cast #bit(U32x4, interleaveHigh(a, b))
    let leftBottom  = cast #bit(U32x4, interleaveLow(c, d))
    let rightBottom = cast #bit(U32x4, interleaveHigh(c, d))
    tile[][0] = cast #bit(U8x16, interleaveLow(leftTop, leftBottom))
    tile[][1] = cast #bit(U8x16, interleaveHigh(leftTop, leftBottom))
    tile[][2] = cast #bit(U8x16, interleaveLow(rightTop, rightBottom))
    tile[][3] = cast #bit(U8x16, interleaveHigh(rightTop, rightBottom))
}

#[Swag.Inline]
private func vp8LoadByteRows(base: const [*] u8, stride: s32)->U8x16
{
    let first  = cast(const [*] u64, base)[0]
    let second = cast(const [*] u64, base + stride)[0]
    return cast #bit(U8x16, interleaveLow(splat(first), splat(second)))
}

#[Swag.Inline]
private func vp8StoreByteRows(base: [*] u8, stride: s32, pair: U8x16)
{
    storeLow8(base, pair)
    storeLow8(base + stride, align(pair, pair, 8))
}

// Pack corresponding columns from the two eight-row tiles into one vector.
#[Swag.Inline]
private func vp8LoadVerticalBytes(top, bottom: const [*] u8, stride: s32, samples: [*] U8x16)
{
    var upper, lower: [4] U8x16
    for pair in 4
    {
        let offset = pair * 2 * stride
        upper[pair] = vp8LoadByteRows(top + offset, stride)
        lower[pair] = vp8LoadByteRows(bottom + offset, stride)
    }

    vp8TransposeByteTile(&upper)
    vp8TransposeByteTile(&lower)
    for pair in 4
    {
        let a = cast #bit(U64x2, upper[pair])
        let b = cast #bit(U64x2, lower[pair])
        samples[2 * pair]     = cast #bit(U8x16, interleaveLow(a, b))
        samples[2 * pair + 1] = cast #bit(U8x16, interleaveHigh(a, b))
    }
}

#[Swag.Inline]
private func vp8StoreVerticalBytes(top, bottom: [*] u8, stride: s32, samples: [*] U8x16)
{
    var upper, lower: [4] U8x16
    for pair in 4
    {
        let a = cast #bit(U64x2, samples[2 * pair])
        let b = cast #bit(U64x2, samples[2 * pair + 1])
        upper[pair] = cast #bit(U8x16, interleaveLow(a, b))
        lower[pair] = cast #bit(U8x16, interleaveHigh(a, b))
    }

    vp8TransposeByteTile(&upper)
    vp8TransposeByteTile(&lower)
    for pair in 4
    {
        let offset = pair * 2 * stride
        vp8StoreByteRows(top + offset, stride, upper[pair])
        vp8StoreByteRows(bottom + offset, stride, lower[pair])
    }
}

// Luma supplies two consecutive eight-row tiles and chroma supplies one per plane.
private func(INNER: bool) vp8FilterVerticalPair(top, bottom: [*] u8, stride, level, iLevel, hLevel: s32)
{
    let first  = top - 4
    let second = bottom - 4
    var samples: [8] U8x16
    vp8LoadVerticalBytes(first, second, stride, &samples[0])
    if vp8FilterByteSamples'INNER(&samples[0], splat(cast(u8, level)), splat(cast(u8, iLevel)), splat(cast(u8, hLevel))) do
        vp8StoreVerticalBytes(first, second, stride, &samples[0])
}

// All three inside edges share the sixteen columns of one macroblock. The
// byte filter saturates each update before the next edge reads the same column.
func vp8FilterVerticalLumaInner(pixels: [*] u8, level, iLevel, hLevel, stride: s32)
{
    let edgeLimit = splat(cast(u8, level))
    let inLimit   = splat(cast(u8, iLevel))
    let hevLimit  = splat(cast(u8, hLevel))
    let lower     = pixels + stride * 8
    var samples: [16] U8x16
    vp8LoadVerticalBytes(pixels, lower, stride, &samples[0])
    vp8LoadVerticalBytes(pixels + 8, lower + 8, stride, &samples[8])

    let changed4  = vp8FilterByteSamples'true(&samples[0], edgeLimit, inLimit, hevLimit)
    let changed8  = vp8FilterByteSamples'true(&samples[4], edgeLimit, inLimit, hevLimit)
    let changed12 = vp8FilterByteSamples'true(&samples[8], edgeLimit, inLimit, hevLimit)
    if changed4 or changed8 do
        vp8StoreVerticalBytes(pixels, lower, stride, &samples[0])
    if changed8 or changed12 do
        vp8StoreVerticalBytes(pixels + 8, lower + 8, stride, &samples[8])
}

func vp8ComputeFilterParams(decoder: *Vp8Decoder)
{
    for segment in VP8_SEGMENTS
    {
        var baseLevel = cast(s32, decoder.filterHeader.level)
        if decoder.segmentHeader.useSegment
        {
            baseLevel = decoder.segmentHeader.filterStrength[segment]
            if decoder.segmentHeader.relativeDelta do
                baseLevel += decoder.filterHeader.level
        }

        for mode in 2
        {
            let parameter = &decoder.filterParams[segment][mode]
            parameter.inner = mode != 0
            var level = baseLevel
            if decoder.filterHeader.useDelta
            {
                level += decoder.filterHeader.referenceDelta[0]
                if mode do
                    level += decoder.filterHeader.modeDelta[0]
            }

            if level <= 0
            {
                parameter.level = 0
                continue
            }

            level = Math.min(level, 63)
            var iLevel = level
            if decoder.filterHeader.sharpness
            {
                iLevel >>= decoder.filterHeader.sharpness > 4 ? 2 : 1
                iLevel = Math.min(iLevel, 9 - decoder.filterHeader.sharpness)
            }

            iLevel = Math.max(iLevel, 1)
            parameter.iLevel = cast(u8, iLevel)
            parameter.level  = cast(u8, (2 * level + iLevel))
            parameter.hLevel = level < 15 ? 0 : (level < 40 ? 1 : 2)
        }
    }
}

func vp8SimpleFilter(decoder: *Vp8Decoder, mbY: s32)
{
    let yData = cast([*] u8, decoder.y.storage())
    for mbX in decoder.mbWidth
    {
        let parameter = decoder.perMbFilterParams[decoder.mbWidth * mbY + mbX]
        if not parameter.level do
            continue
        let level  = cast(s32, parameter.level)
        let offset = (mbY * decoder.yStride + mbX) * 16
        if mbX do
            vp8Filter2(yData, level + 4, offset, decoder.yStride, 1)
        if parameter.inner
        {
            vp8Filter2(yData, level, offset + 4, decoder.yStride, 1)
            vp8Filter2(yData, level, offset + 8, decoder.yStride, 1)
            vp8Filter2(yData, level, offset + 12, decoder.yStride, 1)
        }

        if mbY do
            vp8Filter2(yData, level + 4, offset, 1, decoder.yStride)
        if parameter.inner
        {
            vp8Filter2(yData, level, offset + 4 * decoder.yStride, 1, decoder.yStride)
            vp8Filter2(yData, level, offset + 8 * decoder.yStride, 1, decoder.yStride)
            vp8Filter2(yData, level, offset + 12 * decoder.yStride, 1, decoder.yStride)
        }
    }
}

func vp8NormalFilter(decoder: *Vp8Decoder, mbY: s32)
{
    let yData  = cast([*] u8, decoder.y.storage())
    let cbData = cast([*] u8, decoder.cb.storage())
    let crData = cast([*] u8, decoder.cr.storage())
    for mbX in decoder.mbWidth
    {
        let parameter = decoder.perMbFilterParams[decoder.mbWidth * mbY + mbX]
        if not parameter.level do
            continue
        let level   = cast(s32, parameter.level)
        let iLevel  = cast(s32, parameter.iLevel)
        let hLevel  = cast(s32, parameter.hLevel)
        let yOffset = (mbY * decoder.yStride + mbX) * 16
        let cOffset = (mbY * decoder.cStride + mbX) * 8
        if mbX
        {
            let edge = yData + yOffset
            vp8FilterVerticalPair'false(edge, edge + 8 * decoder.yStride, decoder.yStride, level + 4, iLevel, hLevel)
            vp8FilterVerticalPair'false(cbData + cOffset, crData + cOffset, decoder.cStride, level + 4, iLevel, hLevel)
        }

        if parameter.inner
        {
            vp8FilterVerticalLumaInner(yData + yOffset, level, iLevel, hLevel, decoder.yStride)
            vp8FilterVerticalPair'true(cbData + cOffset + 4, crData + cOffset + 4, decoder.cStride, level, iLevel, hLevel)
        }

        if mbY
        {
            vp8FilterHorizontalLuma'false(yData + yOffset, decoder.yStride, level + 4, iLevel, hLevel)
            vp8FilterHorizontalChroma'false(cbData + cOffset, crData + cOffset, decoder.cStride, level + 4, iLevel, hLevel)
        }

        if parameter.inner
        {
            vp8FilterHorizontalLuma'true(yData + yOffset + 4 * decoder.yStride, decoder.yStride, level, iLevel, hLevel)
            vp8FilterHorizontalLuma'true(yData + yOffset + 8 * decoder.yStride, decoder.yStride, level, iLevel, hLevel)
            vp8FilterHorizontalLuma'true(yData + yOffset + 12 * decoder.yStride, decoder.yStride, level, iLevel, hLevel)
            vp8FilterHorizontalChroma'true(cbData + cOffset + 4 * decoder.cStride, crData + cOffset + 4 * decoder.cStride, decoder.cStride, level, iLevel, hLevel)
        }
    }
}

func vp8ApplyFilter(decoder: *Vp8Decoder, mbY: s32)
{
    if not decoder.filterHeader.level do
        return
    if decoder.filterHeader.simple do
        vp8SimpleFilter(decoder, mbY)
    else do
        vp8NormalFilter(decoder, mbY)
}
