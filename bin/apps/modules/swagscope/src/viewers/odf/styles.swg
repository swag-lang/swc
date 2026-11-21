#global internal
#global namespace Viewers.Odf

using Core

enum StyleFamily { Other, Paragraph, Text, Table, Cell, Graphic, Presentation }

private func familyOf(value: string)->StyleFamily
{
    switch value
    {
    case "paragraph":    return .Paragraph
    case "text":         return .Text
    case "table":        return .Table
    case "table-cell":   return .Cell
    case "presentation": return .Presentation
    case "graphic":      return .Graphic
    default:             return .Other
    }
}

private func styleKey(name: string, family: StyleFamily)->String => Format.toString("%:%", cast(u32, family), name)

private struct NamedStyle
{
    name:       String
    parent:     String
    family:     StyleFamily
    properties: Properties
    resolved:   Properties
}

// The first authored page geometry supplies a bounded reading measure and inset.
enum PageMargin { Top, Bottom, Left, Right }

struct PageGeometry
{
    width:   f64
    top:     f64
    bottom:  f64
    left:    f64
    right:   f64
    valid:   bool
    limited: bool
}

impl PageGeometry
{
    mtd const pageWidthCssPixels()->f32
    {
        if not .valid or .width <= .left + .right or .width > 1584 do
            return 680
        return cast(f32, Math.clamp(.width * 4 / 3, 320, 1200))
    }

    mtd const cssInsets()->String
    {
        if not .valid or .width <= .left + .right or .width > 1584 do
            return String.from("24px")
        return Format.toString("%px %px %px %px",
                               cast(u32, Math.round(.top * 4 / 3)),
                               cast(u32, Math.round(.right * 4 / 3)),
                               cast(u32, Math.round(.bottom * 4 / 3)),
                               cast(u32, Math.round(.left * 4 / 3)))
    }

    mtd readMargin(token: const *Package.Token, attribute: string, side: PageMargin)
    {
        if let value = token.attribute(attribute)
        {
            let margin = Odf.points(value)
            if not margin.valid or margin.value < 0
            {
                .limited = true
                return
            }

            switch side
            {
            case .Top:    .top = margin.value
            case .Bottom: .bottom = margin.value
            case .Left:   .left = margin.value
            case .Right:  .right = margin.value
            }
        }
    }
}

// Common and automatic ODF styles share bounded names and an acyclic reading projection.
struct StyleCatalog
{
    fonts:     HashTable'(String, String)
    styles:    Array'NamedStyle
    index:     HashTable'(String, u64)
    defaults:  [7] Properties
    lists:     HashTable'(String, bool)
    pageColor: String
    page:      PageGeometry
}

