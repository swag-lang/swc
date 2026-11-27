#global internal
#global namespace Viewers.Package

using Core

private const SchemeNames = ["dk1", "lt1", "dk2", "lt2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink"]

func isRgbHex(value: string)->bool
{
    if value.count != 6
    {
        return false
    }

    for digit in value where not Latin1.isHexDigit(digit)
    {
        return false
    }

    return true
}

// Shared OOXML theme colors and Latin typefaces; document-specific aliases remain with the reader.
struct OfficeTheme
{
    defined:   bool
    colors:    [12] String
    majorFont: String
    minorFont: String
}

impl OfficeTheme
{
    func defaults()->OfficeTheme
    {
        var result: #returntype
        let values = ["000000", "FFFFFF", "1F497D", "EEECE1", "4F81BD", "C0504D", "9BBB59", "8064A2", "4BACC6", "F79646", "0000FF", "800080"]
        for value, index in values
        {
            result.colors[index] = value
        }

        return result
    }

    mtd const color(name: string)->String
    {
        for value, index in SchemeNames where value == name
        {
            return .colors[index]
        }

        return {}
    }

    mtd read(source: string)
    {
        var scan          = Scanner.create(source)
        var token: Token
        var inScheme      = false
        var selected      = Swag.U64.Max
        var font:  string = ""
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("theme")
                {
                    .defined = true
                }

                if token.isElement("clrScheme")
                {
                    inScheme = not token.empty
                }
                else if inScheme
                {
                    for name, index in SchemeNames where token.isElement(name)
                    {
                        selected = index
                    }

                    if selected < .colors.count
                    {
                        let value = token.isElement("sysClr") ? (token.attribute("lastClr") orelse "") : (token.attribute("val") orelse "")
                        if (token.isElement("srgbClr") or token.isElement("sysClr")) and isRgbHex(value)
                        {
                            .colors[selected] = value
                        }
                    }
                }

                if token.isElement("majorFont")
                {
                    font = "major"
                }
                else if token.isElement("minorFont")
                {
                    font = "minor"
                }
                else if font.count and token.isElement("latin")
                {
                    let name = token.attribute("typeface") orelse ""
                    if name.count <= 256
                    {
                        if font == "major"
                        {
                            .majorFont = name
                        }
                        else
                        {
                            .minorFont = name
                        }
                    }
                }
            }
            else if token.kind == .End
            {
                if token.isElement("clrScheme")
                {
                    inScheme = false
                }

                if token.isElement("majorFont") or token.isElement("minorFont")
                {
                    font = ""
                }
            }
        }
    }
}
