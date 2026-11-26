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
func vp8LoadEight(source: const [*] u8)->U16x8
{
    let bytes = cast #bit(U8x16, splat(cast(const [*] u64, source)[0]))
    return widenLow(bytes)
}

#[Swag.Inline]
func vp8StoreEight(destination: [*] u8, values: U16x8)
{
    storeLow8(destination, packUnsigned(cast #bit(S16x8, values), splat(0's16)))
}

#[Swag.Inline]
func vp8FilterSamples(samples: [*] U16x8, edgeLimit, inLimit, hevLimit: S16x8, fourNotSix: bool)->bool
{
    let zero = splat(0's16)
    let p3   = cast #bit(S16x8, samples[0])
    let p2   = cast #bit(S16x8, samples[1])
    let p1   = cast #bit(S16x8, samples[2])
    let p0   = cast #bit(S16x8, samples[3])
    let q0   = cast #bit(S16x8, samples[4])
    let q1   = cast #bit(S16x8, samples[5])
    let q2   = cast #bit(S16x8, samples[6])
    let q3   = cast #bit(S16x8, samples[7])

    let pGap     = Math.abs(p1 - p0)
    let qGap     = Math.abs(q1 - q0)
    let crossGap = q0 - p0
    let across   = 2 * Math.abs(crossGap) + (Math.abs(p1 - q1) >> 1)
    let insideP  = Math.max(pGap, Math.max(Math.abs(p3 - p2), Math.abs(p2 - p1)))
    let insideQ  = Math.max(qGap, Math.max(Math.abs(q3 - q2), Math.abs(q2 - q1)))
    let active   = (across <= edgeLimit) & (Math.max(insideP, insideQ) <= inLimit)
    if not anyTrue(active) do
        return false

    let hev   = (pGap > hevLimit) | (qGap > hevLimit)
    let extra = Math.clamp(p1 - q1, splat(-128's16), splat(127's16))
    var a     = 3 * crossGap
    a += fourNotSix ? select(hev, extra, zero) : extra

    let a1   = Math.clamp((a + 4) >> 3, splat(-16's16), splat(15's16))
    let a2   = Math.clamp((a + 3) >> 3, splat(-16's16), splat(15's16))
    let wide = active & ~hev
    if fourNotSix
    {
        let a3 = select(wide, (a1 + 1) >> 1, zero)
        samples[2] = cast #bit(U16x8, (p1 + a3))
        samples[3] = cast #bit(U16x8, (p0 + select(active, a2, zero)))
        samples[4] = cast #bit(U16x8, (q0 - select(active, a1, zero)))
        samples[5] = cast #bit(U16x8, (q1 - a3))
    }
    else
    {
        let saturated   = Math.clamp(a, splat(-128's16), splat(127's16))
        let wide0       = select(wide, (27 * saturated + 63) >> 7, zero)
        let wide1       = select(wide, (18 * saturated + 63) >> 7, zero)
        let wide2       = select(wide, (9 * saturated + 63) >> 7, zero)
        let narrow      = active & hev
        let pAdjustment = wide0 + select(narrow, a2, zero)
        let qAdjustment = wide0 + select(narrow, a1, zero)
        samples[1] = cast #bit(U16x8, (p2 + wide2))
        samples[2] = cast #bit(U16x8, (p1 + wide1))
        samples[3] = cast #bit(U16x8, (p0 + pAdjustment))
        samples[4] = cast #bit(U16x8, (q0 - qAdjustment))
        samples[5] = cast #bit(U16x8, (q1 - wide1))
        samples[6] = cast #bit(U16x8, (q2 - wide2))
    }

    return true
}

// Each tile transposes eight rows into the samples on either side of the edge.
func vp8FilterVertical(edge: [*] u8, count, stride, level, iLevel, hLevel: s32, fourNotSix: bool)
{
    let edgeLimit = splat(cast(s16, level))
    let inLimit   = splat(cast(s16, iLevel))
    let hevLimit  = splat(cast(s16, hLevel))
    let first     = edge - 4
    for block in count / 8
    {
        let tile = first + block * 8 * stride
        var samples: [8] U16x8
        for row in 8 do
            samples[row] = vp8LoadEight(tile + row * stride)

        transpose8x8(&samples)
        if not vp8FilterSamples(&samples[0], edgeLimit, inLimit, hevLimit, fourNotSix) do
            continue

        transpose8x8(&samples)
        for row in 8 do
            vp8StoreEight(tile + row * stride, samples[row])
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

// The three interior edges share four columns with their neighbors. Load the
// macroblock once, keep earlier updates in the transposed tiles, then store the tiles.
func vp8FilterVerticalLumaInner(pixels: [*] u8, level, iLevel, hLevel, stride: s32)
{
    let edgeLimit = splat(cast(s16, level))
    let inLimit   = splat(cast(s16, iLevel))
    let hevLimit  = splat(cast(s16, hLevel))
    for band in 2
    {
        let base = pixels + band * 8 * stride
        var samples: [16] U16x8
        for row in 8
        {
            let bytes = load(base + row * stride)
            samples[row]     = widenLow(bytes)
            samples[row + 8] = widenHigh(bytes)
        }

        let left  = cast(*[8] U16x8, &samples[0])
        let right = cast(*[8] U16x8, &samples[8])
        transpose8x8(left)
        transpose8x8(right)

        // The next edge reads the previous edge's clipped q0 and q1.
        let changed4 = vp8FilterSamples(&samples[0], edgeLimit, inLimit, hevLimit, true)
        if changed4
        {
            let clipped = packUnsigned(cast #bit(S16x8, samples[4]), cast #bit(S16x8, samples[5]))
            samples[4] = widenLow(clipped)
            samples[5] = widenHigh(clipped)
        }

        let changed8 = vp8FilterSamples(&samples[4], edgeLimit, inLimit, hevLimit, true)
        if changed8
        {
            let clipped = packUnsigned(cast #bit(S16x8, samples[8]), cast #bit(S16x8, samples[9]))
            samples[8] = widenLow(clipped)
            samples[9] = widenHigh(clipped)
        }

        let changed12 = vp8FilterSamples(&samples[8], edgeLimit, inLimit, hevLimit, true)

        if changed4 or changed8
        {
            transpose8x8(left)
            for row in 8 do
                vp8StoreEight(base + row * stride, samples[row])
        }

        if changed8 or changed12
        {
            transpose8x8(right)
            for row in 8 do
                vp8StoreEight(base + row * stride + 8, samples[row + 8])
        }
    }
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
            vp8FilterVertical(yData + yOffset, 16, decoder.yStride, level + 4, iLevel, hLevel, false)
            vp8FilterVertical(cbData + cOffset, 8, decoder.cStride, level + 4, iLevel, hLevel, false)
            vp8FilterVertical(crData + cOffset, 8, decoder.cStride, level + 4, iLevel, hLevel, false)
        }

        if parameter.inner
        {
            vp8FilterVerticalLumaInner(yData + yOffset, level, iLevel, hLevel, decoder.yStride)
            vp8FilterVertical(cbData + cOffset + 4, 8, decoder.cStride, level, iLevel, hLevel, true)
            vp8FilterVertical(crData + cOffset + 4, 8, decoder.cStride, level, iLevel, hLevel, true)
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
