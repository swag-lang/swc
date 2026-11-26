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

// The normal filter processes luma edges of sixteen samples and chroma edges of eight.
// Each vector lane handles one position along the edge.
func vp8Filter246(pixels: [*] u8, count, level, iLevel, hLevel, index, iStep, jStep: s32, fourNotSix: bool)
{
    let edgeLimit  = splat(cast(s16, level))
    let inLimit    = splat(cast(s16, iLevel))
    let hevLimit   = splat(cast(s16, hLevel))
    let horizontal = iStep == 1
    let sampleStep = horizontal ? jStep : iStep
    let firstEdge  = pixels + index - 4 * (horizontal ? jStep : 1)
    for block in count / 8
    {
        let edge = firstEdge + block * 8 * iStep
        var samples: [8] U16x8
        for i in 8 do
            samples[i] = vp8LoadEight(edge + i * sampleStep)

        // A vertical edge loads contiguous rows and transposes them into sample positions.
        if not horizontal do
            transpose8x8(&samples)

        if not vp8FilterSamples(&samples[0], edgeLimit, inLimit, hevLimit, fourNotSix) do
            continue

        if horizontal
        {
            let first = fourNotSix ? 2 : 1
            for i in first until 8 - first do
                vp8StoreEight(edge + i * sampleStep, samples[i])
        }
        else
        {
            transpose8x8(&samples)
            for row in 8 do
                vp8StoreEight(edge + row * sampleStep, samples[row])
        }
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
            vp8Filter246(yData, 16, level + 4, iLevel, hLevel, yOffset, decoder.yStride, 1, false)
            vp8Filter246(cbData, 8, level + 4, iLevel, hLevel, cOffset, decoder.cStride, 1, false)
            vp8Filter246(crData, 8, level + 4, iLevel, hLevel, cOffset, decoder.cStride, 1, false)
        }

        if parameter.inner
        {
            vp8FilterVerticalLumaInner(yData + yOffset, level, iLevel, hLevel, decoder.yStride)
            vp8Filter246(cbData, 8, level, iLevel, hLevel, cOffset + 4, decoder.cStride, 1, true)
            vp8Filter246(crData, 8, level, iLevel, hLevel, cOffset + 4, decoder.cStride, 1, true)
        }

        if mbY
        {
            vp8Filter246(yData, 16, level + 4, iLevel, hLevel, yOffset, 1, decoder.yStride, false)
            vp8Filter246(cbData, 8, level + 4, iLevel, hLevel, cOffset, 1, decoder.cStride, false)
            vp8Filter246(crData, 8, level + 4, iLevel, hLevel, cOffset, 1, decoder.cStride, false)
        }

        if parameter.inner
        {
            vp8Filter246(yData, 16, level, iLevel, hLevel, yOffset + 4 * decoder.yStride, 1, decoder.yStride, true)
            vp8Filter246(yData, 16, level, iLevel, hLevel, yOffset + 8 * decoder.yStride, 1, decoder.yStride, true)
            vp8Filter246(yData, 16, level, iLevel, hLevel, yOffset + 12 * decoder.yStride, 1, decoder.yStride, true)
            vp8Filter246(cbData, 8, level, iLevel, hLevel, cOffset + 4 * decoder.cStride, 1, decoder.cStride, true)
            vp8Filter246(crData, 8, level, iLevel, hLevel, cOffset + 4 * decoder.cStride, 1, decoder.cStride, true)
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
