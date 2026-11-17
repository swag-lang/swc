#global internal
#global namespace Viewers.Docx

using Core, Pixel

enum FormatSwitch
{
    Inherit
    Off
    On
}

// Explicit states distinguish an inherited value from a direct-format reset.
struct RunFormat
{
    bold:      FormatSwitch
    italic:    FormatSwitch
    underline: FormatSwitch
    strike:    FormatSwitch
    hidden:    FormatSwitch
    size:      u32     // Half-points.
    family:    String
    color:     String
    highlight: String
    limited:   bool
}

impl RunFormat
{
    mtd overlay(other: const *RunFormat)
    {
        if other.bold != .Inherit do
            .bold = other.bold
        if other.italic != .Inherit do
            .italic = other.italic
        if other.strike != .Inherit do
            .strike = other.strike
        if other.hidden != .Inherit do
            .hidden = other.hidden
        .copyDisplay(other)
    }

    // Character toggles compose in styles; direct formatting sets their state.
    mtd applyStyle(other: const *RunFormat)
    {
        if other.bold == .On do
            .bold = .bold == .On ? .Off : .On
        if other.italic == .On do
            .italic = .italic == .On ? .Off : .On
        if other.strike == .On do
            .strike = .strike == .On ? .Off : .On
        if other.hidden == .On do
            .hidden = .hidden == .On ? .Off : .On
        .copyDisplay(other)
    }

    private mtd copyDisplay(other: const *RunFormat)
    {
        if other.underline != .Inherit do
            .underline = other.underline
        if other.size do
            .size = other.size
        if not other.family.isEmpty() do
            .family = other.family
        if not other.color.isEmpty() do
            .color = other.color
        if not other.highlight.isEmpty() do
            .highlight = other.highlight
        .limited = .limited or other.limited
    }

