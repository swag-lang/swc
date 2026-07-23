using Swag, Core

const CURVE_TAG_ON = 0x01'u8
const MAX_RECURSE  = 16'u32

const CMP_ARG_1_AND_2_ARE_WORDS = 0x0001'u16
const CMP_ARGS_ARE_XY_VALUES    = 0x0002'u16
const CMP_WE_HAVE_A_SCALE       = 0x0008'u16
const CMP_MORE_COMPONENTS       = 0x0020'u16
const CMP_WE_HAVE_AN_XY_SCALE   = 0x0040'u16
const CMP_WE_HAVE_A_2X2         = 0x0080'u16
const CMP_WE_HAVE_INSTRUCTIONS  = 0x0100'u16

func addScaledPoint(faceData: *FaceImpl, x, y: f64, onCurve: bool)
{
    faceData.outlinePoints.add(Vector{x: cast(s32) Math.round(x), y: cast(s32) Math.round(y)})
    faceData.outlineTags.add(onCurve ? CURVE_TAG_ON : 0)
}

func appendSimpleGlyph(faceData: *FaceImpl, glyphData: #null const [..] u8, xPpem, yPpem: u32) throw
{
    let contourCount = cast(u32) readS16(glyphData, 0)
    var offset       = 10'u64
    var contourEnds: Array'u16
    contourEnds.resize(contourCount)
    for contourCount
    {
        contourEnds[@index] = readU16(glyphData, offset)
        offset              += 2
    }

    let pointCount = contourCount ? contourEnds.back() + 1 : 0
    let instructionLength = readU16(glyphData, offset)
    offset += 2 + instructionLength

    var flags: Array'u8
    flags.resize(pointCount)
    var i = 0'u32
    while i < pointCount
    {
        let flag = readU8(glyphData, offset)
        offset   += 1
        flags[i] = flag
        i        += 1
        if (flag & 0x08) != 0
        {
            let repeat = readU8(glyphData, offset)
            offset += 1
            for repeat
            {
                flags[i] = flag
                i        += 1
            }
        }
    }

    var xs: Array's32
    xs.resize(pointCount)
    var x = 0's32
    for pointCount
    {
        let flag = flags[@index]
        if (flag & 0x02) != 0
        {
            let dx = cast(s32) readU8(glyphData, offset)
            offset += 1
            x      += (flag & 0x10) != 0 ? dx : -dx
        }
        elif (flag & 0x10) == 0
        {
            x      += readS16(glyphData, offset)
            offset += 2
        }

        xs[@index] = x
    }

    var ys: Array's32
    ys.resize(pointCount)
    var y = 0's32
    for pointCount
    {
        let flag = flags[@index]
        if (flag & 0x04) != 0
        {
            let dy = cast(s32) readU8(glyphData, offset)
            offset += 1
            y      += (flag & 0x20) != 0 ? dy : -dy
        }
        elif (flag & 0x20) == 0
        {
            y      += readS16(glyphData, offset)
            offset += 2
        }

        ys[@index] = y
    }

    let startPoint = faceData.outlinePoints.count
    for pointCount
    {
        let px = scale26_6(xs[@index], xPpem, faceData.unitsPerEm)
        let py = scale26_6(ys[@index], yPpem, faceData.unitsPerEm)
        addScaledPoint(faceData, px, py, (flags[@index] & CURVE_TAG_ON) != 0)
    }

    for contourCount do
        faceData.outlineContours.add(cast(s16) (startPoint + contourEnds[@index]))
}

func appendCompositeGlyph(faceData: *FaceImpl, glyphData: #null const [..] u8, xPpem, yPpem: u32, depth: u32) throw
{
    if depth >= MAX_RECURSE do
        fail(0x15)

    var offset = 10'u64
    var hasMore = true
    while hasMore
    {
        let flags        = readU16(glyphData, offset + 0)
        let componentIdx = readU16(glyphData, offset + 2)
        offset += 4

        var arg1 = 0's32
        var arg2 = 0's32
        if (flags & CMP_ARG_1_AND_2_ARE_WORDS) != 0
        {
            arg1   = readS16(glyphData, offset + 0)
            arg2   = readS16(glyphData, offset + 2)
            offset += 4
        }
        else
        {
            arg1   = cast #bit (s8) readU8(glyphData, offset + 0)
            arg2   = cast #bit (s8) readU8(glyphData, offset + 1)
            offset += 2
        }

        var xx: f64 = 1.0
        var xy: f64 = 0.0
        var yx: f64 = 0.0
        var yy: f64 = 1.0
        if (flags & CMP_WE_HAVE_A_SCALE) != 0
        {
            xx     = readF2Dot14(glyphData, offset)
            yy     = xx
            offset += 2
        }
        elif (flags & CMP_WE_HAVE_AN_XY_SCALE) != 0
        {
            xx     = readF2Dot14(glyphData, offset + 0)
            yy     = readF2Dot14(glyphData, offset + 2)
            offset += 4
        }
        elif (flags & CMP_WE_HAVE_A_2X2) != 0
        {
            xx     = readF2Dot14(glyphData, offset + 0)
            yx     = readF2Dot14(glyphData, offset + 2)
            xy     = readF2Dot14(glyphData, offset + 4)
            yy     = readF2Dot14(glyphData, offset + 6)
            offset += 8
        }

        let basePointCount   = faceData.outlinePoints.count
        let baseContourCount = faceData.outlineContours.count

        appendGlyph(faceData, componentIdx, xPpem, yPpem, depth + 1)

        let addedPointCount = faceData.outlinePoints.count - basePointCount
        if addedPointCount
        {
            var dx = 0.0
            var dy = 0.0
            if (flags & CMP_ARGS_ARE_XY_VALUES) != 0
            {
                dx = scale26_6(arg1, xPpem, faceData.unitsPerEm)
                dy = scale26_6(arg2, yPpem, faceData.unitsPerEm)
            }

            for addedPointCount
            {
                let idx = basePointCount + cast(u32) @index
                let src = faceData.outlinePoints[idx]
                let tx  = cast(f64) src.x
                let ty  = cast(f64) src.y
                faceData.outlinePoints[idx].x = cast(s32) Math.round(tx * xx + ty * xy)
                faceData.outlinePoints[idx].y = cast(s32) Math.round(tx * yx + ty * yy)
            }

            if (flags & CMP_ARGS_ARE_XY_VALUES) == 0 and arg1 >= 0 and arg2 >= 0 and cast(u32) arg1 < basePointCount and cast(u32) arg2 < addedPointCount
            {
                let anchorParent = faceData.outlinePoints[arg1]
                let anchorChild  = faceData.outlinePoints[basePointCount + arg2]
                dx = anchorParent.x - anchorChild.x
                dy = anchorParent.y - anchorChild.y
            }

            for addedPointCount
            {
                let idx = basePointCount + cast(u32) @index
                faceData.outlinePoints[idx].x = cast(s32) Math.round(faceData.outlinePoints[idx].x + dx)
                faceData.outlinePoints[idx].y = cast(s32) Math.round(faceData.outlinePoints[idx].y + dy)
            }
        }

        for faceData.outlineContours.count - baseContourCount do
            faceData.outlineContours[baseContourCount + @index] = cast(s16) faceData.outlineContours[baseContourCount + @index]

        hasMore = (flags & CMP_MORE_COMPONENTS) != 0
    }

    if hasMore and (readU16(glyphData, offset) & CMP_WE_HAVE_INSTRUCTIONS) != 0 {}
}

func appendGlyph(faceData: *FaceImpl, glyphIndex: u32, xPpem, yPpem: u32, depth: u32 = 0) throw
{
    if glyphIndex >= faceData.face.glyphCount do
        fail(0x10)

    let start = faceData.glyphLocations[glyphIndex]
    let stop  = faceData.glyphLocations[glyphIndex + 1]
    if stop <= start do
        return

    let glyf  = getTableSlice(faceData, TAG_GLYF, 0x8E)
    let data  = getSlice(glyf, start, stop - start)
    let count = readS16(data, 0)
    if count >= 0 do
        appendSimpleGlyph(faceData, data, xPpem, yPpem)
    else do
        appendCompositeGlyph(faceData, data, xPpem, yPpem, depth)
}

func loadGlyphInternal(face: *Face, glyphIndex: u32) throw
{
    let faceData = getFaceImpl(face)
    let slot = &face.glyph
    clearOutline(slot)
    clearBitmap(slot)

    faceData.outlinePoints.clear()
    faceData.outlineTags.clear()
    faceData.outlineContours.clear()

    slot.index  = glyphIndex
    slot.format = .Outline

    let xPpem = Math.max(1'u32, face.size.metrics.xPpem)
    let yPpem = Math.max(1'u32, face.size.metrics.yPpem)
    appendGlyph(faceData, glyphIndex, xPpem, yPpem)

    slot.outline.pointCount   = cast(s16) faceData.outlinePoints.count
    slot.outline.contourCount = cast(s16) faceData.outlineContours.count
    slot.outline.points       = faceData.outlinePoints.count ? faceData.outlinePoints.buffer : null
    slot.outline.tags         = faceData.outlineTags.count ? faceData.outlineTags.buffer : null
    slot.outline.contours     = faceData.outlineContours.count ? faceData.outlineContours.buffer : null
    slot.outline.flags        = 0

    let metric              = faceData.glyphMetrics[glyphIndex]
    slot.advance.x                 = scale26_6(metric.advanceWidth, xPpem, faceData.unitsPerEm)
    slot.advance.y                 = 0
    slot.metrics.horizontalAdvance = slot.advance.x
    updateSlotMetrics(slot)
}
