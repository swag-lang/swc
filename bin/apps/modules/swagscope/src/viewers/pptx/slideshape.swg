#global internal
#global namespace Viewers.Pptx

using Core

// One text or picture object, retaining its authored slide-space geometry and placeholder identity.
struct SlideShape
{
    html:             String
    plainText:        String
    bounds:           Math.Rectangle
    positioned:       bool
    hasOffset:        bool
    hasExtent:        bool
    placeholder:      bool
    placeholderKind:  String
    placeholderIndex: u32
    fontSize:         u32
    textColor:        String
    fill:             String
    hasFill:          bool
    line:             String
    lineWidth:        f32
    round:            bool
    centered:         bool
    bodyProperties:   bool
    insetMask:        u8
    inset:            Math.Vector4 = {9.6, 4.8, 9.6, 4.8}
    picture:          bool
    unsupported:      bool
    hidden:           bool
    omittedImages:    u64
}

private func emuValue(token: const *Package.Token, name: string)->f32
{
    let value = catch StrConv.toS64(token.attribute(name) orelse "") orelse 0

    // Keep hostile coordinates from creating enormous layout or paint regions.
    return cast(f32, Math.clamp(value, -100_000_000's64, 100_000_000's64)) / 9525
}

impl SlideShape
{
    func parse(source: string, theme: const *SlideTheme, images: *Package.ImageCatalog? = null, pageWidth = 960.0)->SlideShape fail
    {
        var result: #returntype
        var scan         = Package.Scanner.create(source)
        var token:  Package.Token
        var inTransform  = false
        var inProperties = false
        var inLine       = false
        var inFill       = false
        var inText       = false
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("pic") do
                    result.picture = true
                if token.isElement("ph")
                {
                    result.placeholder      = true
                    result.placeholderKind  = token.attribute("type") orelse "obj"
                    result.placeholderIndex = catch StrConv.toU32(token.attribute("idx") orelse "0") orelse 0
                }
                elif token.isElement("cNvPr")
                {
                    result.hidden = token.attribute("hidden") == "1" or token.attribute("hidden") == "true"
                }
                elif token.isElement("spPr")
                {
                    inProperties = not token.empty
                }
                elif token.isElement("xfrm")
                {
                    inTransform = not token.empty
                    let rotation = token.attribute("rot") orelse "0"
                    if rotation != "0" or
                       token.attribute("flipH") == "1" or
                       token.attribute("flipH") == "true" or
                       token.attribute("flipV") == "1" or
                       token.attribute("flipV") == "true" do
                        result.unsupported = true
                }
                elif inTransform and token.isElement("off")
                {
                    result.bounds.x  = emuValue(&token, "x")
                    result.bounds.y  = emuValue(&token, "y")
                    result.hasOffset = true
                }
                elif inTransform and token.isElement("ext")
                {
                    result.bounds.width  = emuValue(&token, "cx")
                    result.bounds.height = emuValue(&token, "cy")
                    result.hasExtent     = result.bounds.width > 0 and result.bounds.height > 0
                }
                elif token.isElement("txBody")
                {
                    inText = not token.empty
                }
                elif inText and token.isElement("bodyPr")
                {
                    result.bodyProperties = token.attribute("anchor") != null
                    result.centered       = token.attribute("anchor") == "ctr"
                    if token.attribute("lIns")
                    {
                        result.inset.x   = Math.max(emuValue(&token, "lIns"), 0)
                        result.insetMask |= 1
                    }

                    if token.attribute("tIns")
                    {
                        result.inset.y   = Math.max(emuValue(&token, "tIns"), 0)
                        result.insetMask |= 2
                    }

                    if token.attribute("rIns")
                    {
                        result.inset.z   = Math.max(emuValue(&token, "rIns"), 0)
                        result.insetMask |= 4
                    }

                    if token.attribute("bIns")
                    {
                        result.inset.w   = Math.max(emuValue(&token, "bIns"), 0)
                        result.insetMask |= 8
                    }
                }
                elif inText and token.isElement("defRPr") and not result.fontSize
                {
                    result.fontSize = catch StrConv.toU32(token.attribute("sz") orelse "") orelse 0
                }
                elif inProperties and token.isElement("prstGeom")
                {
                    let kind = token.attribute("prst") orelse "rect"
                    result.round = kind == "roundRect"
                    if kind != "rect" and kind != "roundRect" do
                        result.unsupported = true
                }
                elif inProperties and token.isElement("custGeom")
                {
                    result.unsupported = true
                }
                elif inProperties and token.isElement("ln")
                {
                    inLine = not token.empty
                    result.lineWidth = Math.max(emuValue(&token, "w"), 1)
                }
                elif inProperties and token.isElement("noFill")
                {
                    if inLine
                    {
                        result.line.clear()
                    }
                    else
                    {
                        result.fill.clear()
                        result.hasFill = true
                    }
                }
                elif inProperties and token.isElement("solidFill")
                {
                    inFill = not token.empty
                    if not inLine do
                        result.hasFill = true
                }
                elif inFill and (token.isElement("srgbClr") or token.isElement("schemeClr"))
                {
                    let value = token.attribute("val") orelse ""
                    let color = token.isElement("schemeClr") ? theme.color(value) : String.from(value)
                    if Package.isRgbHex(color)
                    {
                        if inLine do
                            result.line = color
                        else do
                            result.fill = color
                    }
                }
            }
            elif token.kind == .End
            {
                if token.isElement("xfrm") do
                    inTransform = false
                elif token.isElement("spPr") do
                    inProperties = false
                elif token.isElement("txBody") do
                    inText = false
                elif token.isElement("solidFill") do
                    inFill = false
                elif token.isElement("ln") do
                    inLine = false
            }
        }

        if scan.damaged do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        result.positioned = result.hasOffset and result.hasExtent
        if images
        {
            let text = try SlideText.parse(source, images, theme, pageWidth)
            result.html          = text.html
            result.plainText     = text.plainText
            result.omittedImages = text.omittedImages
        }

        return result
    }

    mtd inherit(parent: const *SlideShape)
    {
        if not .hasOffset and parent.hasOffset
        {
            .bounds.x  = parent.bounds.x
            .bounds.y  = parent.bounds.y
            .hasOffset = true
        }

        if not .hasExtent and parent.hasExtent
        {
            .bounds.width  = parent.bounds.width
            .bounds.height = parent.bounds.height
            .hasExtent     = true
        }

        .positioned = .hasOffset and .hasExtent
        if not .fontSize do
            .fontSize = parent.fontSize
        if not .bodyProperties
        {
            .centered       = parent.centered
            .bodyProperties = parent.bodyProperties
        }

        if not (.insetMask & 1) do
            .inset.x = parent.inset.x
        if not (.insetMask & 2) do
            .inset.y = parent.inset.y
        if not (.insetMask & 4) do
            .inset.z = parent.inset.z
        if not (.insetMask & 8) do
            .inset.w = parent.inset.w
        .insetMask |= parent.insetMask
        if .textColor.isEmpty() do
            .textColor = parent.textColor
        if not .hasFill
        {
            .fill    = parent.fill
            .hasFill = parent.hasFill
        }
    }

    mtd const isTitle()->bool => .placeholderKind == "title" or .placeholderKind == "ctrTitle"

    mtd const placeholderIn(shapes: const [..] SlideShape)->const *SlideShape?
    {
        if not .placeholder do
            return null
        for shape in shapes where shape.placeholder and shape.placeholderIndex == .placeholderIndex do
            return shape
        for shape in shapes where shape.placeholder and
                                  ((.isTitle() and shape.isTitle()) or shape.placeholderKind == .placeholderKind) do
            return shape
        return null
    }
}
