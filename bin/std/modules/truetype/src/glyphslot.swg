using Swag, Core

public enum GlyphFormat
{
    None      = 0
    Composite = 0x636F6D70
    Bitmap    = 0x62697473
    Outline   = 0x6F75746C
    Plotter   = 0x706C6F74
}

public struct GlyphMetrics
{
    width:            s32
    height:           s32
    horizontalBearingX: s32
    horizontalBearingY: s32
    horizontalAdvance:  s32
    verticalBearingX:   s32
    verticalBearingY:   s32
    verticalAdvance:    s32
}

public struct GlyphSlot
{
    face:                   #null *Face
    index:                  u32
    metrics:                GlyphMetrics
    linearHorizontalAdvance: s32
    linearVerticalAdvance:   s32
    advance:                Vector
    format:                 GlyphFormat = GlyphFormat.None
    bitmap:                 Bitmap
    bitmapLeft:             s32
    bitmapTop:              s32
    outline:                Outline
    leftSideBearingDelta:   s32
    rightSideBearingDelta:  s32
}

public impl GlyphSlot
{
    mtd oblique()
    {
        if .outline.pointCount <= 0 do
            return

        let points = .outline.points orelse cast([*] Vector) 1'u64
        for cast(u32) .outline.pointCount do
            points[@index].x += cast(s32) Math.round(points[@index].y * 0.21256)

        updateSlotMetrics(me)
    }
}

func clearOutline(slot: *GlyphSlot)
{
    slot.outline.contourCount = 0
    slot.outline.pointCount   = 0
    slot.outline.points     = null
    slot.outline.tags       = null
    slot.outline.contours   = null
    slot.outline.flags      = 0
}

func clearBitmap(slot: *GlyphSlot)
{
    slot.bitmap.rows         = 0
    slot.bitmap.width        = 0
    slot.bitmap.pitch        = 0
    slot.bitmap.buffer       = null
    slot.bitmap.pixelMode   = .Gray
    slot.bitmap.grayCount    = 256
    slot.bitmapLeft         = 0
    slot.bitmapTop          = 0
}

func computeOutlineBounds(outline: #null const *Outline)->{ minX: s32, minY: s32, maxX: s32, maxY: s32 }
{
    var result: retval
    if !outline or outline.pointCount <= 0 do
        return result

    result.minX = Swag.S32.Max
    result.minY = Swag.S32.Max
    result.maxX = Swag.S32.Min
    result.maxY = Swag.S32.Min

    let points = cast(const [*] Vector) (outline.points orelse cast([*] Vector) 1'u64)
    for cast(u32) outline.pointCount
    {
        let pt = points[@index]
        result.minX = Math.min(result.minX, pt.x)
        result.minY = Math.min(result.minY, pt.y)
        result.maxX = Math.max(result.maxX, pt.x)
        result.maxY = Math.max(result.maxY, pt.y)
    }

    return result
}

func updateSlotMetrics(slot: *GlyphSlot)
{
    let bounds = computeOutlineBounds(&slot.outline)
    if slot.outline.pointCount <= 0
    {
        slot.metrics = {}
        return
    }

    slot.metrics.width        = bounds.maxX - bounds.minX
    slot.metrics.height       = bounds.maxY - bounds.minY
    slot.metrics.horizontalBearingX = bounds.minX
    slot.metrics.horizontalBearingY = bounds.maxY
    slot.metrics.verticalAdvance  = 0
    slot.metrics.verticalBearingX = 0
    slot.metrics.verticalBearingY = 0
}
