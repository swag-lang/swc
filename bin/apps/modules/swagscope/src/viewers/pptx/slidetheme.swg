#global internal
#global namespace Viewers.Pptx

using Core

// DrawingML colors belong to the document, independently of the application's palette.
struct SlideTheme
{
    colors:    [12] String
    colorMap:  [4] String
    titleSize: u32 = 4400     // Hundredths of a point.
    bodySize:  u32 = 1800
    otherSize: u32 = 1800
}

private const SchemeNames = ["dk1", "lt1", "dk2", "lt2", "accent1", "accent2", "accent3",
                             "accent4", "accent5", "accent6", "hlink", "folHlink"]

func isRgbHex(value: string)->bool
{
    if value.count != 6 do
        return false
    for digit in value where not Latin1.isHexDigit(digit) do
        return false
    return true
}

impl SlideTheme
{
    func defaults()->SlideTheme
    {
        var result: #returntype
        let values = ["000000", "FFFFFF", "1F497D", "EEECE1", "4F81BD", "C0504D", "9BBB59",
                      "8064A2", "4BACC6", "F79646", "0000FF", "800080"]
        for value, index in values do
            result.colors[index] = value
        for value, index in ["dk1", "dk2", "lt1", "lt2"] do
            result.colorMap[index] = value
        return result
    }

    mtd const color(name: string)->String
    {
        var scheme = name
        for aliasName, index in ["tx1", "tx2", "bg1", "bg2"] where aliasName == name do
            scheme = .colorMap[index]
        for value, index in SchemeNames where value == scheme do
            return .colors[index]
        return {}
    }

    mtd read(source: string)
    {
        var scan     = Package.Scanner.create(source)
        var token:     Package.Token
        var inScheme = false
        var selected = Swag.U64.Max
        var textStyle: string = ""
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("clrMap") or token.isElement("overrideClrMapping")
                {
                    for name, index in ["tx1", "tx2", "bg1", "bg2"]
                    {
                        if let value = token.attribute(name) do
                            .colorMap[index] = value
                    }
                }

                if token.isElement("clrScheme")
                {
                    inScheme = true
                }
                elif inScheme
                {
                    for name, index in SchemeNames where token.isElement(name) do
                        selected = index
                    if selected < .colors.count
                    {
                        let value = token.isElement("sysClr") ? (token.attribute("lastClr") orelse "") : (token.attribute("val") orelse "")
                        if (token.isElement("srgbClr") or token.isElement("sysClr")) and isRgbHex(value) do
                            .colors[selected] = value
                    }
                }

                if token.isElement("titleStyle")
                {
                    textStyle = "title"
                }
                elif token.isElement("bodyStyle")
                {
                    textStyle = "body"
                }
                elif token.isElement("otherStyle")
                {
                    textStyle = "other"
                }
                elif token.isElement("defRPr") and textStyle.count
                {
                    let size = catch StrConv.toU32(token.attribute("sz") orelse "") orelse 0
                    if size >= 100 and size <= 40000
                    {
                        switch textStyle
                        {
                        case "title": .titleSize = size
                        case "body":  .bodySize = size
                        case "other": .otherSize = size
                        }

                        textStyle = ""
                    }
                }
            }
            elif token.kind == .End
            {
                if token.isElement("clrScheme") do
                    inScheme = false
                if token.isElement("titleStyle") or
                   token.isElement("bodyStyle") or
                   token.isElement("otherStyle") do
                    textStyle = ""
            }
        }
    }
}
