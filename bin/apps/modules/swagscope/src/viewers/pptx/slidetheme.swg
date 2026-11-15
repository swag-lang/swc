#global internal
#global namespace Viewers.Pptx

using Core

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
