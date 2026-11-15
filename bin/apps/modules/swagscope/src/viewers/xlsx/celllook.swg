#global internal
#global namespace Viewers.Xlsx

using Core, Gui, Pixel

enum CellHorizontal { General, Left, Center, Right }
enum CellVertical { Bottom, Center, Top }

struct CellFont
{
    size:      f32 = 11
    color:     u32 = 0xFF000000
    bold:      bool
    italic:    bool
    underline: bool
    strike:    bool
    mono:      bool
    limited:   bool
}

impl CellFont
{
    mtd const create(theme: *Theme)->*Font
    {
        let style = .bold ? (.italic ? FontFamilyStyle.BoldItalic : .Bold) : (.italic ? FontFamilyStyle.Italic : .Regular)
        let size  = cast(u32, Math.max(Math.round(.size * 4 / 3), 1))
        return .mono ? theme.createDefaultFontFs(size, style) : theme.createDefaultFont(size, style)
    }
}

struct CellEdge
{
    color:      u32 = 0xFF000000
    width:      f32
    dash:       DashStyle
    doubleLine: bool
}

struct CellAlignment
{
    horizontal: CellHorizontal
    vertical:   CellVertical
    wrap:       bool
    indent:     u32
    mask:       u32
    limited:    bool
}

impl CellAlignment
{
    mtd read(token: const *Package.Token)
    {
        if let value = token.attribute("horizontal")
        {
            .mask |= 1
            switch value
            {
            case "general": .horizontal = .General
            case "left":    .horizontal = .Left
            case "center":  .horizontal = .Center
            case "right":   .horizontal = .Right
            default:        .limited = true
            }
        }

        if let value = token.attribute("vertical")
        {
            .mask |= 2
            switch value
            {
            case "bottom": .vertical = .Bottom
            case "center": .vertical = .Center
            case "top":    .vertical = .Top
            default:       .limited = true
            }
        }

        if let value = token.attribute("wrapText")
        {
            .mask |= 4
            .wrap = value == "1" or value == "true"
        }

        if let value = token.attribute("indent")
        {
            .mask   |= 8
            .indent = catch StrConv.toU32(value) orelse Swag.U32.Max
            if .indent > 250
            {
                .indent  = 0
                .limited = true
            }
        }

        if (token.attribute("textRotation") orelse "0") != "0" or token.attribute("shrinkToFit") == "1" do
            .limited = true
    }

    mtd apply(other: const *CellAlignment)
    {
        if other.mask & 1 do
            .horizontal = other.horizontal
        if other.mask & 2 do
            .vertical = other.vertical
        if other.mask & 4 do
            .wrap = other.wrap
        if other.mask & 8 do
            .indent = other.indent
        .mask    |= other.mask
        .limited = .limited or other.limited
    }
}

struct CellLook
{
    font:      CellFont
    fill:      u32
    edges:     [4] CellEdge
    alignment: CellAlignment
    limited:   bool
}

impl CellLook
{
    mtd const hasBorder()->bool
    {
        for edge in .edges where edge.width > 0 do
            return true
        return false
    }

    mtd const paintBorders(painter: *Painter, rect: Math.Rectangle, mask = 15'u32)
    {
        for edge, index in .edges where edge.width > 0 and (mask & (1'u32 << index))
        {
            var first, last: Math.Point
            switch index
            {
            case 0: first = {rect.x, rect.y}
                last = {rect.x, rect.bottom()}

            case 1: first = {rect.right(), rect.y}
                last = {rect.right(), rect.bottom()}

            case 2: first = {rect.x, rect.y}
                last = {rect.right(), rect.y}

            case 3: first = {rect.x, rect.bottom()}
                last = {rect.right(), rect.bottom()}
            }

            var pen = Pen.createDash(edge.dash, Color.fromArgb(edge.color), edge.width)
            pen.begCapStyle = .None
            pen.endCapStyle = .None
            painter.drawLine(first, last, pen)
            if edge.doubleLine
            {
                if index < 2
                {
                    first.x += index == 0 ? 2 : -2
                    last.x  = first.x
                }
                else
                {
                    first.y += index == 2 ? 2 : -2
                    last.y  = first.y
                }

                painter.drawLine(first, last, pen)
            }
        }
    }
}
