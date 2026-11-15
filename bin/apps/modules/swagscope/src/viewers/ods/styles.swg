#global internal
#global namespace Viewers.Ods

using Core, Pixel

private struct Delta
{
    look:    Xlsx.CellLook
    mask:    u32
    width:   f32 = -1
    height:  f32 = -1
    display: Docx.FormatSwitch
}

private impl Delta
{
    mtd overlay(other: const *Delta)
    {
        if other.mask & 1 do
            .look.fill = other.look.fill
        for index in 4 where other.mask & (2'u32 << index) do
            .look.edges[index] = other.look.edges[index]
        .mask |= other.mask
        .look.alignment.apply(&other.look.alignment)
        .look.limited = .look.limited or other.look.limited
        if other.width >= 0 do
            .width = other.width
        if other.height >= 0 do
            .height = other.height
        if other.display != .Inherit do
            .display = other.display
    }
}

private struct Named
{
    name:   String
    family: String
    parent: String
    delta:  Delta
}

// ODF style geometry and cell paint adapt directly to the native workbook model.
struct Styles
{
    typography: Odf.StyleCatalog
    names:      Array'Named
    index:      HashTable'(String, u64)
    cellIds:    HashTable'(String, u32)
    defaults:   HashTable'(String, Delta)
    cells:      Xlsx.CellStyles
}

private func key(name, family: string)->String => Format.toString("%:%", family, name)

private func color(value: string)->u32
{
    let rgb = Odf.rgb(value)
    if rgb.isEmpty() do
        return 0
    return (catch StrConv.toU32(Format.toString("0x%", rgb)) orelse 0) | 0xFF000000
}

private func edge(value: string)->Xlsx.CellEdge
{
    var result: #returntype
    if value == "none" do
        return result
    let words = Tokenize.split(value, ' 'rune)
    if words.count != 3 do
        return result
    let width = Odf.points(words[0])
    if not width.valid or width.value < 0 or width.value > 24 do
        return result
    result.color = color(words[2])
    if not result.color do
        return {}
    result.width = cast(f32, width.value * 4 / 3)
    switch words[1]
    {
    case "solid":  result.dash = .None
    case "dotted": result.dash = .Dot
    case "dashed": result.dash = .Dash
    case "double": result.doubleLine = true
    default:       return {}
    }

    return result
}

private func readDelta(result: *Delta, token: const *Package.Token)
{
    if let value = token.attribute("background-color")
    {
        result.mask      |= 1
        result.look.fill = color(value)
        if value != "transparent" and not result.look.fill do
            result.look.limited = true
    }

    for name, index in ["border-left", "border-right", "border-top", "border-bottom"]
    {
        let value = token.attribute(name) orelse token.attribute("border")
        if not value do
            continue
        result.mask |= 2'u32 << index
        result.look.edges[index] = edge(value)
        if value != "none" and not result.look.edges[index].width do
            result.look.limited = true
    }

    if let value = token.attribute("vertical-align")
    {
        result.look.alignment.mask |= 2
        switch value
        {
        case "top":    result.look.alignment.vertical = .Top
        case "middle": result.look.alignment.vertical = .Center
        case "bottom", "automatic": result.look.alignment.vertical = .Bottom
        default:       result.look.limited = true
        }
    }

    if let value = token.attribute("wrap-option")
    {
        result.look.alignment.mask |= 4
        result.look.alignment.wrap = value == "wrap"
    }

    if let value = token.attribute("text-align")
    {
        result.look.alignment.mask |= 1
        switch value
        {
        case "left", "start": result.look.alignment.horizontal = .Left
        case "right", "end":  result.look.alignment.horizontal = .Right
        case "center":        result.look.alignment.horizontal = .Center
        default:              result.look.limited = true
        }
    }

    if token.attribute("text-align-source") == "value-type"
    {
        result.look.alignment.mask       |= 1
        result.look.alignment.horizontal = .General
    }

    if let value = token.attribute("column-width")
    {
        let size = Odf.points(value)
        if size.valid and size.value >= 0 do
            result.width = cast(f32, size.value * 4 / 3)
        else do
            result.look.limited = true
    }

    if let value = token.attribute("row-height")
    {
        let size = Odf.points(value)
        if size.valid and size.value >= 0 do
            result.height = cast(f32, size.value * 4 / 3)
        else do
            result.look.limited = true
    }

    if let value = token.attribute("display") do
        result.display = value == "false" ? .Off : .On
    if (token.attribute("rotation-angle") orelse "0") != "0" or
       token.attribute("shrink-to-fit") == "true" or
       token.attribute("repeat-content") == "true" do
        result.look.limited = true
}

impl Styles
{
    mtd read(source: string) fail
    {
        try .typography.read(source)
        var scan      = Package.Scanner.create(source)
        var token:   Package.Token
        var current: Named
        var inStyle   = false
        var isDefault = false
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("style") or token.isElement("default-style")
                {
                    current        = {}
                    current.name   = token.attribute("name") orelse ""
                    current.family = token.attribute("family") orelse ""
                    current.parent = token.attribute("parent-style-name") orelse ""
                    inStyle        = current.family == "table-cell" or
                                     current.family == "table-column" or
                                     current.family == "table-row" or
                                     current.family == "table"
                    isDefault = token.isElement("default-style")
                    if current.name.count > 256 or current.parent.count > 256 do
                        fail Errors.UnsupportedFormatError{Odt.texts().err_TooLarge}
                }
                elif inStyle
                {
                    readDelta(&current.delta, &token)
                }
            }

