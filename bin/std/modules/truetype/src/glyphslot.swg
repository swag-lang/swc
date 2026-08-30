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
    public readonly
    {
        width:              s32     // Width of the outline control box.
        height:             s32     // Height of the outline control box.
        horizontalBearingX: s32     // Offset from the pen to the left outline bound.
        horizontalBearingY: s32     // Offset from the baseline to the top outline bound.
        horizontalAdvance:  s32     // Recommended horizontal pen advance.
    }
}

impl GlyphMetrics
{
    mtd clearBounds()
    {
        .width              = 0
        .height             = 0
        .horizontalBearingX = 0
        .horizontalBearingY = 0
    }

    mtd setBounds(minX, minY, maxX, maxY: s32)
    {
        .width              = maxX - minX
        .height             = maxY - minY
        .horizontalBearingX = minX
        .horizontalBearingY = maxY
    }

    mtd setHorizontalAdvance(value: s32)
    {
        .horizontalAdvance = value
    }
}

// Holds the outline, metrics, and bitmap of the most recently loaded glyph.
//
// Every face has one reusable slot. Calling [[TrueType.Face.loadGlyph]] or
// [[TrueType.Face.loadChar]] replaces its borrowed outline and bitmap storage.
// Copy owned data before loading another glyph when it must outlive the operation.
public struct GlyphSlot
{
    // Outline transformations intentionally mutate the current glyph in place.
    public outline: Outline     // Borrowed scalable outline for the glyph.

    // Loading and rendering replace the slot atomically. Use the public methods to
    // mutate its outline instead of assigning derived state directly.
    public readonly
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
    }
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

        let points = .outline.points!
        for cast(u32) .outline.pointCount do
            points[Swag.index].x += cast(s32) Math.round(points[Swag.index].y * 0.21256)

        updateSlotMetrics(me)
    }

    internal mtd initialize(face: *Face)
    {
        .face   = face
        .format = .None
        .bitmap.reset()
    }

    internal mtd beginLoad(index: u32)
    {
        .index  = index
        .format = .Outline
    }

    internal mtd setAdvance(horizontal: s32)
    {
        .advance.x = horizontal
        .advance.y = 0
        .metrics.setHorizontalAdvance(horizontal)
    }

    internal mtd resetBitmap()
    {
        .bitmap.reset()
        .bitmapLeft = 0
        .bitmapTop  = 0
    }

    internal mtd setBitmap(rows, width: u32, pitch: s32, buffer: #null [*] u8, pixelMode: PixelMode, left, top: s32)
    {
        .bitmap.set(rows, width, pitch, buffer, pixelMode)
        .bitmapLeft = left
        .bitmapTop  = top
    }
}

func clearOutline(slot: *GlyphSlot)
{
    slot.outline.reset()
}

func clearBitmap(slot: *GlyphSlot)
{
    slot.resetBitmap()
}

func computeOutlineBounds(outline: const *Outline)->{ minX: s32, minY: s32, maxX: s32, maxY: s32 }
{
    var result: retval
    if outline.pointCount <= 0 do
        return result

    result.minX = Swag.S32.Max
    result.minY = Swag.S32.Max
    result.maxX = Swag.S32.Min
    result.maxY = Swag.S32.Min

    let points = cast(const [*] Vector) outline.points!
    for cast(u32) outline.pointCount
    {
        let pt = points[Swag.index]
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
        slot.metrics.clearBounds()
        return
    }

    slot.metrics.setBounds(bounds.minX, bounds.minY, bounds.maxX, bounds.maxY)
}
