#global internal
#global namespace Viewers.Odf

using Core

// ODF properties adapt to the existing reading typography and point-based paragraph model.
struct Properties
{
    run:       Docx.RunFormat
    paragraph: Docx.ParagraphFormat
    cellCss:   String
    scale:     f64 = 1
    limited:   bool
}

impl Properties
{
    mtd overlay(other: const *Properties)
    {
        .run.overlay(&other.run)
        .paragraph.overlay(&other.paragraph)
        if other.run.size
        {
            .scale = other.scale
        }
        elif other.scale != 1
        {
            if .run.size do
                .run.size = cast(u32, Math.clamp(Math.round(cast(f64, .run.size) * other.scale), 1, 800))
            else do
                .scale *= other.scale
        }

        if .scale < 0.05 or .scale > 16
        {
            .scale   = Math.clamp(.scale, 0.05, 16)
            .limited = true
        }

        if not other.cellCss.isEmpty()
        {
            .cellCss += other.cellCss
            if .cellCss.count > 2048
            {
                .cellCss = other.cellCss
                .limited = true
            }
        }

        .limited = .limited or other.limited or .run.limited or .paragraph.limited
    }

    mtd readText(token: const *Package.Token, fonts: const *HashTable'(String, String))
    {
        if let value = token.attribute("font-weight")
        {
            let weight = catch StrConv.toU32(value) orelse 0
            if value == "bold" or weight >= 600 do
                .run.bold = .On
            elif value == "normal" or (weight >= 100 and weight <= 500) do
                .run.bold = .Off
            else do
                .limited = true
        }

        if let value = token.attribute("font-style") do
            .run.italic = value == "normal" ? .Off : .On
        if let value = token.attribute("text-underline-style") do
            .run.underline = value == "none" ? .Off : .On
        if let value = token.attribute("text-line-through-style") do
            .run.strike = value == "none" ? .Off : .On
        if let value = token.attribute("display") do
            .run.hidden = value == "none" ? .On : .Off
        if let value = token.attribute("font-size")
        {
            if Utf8.endsWith(value, "%")
            {
                let percent = catch StrConv.toF64(value[until value.count - 1]) orelse 0
                if Math.isFinite(percent) and percent >= 5 and percent <= 400 do
                    .scale = percent / 100
                else do
                    .limited = true
            }
            else
            {
                let size = points(value)
                if size.valid and size.value > 0 and size.value <= 400 do
                    .run.size = cast(u32, Math.max(Math.round(size.value * 2), 1))
                else do
                    .limited = true
            }
        }

        if let value = token.attribute("color")
        {
            let color = rgb(value)
            if not color.isEmpty() do
                .run.color = color
            else do
                .limited = true
        }

        if let value = token.attribute("background-color")
        {
            if value == "transparent"
            {
                .run.highlight = "none"
            }
            else
            {
                let color = rgb(value)
                if not color.isEmpty() do
                    .run.highlight = color
                else do
                    .limited = true
            }
        }

        let named  = token.attribute("font-name")
        var family = token.attribute("font-family") orelse ""
        if named
        {
            if let font = fonts.tryFind(String.from(named)) do
                family = font.value
        }

        if family.count
        {
            .run.family = fontFamily(family)
            if .run.family.isEmpty() do
                .limited = true
        }
    }

    mtd readParagraph(token: const *Package.Token)
    {
        if let value = token.attribute("text-align")
        {
            if value == "start" or value == "left" do
                .paragraph.alignment = "left"
            elif value == "end" or value == "right" do
                .paragraph.alignment = "right"
            elif value == "center" or value == "justify" do
                .paragraph.alignment = value
            else do
                .limited = true
        }

        let names = ["margin-top", "margin-bottom", "margin-left", "margin-right", "text-indent"]
        for name, index in names
        {
            let value = token.attribute(name)
            if not value do
                continue
            let length = points(value)
            if not length.valid
            {
                .limited = true
                continue
            }

            let twips = cast(s32, Math.round(length.value * 20))
            switch index
            {
            case 0:
                .paragraph.before = Math.max(twips, 0)

            case 1:
                .paragraph.after = Math.max(twips, 0)

            case 2:
                .paragraph.left       = twips
                .paragraph.indentMask |= 1

            case 3:
                .paragraph.right      = twips
                .paragraph.indentMask |= 2

            case 4:
                .paragraph.first      = twips
                .paragraph.indentMask |= 4
            }
        }

        if let value = token.attribute("line-height")
        {
            if Utf8.endsWith(value, "%")
            {
                let percent = catch StrConv.toF64(value[until value.count - 1]) orelse 0
                if Math.isFinite(percent) and percent > 0 and percent <= 1000
                {
                    .paragraph.line     = cast(s32, Math.round(percent * 2.4))
                    .paragraph.lineRule = "auto"
                }
                else
                {
                    .limited = true
                }
            }
            elif value == "normal"
            {
                .paragraph.line     = 240
                .paragraph.lineRule = "auto"
            }
            else
            {
                let length = points(value)
                if length.valid and length.value > 0
                {
                    .paragraph.line     = cast(s32, Math.round(length.value * 20))
                    .paragraph.lineRule = "exact"
                }
                else
                {
                    .limited = true
                }
            }
        }

        if let value = token.attribute("break-before") do
            .paragraph.pageBefore = value == "page" ? .On : .Off
    }

    mtd readCell(token: const *Package.Token)
    {
        let numbers: Globalization.NumberFormatInfo
        if let value = token.attribute("background-color")
        {
            let color = rgb(value)
            if value == "transparent" do
                .cellCss += "background-color:transparent;"
            elif not color.isEmpty() do
                .cellCss += Format.toString("background-color:#%;", color)
            else do
                .limited = true
        }

        for name in ["padding", "padding-left", "padding-right", "padding-top", "padding-bottom"]
        {
            let value = token.attribute(name)
            if not value do
                continue
            let length = points(value)
            if length.valid and length.value >= 0 do
                .cellCss += Format.toString("%:%pt;", name, numbers.format(length.value, 3))
            else do
                .limited = true
        }

        for name in ["border", "border-left", "border-right", "border-top", "border-bottom"]
        {
            let value = token.attribute(name)
            if not value do
                continue
            if value == "none"
            {
                .cellCss += Format.toString("%:none;", name)
                continue
            }

            let words = Tokenize.split(value, ' 'rune)
            if words.count != 3
            {
                .limited = true
                continue
            }

            let width = points(words[0])
            let kind  = words[1]
            let color = rgb(words[2])
            if width.valid and
               width.value >= 0 and
               width.value <= 24 and
               not color.isEmpty() and
               (kind == "solid" or kind == "dotted" or kind == "dashed" or kind == "double") do
                .cellCss += Format.toString("%:%pt % #%;", name, numbers.format(width.value, 3), kind, color)
            else do
                .limited = true
        }
    }

    mtd const applyRun(run: *Docx.RunFormat)
    {
        run.overlay(&.run)
        if .scale != 1 do
            run.size = cast(u32, Math.clamp(Math.round(cast(f64, run.size ? run.size : 24) * .scale), 1, 800))
    }
}
