using Swag, Core

// Identifies which representation is active in a [[TrueType.GlyphSlot]].
public enum GlyphFormat
{
    None        // No glyph representation is available.
    Outline     // The slot represents a scalable outline.
}

// Contains the measurements of the current glyph.
//
// Values use 26.6 fixed-point pixels.
public struct GlyphMetrics
{
    width:              s32     // Width of the outline control box.
    height:             s32     // Height of the outline control box.
    horizontalBearingX: s32     // Offset from the pen to the left outline bound.
    horizontalBearingY: s32     // Offset from the baseline to the top outline bound.
    horizontalAdvance:  s32     // Recommended horizontal pen advance.
}

// Holds the outline, metrics, and bitmap of the most recently loaded glyph.
//
// Every face has one reusable slot. Calling [[TrueType.Face.loadGlyph]] or
// [[TrueType.Face.loadChar]] replaces its borrowed outline and bitmap storage.
// Copy owned data before loading another glyph when it must outlive the operation.
public struct GlyphSlot
{
    #[Swag.Late]
    face:       *Face                              // Borrowed pointer to the owning face.
    index:      u32                                // Glyph index represented by this slot.
    metrics:    GlyphMetrics                       // Scaled measurements for the glyph.
    advance:    Vector                             // Pen displacement after drawing this glyph.
    format:     GlyphFormat = GlyphFormat.None     // Active representation.
    bitmap:     Bitmap                             // Borrowed pixels from the most recent render.
    bitmapLeft: s32                                // Bitmap left edge relative to the pen, in pixels.
    bitmapTop:  s32                                // Bitmap top edge above the baseline, in pixels.
    outline:    Outline                            // Borrowed scalable outline for the glyph.
}

public impl GlyphSlot
{
    // Applies a synthetic italic slant to the current outline.
    //
    // The operation mutates the reusable outline and refreshes its bounds. Load
    // the glyph again to recover the original geometry.
    mtd oblique()
    {
        if .outline.pointCount <= 0 do
            return

        let points = notnull .outline.points
        for cast(u32) .outline.pointCount do
            points[@index].x += cast(s32) Math.round(points[@index].y * 0.21256)

        updateSlotMetrics(me)
    }
}

func clearOutline(slot: *GlyphSlot)
{
    slot.outline.contourCount = 0
    slot.outline.pointCount   = 0
    slot.outline.points       = null
    slot.outline.tags         = null
    slot.outline.contours     = null
    slot.outline.flags        = 0
}

func clearBitmap(slot: *GlyphSlot)
{
    slot.bitmap.rows      = 0
    slot.bitmap.width     = 0
    slot.bitmap.pitch     = 0
    slot.bitmap.buffer    = null
    slot.bitmap.pixelMode = .Gray
    slot.bitmap.grayCount = 256
    slot.bitmapLeft       = 0
    slot.bitmapTop        = 0
}

func computeOutlineBounds(outline: const *Outline)->{ minX: s32, minY: s32, maxX: s32, maxY: s32 }
{
    var result: retval
    if !outline or outline.pointCount <= 0 do
        return result

    result.minX = Swag.S32.Max
    result.minY = Swag.S32.Max
    result.maxX = Swag.S32.Min
    result.maxY = Swag.S32.Min

    let points = cast(const [*] Vector) (notnull outline.points)
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

    slot.metrics.width              = bounds.maxX - bounds.minX
    slot.metrics.height             = bounds.maxY - bounds.minY
    slot.metrics.horizontalBearingX = bounds.minX
    slot.metrics.horizontalBearingY = bounds.maxY
}