            if token.kind == .End or token.empty
            {
                if (token.isElement("style") or token.isElement("default-style")) and inStyle
                {
                    if isDefault
                    {
                        if let entry = .defaults.tryFind(current.family) do
                            entry.value.overlay(&current.delta)
                        else do
                            .defaults.add(current.family, current.delta)
                    }
                    elif not current.name.isEmpty()
                    {
                        let name = key(current.name, current.family)
                        if let entry = .index.tryFind(name)
                        {
                            .names[entry.value] = current
                        }
                        else
                        {
                            .index.add(name, .names.count)
                            .names.add(current)
                        }
                    }

                    inStyle = false
                }
            }

            if .names.count > 4096 do
                fail Errors.UnsupportedFormatError{Odt.texts().err_TooLarge}
        }
    }

    mtd const geometry(name, family: string)->Delta
    {
        var result: Delta
        if let entry = .defaults.tryFind(String.from(family)) do
            result = entry.value
        if not name.count do
            return result
        var chain: Array'u64
        var next = .index.tryFind(key(name, family))
        while next
        {
            var repeated = false
            for previous in chain where previous == next.value do
                repeated = true
            if repeated or chain.count >= 64
            {
                result.look.limited = true
                break
            }

            chain.add(next.value)
            let parent = .names[next.value].parent
            if parent.isEmpty() do
                break
            next = .index.tryFind(key(parent, family))
            if not next do
                result.look.limited = true
        }

        if chain.isEmpty() do
            result.look.limited = true
        for offset in chain.count do
            result.overlay(&.names[chain[chain.count - offset - 1]].delta)
        return result
    }

    mtd finish()
    {
        .typography.finish()
        .cells.styles.add(.cellLook(""))
        for style in .names where style.family == "table-cell"
        {
            .cellIds.add(style.name, cast(u32, .cells.styles.count))
            .cells.styles.add(.cellLook(style.name))
        }

        .cells.normalFont = .cells.styles[0].font
    }

    private mtd const cellLook(name: string)->Xlsx.CellLook
    {
        var result     = .geometry(name, "table-cell").look
        let properties = .typography.lookup(name, .Cell)
        var run: Docx.RunFormat
        run.size = 22
        properties.applyRun(&run)
        result.font.size      = cast(f32, run.size) / 2
        result.font.bold      = run.bold == .On
        result.font.italic    = run.italic == .On
        result.font.underline = run.underline == .On
        result.font.strike    = run.strike == .On
        if not run.color.isEmpty() do
            result.font.color = color(Format.toString("#%", run.color))
        var family = run.family.toLower()
        result.font.mono = Utf8.contains(family, "mono") or
                           Utf8.contains(family, "courier") or
                           Utf8.contains(family, "consolas")
        if properties.paragraph.left > 0
        {
            result.alignment.indent = cast(u32, Math.round(cast(f64, properties.paragraph.left) / 240))
            result.limited = true
        }

        result.limited = result.limited or properties.limited
        return result
    }

    mtd const cellId(name: string)->u32
    {
        if not name.count do
            return 0
        if let entry = .cellIds.tryFind(String.from(name)) do
            return entry.value
        return Swag.U32.Max
    }
}
