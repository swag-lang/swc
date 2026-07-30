#global public

using Core

// Provides a compact fluent wrapper for drawing one rich string.
//
// Configure font, color, alignment, and flags, then call [[StringPainter.draw]].
struct StringPainter
{
    str: RichString           // Reusable parsed rich-text storage.
    fmt: RichStringFormat     // Formatting applied by the next draw.
}

impl StringPainter
{
    // Sets the regular font used for drawing.
    mtd font(font: *Font)
    {
        .fmt.font.regular = font
    }

    // Sets palette entry zero, the default text color.
    mtd color(col: Color)
    {
        .fmt.palette[0] = col
    }

    // Sets horizontal alignment within the draw rectangle.
    mtd horzAlign(align: StringHorzAlignment)
    {
        .fmt.horzAlignment = align
    }

    // Sets vertical alignment within the draw rectangle.
    mtd vertAlign(align: StringVertAlignment)
    {
        .fmt.vertAlignment = align
    }

    // Replaces wrapping and clipping flags.
    mtd flags(f: StringFormatFlags)
    {
        .fmt.flags = f
    }

    // Parses `what` and records it in `painter` inside `rect`.
    mtd draw(painter: *Painter, rect: Math.Rectangle, what: string)
    {
        .str.set(what)
        painter.drawRichString(rect, &.str, .fmt)
    }
}