impl StyleCatalog
{
    mtd read(source: string) fail
    {
        var scan = Package.Scanner.create(source)
        var token: Package.Token
        while scan.next(&token)
        {
            if token.kind != .Start or not token.isElement("font-face") do
                continue
            let name   = String.from(token.attribute("name") orelse "")
            let family = fontFamily(token.attribute("font-family") orelse "")
            if name.count > 256 or .fonts.count >= 1024 do
                fail Errors.UnsupportedFormatError{Odt.texts().err_TooLarge}
            if not name.isEmpty() and not family.isEmpty()
            {
                if let entry = .fonts.tryFind(name) do
                    entry.value = family
                else do
                    .fonts.add(name, family)
            }
        }

        scan = Package.Scanner.create(source)
        var current:  NamedStyle
        var inStyle   = false
        var isDefault = false
        var listName: String
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("style") or token.isElement("default-style")
                {
                    current        = {}
                    current.name   = token.attribute("name") orelse ""
                    current.parent = token.attribute("parent-style-name") orelse ""
                    current.family = familyOf(token.attribute("family") orelse "")
                    if current.name.count > 256 or current.parent.count > 256 do
                        fail Errors.UnsupportedFormatError{Odt.texts().err_TooLarge}
                    let outline = catch StrConv.toS32(token.attribute("default-outline-level") orelse "0") orelse 0
                    if outline > 0 and outline <= 10 do
                        current.properties.paragraph.outline = outline - 1
                    inStyle   = current.family != .Other
                    isDefault = token.isElement("default-style")
                }
                elif inStyle
                {
                    if token.isElement("text-properties") do
                        current.properties.readText(&token, &.fonts)
                    elif token.isElement("paragraph-properties") do
                        current.properties.readParagraph(&token)
                    elif token.isElement("table-cell-properties") or token.isElement("table-properties") do
                        current.properties.readCell(&token)
                    elif token.isElement("map") do
                        current.properties.limited = true
                }
                elif token.isElement("page-layout-properties")
                {
                    if .page.valid
                    {
                        .page.limited = true
                    }
                    else
                    {
                        let width = Odf.points(token.attribute("page-width") orelse "")
                        if width.valid and width.value > 0
                        {
                            .page.width = width.value
                            .page.valid = true
                            .page.readMargin(&token, "margin-top", .Top)
                            .page.readMargin(&token, "margin-bottom", .Bottom)
                            .page.readMargin(&token, "margin-left", .Left)
                            .page.readMargin(&token, "margin-right", .Right)

                            if .page.width <= .page.left + .page.right or .page.width > 1584 do
                                .page.limited = true
                        }
                        elif token.attribute("page-width") != null
                        {
                            .page.limited = true
                        }
                    }

                    let color = rgb(token.attribute("background-color") orelse "")
                    if not color.isEmpty() do
                        .pageColor = color
                }

                if token.isElement("list-style")
                {
                    listName = token.attribute("name") orelse ""
                }
                elif not listName.isEmpty() and token.isElement("list-level-style-number")
                {
                    if let entry = .lists.tryFind(listName) do
                        entry.value = true
                    else do
                        .lists.add(listName, true)
                }
            }

            if token.kind == .End or token.empty
            {
                if (token.isElement("style") or token.isElement("default-style")) and inStyle
                {
                    if isDefault
                    {
                        .defaults[cast(u32, current.family)].overlay(&current.properties)
                    }
                    elif not current.name.isEmpty()
                    {
                        let key = styleKey(current.name, current.family)
                        if let item = .index.tryFind(key)
                        {
                            .styles[item.value] = current
                        }
                        else
                        {
                            .index.add(key, .styles.count)
                            .styles.add(current)
                        }
                    }

                    inStyle = false
                }

                if token.isElement("list-style") do
                    listName.clear()
            }

            if .styles.count > 4096 or .lists.count > 1024 do
                fail Errors.UnsupportedFormatError{Odt.texts().err_TooLarge}
        }

        if scan.damaged do
            fail Errors.InvalidFormatError{Odt.texts().err_Invalid}
    }

    mtd finish()
    {
        for index in .styles.count
        {
            let resolved = .resolve(index)
            .styles[index].resolved = resolved
        }
    }

    private mtd const resolve(index: u64)->Properties
    {
        let family  = .styles[index].family
        var result  = .defaults[cast(u32, family)]
        var chain: Array'u64
        var current = index
        while true
        {
            var repeated = false
            for previous in chain where previous == current do
                repeated = true
            if repeated or chain.count >= 64
            {
                result.limited = true
                break
            }

            chain.add(current)
            let style = &.styles[current]
            if style.parent.isEmpty() do
                break
            let parent = .index.tryFind(styleKey(style.parent, family))
            if not parent
            {
                result.limited = true
                break
            }

            current = parent.value
        }

        for offset in chain.count do
            result.overlay(&.styles[chain[chain.count - offset - 1]].properties)
        return result
    }

    mtd const lookup(name: string, family: StyleFamily)->Properties
    {
        if not name.count do
            return .defaults[cast(u32, family)]
        let item = .index.tryFind(styleKey(name, family))
        if item do
            return .styles[item.value].resolved
        var result = .defaults[cast(u32, family)]
        result.limited = true
        return result
    }
}