    mtd read(token: const *Package.Token, theme: const *Package.OfficeTheme)
    {
        let value   = token.attribute("val") orelse ""
        let enabled = value != "0" and value != "false" and value != "off"
        if token.isElement("b")
        {
            .bold = enabled ? .On : .Off
        }
        elif token.isElement("i")
        {
            .italic = enabled ? .On : .Off
        }
        elif token.isElement("strike")
        {
            .strike = enabled ? .On : .Off
        }
        elif token.isElement("vanish")
        {
            .hidden = enabled ? .On : .Off
        }
        elif token.isElement("u")
        {
            .underline = enabled and value != "none" ? .On : .Off
            if enabled and value.count and value != "single" and value != "none" do
                .limited = true
        }
        elif token.isElement("sz")
        {
            let size = catch StrConv.toU32(value) orelse 0
            if size >= 1 and size <= 800 do
                .size = size
            else do
                .limited = true
        }
        elif token.isElement("rFonts")
        {
            let named  = token.attribute("ascii") orelse token.attribute("hAnsi")
            let themed = token.attribute("asciiTheme") orelse token.attribute("hAnsiTheme") orelse ""
            let name   = named orelse (Utf8.startsWith(themed, "major") ? theme.majorFont.toString() : Utf8.startsWith(themed, "minor") ? theme.minorFont.toString() : "")
            var safe   = name.count <= 256
            for byte in name where byte < 128 and
                                   not Latin1.isLetterOrDigit(byte) and
                                   byte != ' 'u8 and
                                   byte != '-'u8 and
                                   byte != '.'u8 do
                safe = false
            if safe do
                .family = name
            else do
                .limited = true
        }
        elif token.isElement("color")
        {
            let name   = token.attribute("themeColor") orelse ""
            var scheme = name
            if name == "text1" or name == "dark1" do
                scheme = "dk1"
            elif name == "text2" or name == "dark2" do
                scheme = "dk2"
            elif name == "background1" or name == "light1" do
                scheme = "lt1"
            elif name == "background2" or name == "light2" do
                scheme = "lt2"
            elif name == "hyperlink" do
                scheme = "hlink"
            elif name == "followedHyperlink" do
                scheme = "folHlink"
            var color  = theme.defined ? theme.color(scheme) : String{}
            let themed = not color.isEmpty()
            if color.isEmpty() do
                color = value
            if color == "auto"
            {
                .color = "auto"
                return
            }

            if not Package.isRgbHex(color)
            {
                .limited = true
                return
            }

            let tint  = token.attribute("themeTint")
            let shade = token.attribute("themeShade")
            if themed and (tint or shade)
            {
                func modifier(value: string?)->{valid: bool, value: u32}
                {
                    var result: #returntype = {valid: true, value: 255}
                    if not value do
                        return result
                    if value.count != 2 or
                       not Latin1.isHexDigit(value[0]) or
                       not Latin1.isHexDigit(value[1])
                    {
                        result.valid = false
                        return result
                    }

                    let number = catch StrConv.toU32(Format.toString("0x%", value)) { result.valid = false; return result; }
                    result.value = number
                    return result
                }

                let tintValue  = modifier(tint)
                let shadeValue = modifier(shade)
                if not tintValue.valid or not shadeValue.valid
                {
                    .limited = true
                    return
                }

                let rgb = catch StrConv.toU32(Format.toString("0x%", color)) { .limited = true; return; }
                if tintValue.value == 255 and shadeValue.value == 255
                {
                    .color = color
                    return
                }

                let source = Color.fromArgb(0xFF000000 | rgb)
                let hsl    = source.toHsl()

                // These Word modifiers operate on byte-scale luminance.
                let high      = Math.max(source.r, Math.max(source.g, source.b))
                let low       = Math.min(source.r, Math.min(source.g, source.b))
                var luminance = (cast(u32, high) + low) / 2
                luminance = luminance * shadeValue.value / 255
                luminance = luminance * tintValue.value / 255 + 255 - tintValue.value
                let adjusted = Color.fromHsl(hsl.h, hsl.s, cast(f32, luminance) / 255)
                color = Format.toString("%{X02}%{X02}%{X02}", adjusted.r, adjusted.g, adjusted.b)
            }

            .color = color
        }
        elif token.isElement("highlight")
        {
            switch value
            {
            case "yellow":      .highlight = "FFFF00"
            case "green":       .highlight = "00FF00"
            case "cyan":        .highlight = "00FFFF"
            case "magenta":     .highlight = "FF00FF"
            case "blue":        .highlight = "0000FF"
            case "red":         .highlight = "FF0000"
            case "darkBlue":    .highlight = "000080"
            case "darkCyan":    .highlight = "008080"
            case "darkGreen":   .highlight = "008000"
            case "darkMagenta": .highlight = "800080"
            case "darkRed":     .highlight = "800000"
            case "darkYellow":  .highlight = "808000"
            case "darkGray":    .highlight = "808080"
            case "lightGray":   .highlight = "C0C0C0"
            case "black":       .highlight = "000000"
            case "white":       .highlight = "FFFFFF"
            case "none":        .highlight = "none"
            default:            .limited = true
            }
        }
    }

    mtd const css()->String
    {
        var result:  #returntype
        let numbers: Globalization.NumberFormatInfo
        if .size do
            result += Format.toString("font-size:%pt;", numbers.format(cast(f64, .size) / 2, 1))
        if not .family.isEmpty() do
            result += Format.toString("font-family:'%';", .family)
        if not .color.isEmpty() do
            result += .color == "auto" ? String.from("color:inherit;") : Format.toString("color:#%;", .color)
        if not .highlight.isEmpty() do
            result += .highlight == "none" ? String.from("background-color:transparent;") : Format.toString("background-color:#%;", .highlight)
        if .bold == .Off do
            result += "font-weight:normal;"
        if .italic == .Off do
            result += "font-style:normal;"
        return result
    }

    // Content has already been escaped, or is trusted embedded-image markup.
    mtd const appendHtml(output: *String, content: string)
    {
        if .hidden == .On do
            return
        let css = .css()
        if not css.isEmpty()
        {
            output[] += "<span style=\""
            Package.appendHtmlEscaped(output, css)
            output[] += "\">"
        }

        if .bold == .On do
            output[] += "<b>"
        if .italic == .On do
            output[] += "<i>"
        if .underline == .On do
            output[] += "<u>"
        if .strike == .On do
            output[] += "<s>"
        output[] += content
        if .strike == .On do
            output[] += "</s>"
        if .underline == .On do
            output[] += "</u>"
        if .italic == .On do
            output[] += "</i>"
        if .bold == .On do
            output[] += "</b>"
        if not css.isEmpty() do
            output[] += "</span>"
    }
}
