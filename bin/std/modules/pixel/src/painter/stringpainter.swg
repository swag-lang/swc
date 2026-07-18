#global #[Swag.ExplicitNullability]
#global public
using Core

struct StringPainter
{
    str:     RichString
    fmt:     RichStringFormat
}

impl StringPainter
{
    // Set font
    mtd font(font: #nonull *Font)
    {
        .fmt.font.regular = font
    }

    // Set text color
    mtd color(col: Color)
    {
        .fmt.palette[0] = col
    }

    // Set horizontal alignment
    mtd horzAlign(align: StringHorzAlignment)
    {
        .fmt.horzAlignment = align
    }

    // Set vertical alignment
    mtd vertAlign(align: StringVertAlignment)
    {
        .fmt.vertAlignment = align
    }

    // Set drawing flags
    mtd flags(f: StringFormatFlags)
    {
        .fmt.flags = f
    }

    // Draw #nonull string
    mtd draw(painter: #nonull *Painter, rect: Math.Rectangle, what: #nonull string)
    {
        .str.set(what)
        painter.drawRichString(rect, &.str, .fmt)
    }
}
