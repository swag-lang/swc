#global internal
#global namespace Viewers.Pptx

using Core, Pixel

// DrawingML colors belong to the document, independently of the application's palette.
struct SlideTheme
{
    office:    Package.OfficeTheme
    colorMap:  [4] String
    titleSize: u32 = 4400     // Hundredths of a point.
    bodySize:  u32 = 1800
    otherSize: u32 = 1800
}

impl SlideTheme
{
    func defaults()->SlideTheme
    {
        var result: #returntype
        result.office = Package.OfficeTheme.defaults()
        for value, index in ["dk1", "dk2", "lt1", "lt2"] do
            result.colorMap[index] = value
        return result
    }

    mtd const color(name: string)->String
    {
        var scheme = name
        for aliasName, index in ["tx1", "tx2", "bg1", "bg2"] where aliasName == name do
            scheme = .colorMap[index]
        return .office.color(scheme)
    }

    // Applies a DrawingML tint or shade to an RGB color. `value` uses OOXML's 100000 scale.
    mtd const transformColor(color: string, value: u32, tint: bool)->String
    {
        if not Package.isRgbHex(color) do
            return {}

        let rgb = catch StrConv.toU32(Format.toString("0x%", color)) { return {} }
        let amount = Math.min(value, 100_000)
        let red   = .transformChannel((rgb >> 16) & 255, amount, tint)
        let green = .transformChannel((rgb >> 8) & 255, amount, tint)
        let blue  = .transformChannel(rgb & 255, amount, tint)
        return Format.toString("%{X02}%{X02}%{X02}", red, green, blue)
    }

    private mtd const transformChannel(channel, value: u32, tint: bool)->u32
    {
        if tint do
            return channel + (((255 - channel) * value + 50_000) / 100_000)
        return (channel * value + 50_000) / 100_000
    }

    // Resolves one DrawingML color element, including its ordered luminance transforms.
    mtd const transformedColor(source: string)->String
    {
        var scan  = Package.Scanner.create(source)
        var token: Package.Token
        var color: String
        var inColor = false
        while scan.next(&token)
        {
            if token.kind == .Start and
               (token.isElement("srgbClr") or token.isElement("schemeClr") or token.isElement("sysClr"))
            {
                inColor = not token.empty
                if token.isElement("schemeClr")
                {
                    color = .color(token.attribute("val") orelse "")
                }
                elif token.isElement("sysClr")
                {
                    color = String.from(token.attribute("lastClr") orelse "")
                }
                else
                {
                    color = String.from(token.attribute("val") orelse "")
                }

                if not Package.isRgbHex(color) do
                    return ""
                if not inColor do
                    break
            }
            elif inColor and token.kind == .Start and
                 (token.isElement("tint") or token.isElement("shade"))
            {
                let amount = catch StrConv.toU32(token.attribute("val") orelse "") orelse Swag.U32.Max
                if amount > 100_000 do
                    return ""
                if amount == 100_000 do
                    continue

                let number = catch StrConv.toU32(Format.toString("0x%", color)) orelse 0
                let sourceColor = Color.fromArgb(0xFF000000 | number)
                let hsl    = sourceColor.toHsl()
                let value  = cast(f32, amount) / 100_000
                let light  = token.isElement("tint") ? hsl.l + (1 - hsl.l) * value : hsl.l * value
                var adjusted: Color
                if hsl.s == 0
                {
                    let gray = cast(u32, Math.round(light * 255))
                    adjusted = Color.fromArgb(0xFF000000 | (gray << 16) | (gray << 8) | gray)
                }
                else do
                    adjusted = Color.fromHsl(hsl.h, hsl.s, light)
                color = Format.toString("%{X02}%{X02}%{X02}", adjusted.r, adjusted.g, adjusted.b)
            }
            elif token.kind == .End and
                 (token.isElement("srgbClr") or token.isElement("schemeClr") or token.isElement("sysClr")) do
                break
        }

        if scan.damaged do
            return ""
        return color
    }

    mtd read(source: string)
    {
        .office.read(source)
        var scan = Package.Scanner.create(source)
        var token:     Package.Token
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
                if token.isElement("titleStyle") or
                   token.isElement("bodyStyle") or
                   token.isElement("otherStyle") do
                    textStyle = ""
            }
        }
    }
}
