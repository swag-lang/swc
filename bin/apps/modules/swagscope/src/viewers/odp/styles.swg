#global internal
#global namespace Viewers.Odp

using Core

struct Paint
{
    fill:           String
    line:           String
    lineWidth:      f32 = 1
    inset:          [4] f32
    mask:           u32
    centered:       Docx.FormatSwitch
    showMaster:     Docx.FormatSwitch
    showBackground: Docx.FormatSwitch
    fillEnabled:    Docx.FormatSwitch
    lineEnabled:    Docx.FormatSwitch
    limited:        bool
}

private impl Paint
{
    internal mtd overlay(other: const *Paint)
    {
        if other.mask & 1 do
            .fill = other.fill
        if other.mask & 2 do
            .line = other.line
        if other.mask & 4 do
            .lineWidth = other.lineWidth
        for index in 4 where other.mask & (8'u32 << index) do
            .inset[index] = other.inset[index]
        if other.centered != .Inherit do
            .centered = other.centered
        if other.showMaster != .Inherit do
            .showMaster = other.showMaster
        if other.showBackground != .Inherit do
            .showBackground = other.showBackground
        if other.fillEnabled != .Inherit do
            .fillEnabled = other.fillEnabled
        if other.lineEnabled != .Inherit do
            .lineEnabled = other.lineEnabled
        .mask    |= other.mask
        .limited = .limited or other.limited
    }

    mtd read(token: const *Package.Token)
    {
        if let value = token.attribute("background-objects-visible") do
            .showMaster = value == "false" ? .Off : .On
        if let value = token.attribute("background-visible") do
            .showBackground = value == "false" ? .Off : .On
        if let value = token.attribute("fill")
        {
            if value == "none"
            {
                .fillEnabled = .Off
            }
            elif value == "solid"
            {
                .fillEnabled = .On
            }
            else
            {
                .fillEnabled = .Off
                .limited     = true
            }
        }

        if let value = token.attribute("fill-color")
        {
            .mask |= 1
            .fill = Odf.rgb(value)
            if .fill.isEmpty() do
                .limited = true
        }

        if let value = token.attribute("stroke")
        {
            if value == "none"
            {
                .lineEnabled = .Off
            }
            elif value == "solid"
            {
                .lineEnabled = .On
            }
            else
            {
                .lineEnabled = .Off
                .limited     = true
            }
        }

        if let value = token.attribute("stroke-color")
        {
            .mask |= 2
            .line = Odf.rgb(value)
            if .line.isEmpty() do
                .limited = true
        }

        if let value = token.attribute("stroke-width")
        {
            let size = Odf.points(value)
            if size.valid and size.value >= 0 and size.value <= 24
            {
                .mask      |= 4
                .lineWidth = cast(f32, size.value * 4 / 3)
            }
            else
            {
                .limited = true
            }
        }

        for name, index in ["padding-left", "padding-top", "padding-right", "padding-bottom"]
        {
            let value = token.attribute(name) orelse token.attribute("padding")
            if not value do
                continue
            let size = Odf.points(value)
            if size.valid and size.value >= 0
            {
                .mask         |= 8'u32 << index
                .inset[index] = cast(f32, size.value * 4 / 3)
            }
            else
            {
                .limited = true
            }
        }

        if let value = token.attribute("textarea-vertical-align") do
            .centered = value == "middle" ? .On : .Off
    }
}

private struct Named
{
    name:   String
    family: String
    parent: String
    paint:  Paint
}

struct Master
{
    layout: String
    style:  String
    source: String
}

struct Styles
{
    typography: Odf.StyleCatalog
    paints:     Array'Named
    index:      HashTable'(String, u64)
    defaults:   HashTable'(String, Paint)
    layouts:    HashTable'(String, Math.Point)
    masters:    HashTable'(String, Master)
}

private func key(name, family: string)->String => Format.toString("%:%", family, name)

impl Styles
{
    mtd read(source: string) fail
    {
        try .typography.read(source)
        var scan      = Package.Scanner.create(source)
        var token:      Package.Token
        var current:    Named
        var inStyle   = false
        var isDefault = false
        var layout:     String
        var masterName: String
        var master:     Master
        var masterAt  = Swag.U64.Max
        while true
        {
            let at = scan.offset
            if not scan.next(&token) do
                break
            if token.kind == .Start
            {
                if token.isElement("style") or token.isElement("default-style")
                {
                    current        = {}
                    current.name   = token.attribute("name") orelse ""
                    current.family = token.attribute("family") orelse ""
                    current.parent = token.attribute("parent-style-name") orelse ""
                    inStyle        = current.family == "graphic" or
                                     current.family == "presentation" or
                                     current.family == "drawing-page"
                    isDefault = token.isElement("default-style")
                    if current.name.count > 256 or current.parent.count > 256 do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                }
                elif inStyle and (token.isElement("graphic-properties") or token.isElement("drawing-page-properties"))
                {
                    current.paint.read(&token)
                }

                if token.isElement("page-layout")
                {
                    layout = token.attribute("name") orelse ""
                }
                elif not layout.isEmpty() and token.isElement("page-layout-properties")
                {
                    let width  = Odf.points(token.attribute("page-width") orelse "")
                    let height = Odf.points(token.attribute("page-height") orelse "")
                    if not width.valid or not height.valid or width.value < 1 or height.value < 1 do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    let size = Math.Point{cast(f32, width.value * 4 / 3), cast(f32, height.value * 4 / 3)}
                    if let entry = .layouts.tryFind(layout) do
                        entry.value = size
                    else do
                        .layouts.add(layout, size)
                }

                if token.isElement("master-page")
                {
                    masterName    = token.attribute("name") orelse ""
                    master.layout = token.attribute("page-layout-name") orelse ""
                    master.style  = token.attribute("style-name") orelse ""
                    masterAt      = at
                }
            }

            if token.kind == .End or token.empty
            {
                if (token.isElement("style") or token.isElement("default-style")) and inStyle
                {
                    if isDefault
                    {
                        if let entry = .defaults.tryFind(current.family) do
                            entry.value.overlay(&current.paint)
                        else do
                            .defaults.add(current.family, current.paint)
                    }
                    elif not current.name.isEmpty()
                    {
                        let name = key(current.name, current.family)
                        if let entry = .index.tryFind(name)
                        {
                            .paints[entry.value] = current
                        }
                        else
                        {
                            .index.add(name, .paints.count)
                            .paints.add(current)
                        }
                    }

                    inStyle = false
                }

                if token.isElement("page-layout") do
                    layout.clear()
                if token.isElement("master-page") and masterAt != Swag.U64.Max
                {
                    master.source = source[masterAt until scan.offset]
                    if let entry = .masters.tryFind(masterName) do
                        entry.value = master
                    else do
                        .masters.add(masterName, master)
                    masterAt = Swag.U64.Max
                }
            }

            if .paints.count > 4096 or .masters.count > 200 or .layouts.count > 200 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }
    }

    mtd const paint(name, family: string)->Paint
    {
        var result: Paint
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
                result.limited = true
                break
            }

            chain.add(next.value)
            let parent = .paints[next.value].parent
            if parent.isEmpty() do
                break
            next = .index.tryFind(key(parent, family))
            if not next do
                result.limited = true
        }

        if chain.isEmpty() do
            result.limited = true
        for offset in chain.count do
            result.overlay(&.paints[chain[chain.count - offset - 1]].paint)
        return result
    }
}
