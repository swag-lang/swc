#global namespace Webp

func vp8Abs(value: s32)->s32
{
    return value < 0 ? -value : value
}

func vp8Clamp15(value: s32)->s32
{
    return vp8Clip(value, -16, 15)
}

func vp8Clamp127(value: s32)->s32
{
    return vp8Clip(value, -128, 127)
}

func vp8Filter2(pixels: [*] u8, level, index, iStep, jStep: s32)
{
    var offset = index
    for 16
    {
        let p1 = cast(s32) pixels[offset - 2 * jStep]
        let p0 = cast(s32) pixels[offset - 1 * jStep]
        let q0 = cast(s32) pixels[offset]
        let q1 = cast(s32) pixels[offset + 1 * jStep]
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

func vp8Filter246(pixels: [*] u8, count, level, iLevel, hLevel, index, iStep, jStep: s32, fourNotSix: bool)
{
    var offset = index
    for count
    {
        let p3 = cast(s32) pixels[offset - 4 * jStep]
        let p2 = cast(s32) pixels[offset - 3 * jStep]
        let p1 = cast(s32) pixels[offset - 2 * jStep]
        let p0 = cast(s32) pixels[offset - 1 * jStep]
        let q0 = cast(s32) pixels[offset]
        let q1 = cast(s32) pixels[offset + 1 * jStep]
        let q2 = cast(s32) pixels[offset + 2 * jStep]
        let q3 = cast(s32) pixels[offset + 3 * jStep]
        if 2 * vp8Abs(p0 - q0) + vp8Abs(p1 - q1) / 2 > level or
           vp8Abs(p3 - p2) > iLevel or
           vp8Abs(p2 - p1) > iLevel or
           vp8Abs(p1 - p0) > iLevel or
           vp8Abs(q1 - q0) > iLevel or
           vp8Abs(q2 - q1) > iLevel or
           vp8Abs(q3 - q2) > iLevel
        {
            offset += iStep
            continue
        }

        if vp8Abs(p1 - p0) > hLevel or vp8Abs(q1 - q0) > hLevel
        {
            let a  = 3 * (q0 - p0) + vp8Clamp127(p1 - q1)
            let a1 = vp8Clamp15((a + 4) >> 3)
            let a2 = vp8Clamp15((a + 3) >> 3)
            pixels[offset - jStep] = vp8Clip8(p0 + a2)
            pixels[offset]         = vp8Clip8(q0 - a1)
        }
        elif fourNotSix
        {
            let a  = 3 * (q0 - p0)
            let a1 = vp8Clamp15((a + 4) >> 3)
            let a2 = vp8Clamp15((a + 3) >> 3)
            let a3 = (a1 + 1) >> 1
            pixels[offset - 2 * jStep] = vp8Clip8(p1 + a3)
            pixels[offset - jStep]     = vp8Clip8(p0 + a2)
            pixels[offset]             = vp8Clip8(q0 - a1)
            pixels[offset + jStep]     = vp8Clip8(q1 - a3)
        }
        else
        {
            let a  = vp8Clamp127(3 * (q0 - p0) + vp8Clamp127(p1 - q1))
            let a1 = (27 * a + 63) >> 7
            let a2 = (18 * a + 63) >> 7
            let a3 = (9 * a + 63) >> 7
            pixels[offset - 3 * jStep] = vp8Clip8(p2 + a3)
            pixels[offset - 2 * jStep] = vp8Clip8(p1 + a2)
            pixels[offset - jStep]     = vp8Clip8(p0 + a1)
            pixels[offset]             = vp8Clip8(q0 - a1)
            pixels[offset + jStep]     = vp8Clip8(q1 - a2)
            pixels[offset + 2 * jStep] = vp8Clip8(q2 - a3)
        }

        offset += iStep
    }
}

func vp8ComputeFilterParams(decoder: *Vp8Decoder)
{
    for [segment] in VP8_SEGMENTS
    {
        var baseLevel = cast(s32) decoder.filterHeader.level
        if decoder.segmentHeader.useSegment
        {
            baseLevel = decoder.segmentHeader.filterStrength[segment]
            if decoder.segmentHeader.relativeDelta do
                baseLevel += decoder.filterHeader.level
        }

        for [mode] in 2
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

            iLevel           = Math.max(iLevel, 1)
            parameter.iLevel = cast(u8) iLevel
            parameter.level  = cast(u8) (2 * level + iLevel)
            parameter.hLevel = level < 15 ? 0 : (level < 40 ? 1 : 2)
        }
    }
}

func vp8SimpleFilter(decoder: *Vp8Decoder)
{
    let yData = cast([*] u8) notnull decoder.y.buffer
    for [mbY] in decoder.mbHeight
    {
        for [mbX] in decoder.mbWidth
        {
            let parameter = decoder.perMbFilterParams[decoder.mbWidth * mbY + mbX]
            if !parameter.level do
                continue
            let level  = cast(s32) parameter.level
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
}

func vp8NormalFilter(decoder: *Vp8Decoder)
{
    let yData  = cast([*] u8) notnull decoder.y.buffer
    let cbData = cast([*] u8) notnull decoder.cb.buffer
    let crData = cast([*] u8) notnull decoder.cr.buffer
    for [mbY] in decoder.mbHeight
    {
        for [mbX] in decoder.mbWidth
        {
            let parameter = decoder.perMbFilterParams[decoder.mbWidth * mbY + mbX]
            if !parameter.level do
                continue
            let level   = cast(s32) parameter.level
            let iLevel  = cast(s32) parameter.iLevel
            let hLevel  = cast(s32) parameter.hLevel
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
                vp8Filter246(yData, 16, level, iLevel, hLevel, yOffset + 4, decoder.yStride, 1, true)
                vp8Filter246(yData, 16, level, iLevel, hLevel, yOffset + 8, decoder.yStride, 1, true)
                vp8Filter246(yData, 16, level, iLevel, hLevel, yOffset + 12, decoder.yStride, 1, true)
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
}

func vp8ApplyFilter(decoder: *Vp8Decoder)
{
    if !decoder.filterHeader.level do
        return
    if decoder.filterHeader.simple do
        vp8SimpleFilter(decoder)
    else do
        vp8NormalFilter(decoder)
}
