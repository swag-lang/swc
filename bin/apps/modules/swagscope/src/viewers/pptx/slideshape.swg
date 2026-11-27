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
    rotation:         f32
    flipHorizontal:   bool
    flipVertical:     bool
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
    ellipse:          bool
    centered:         bool
    bodyProperties:   bool
    insetMask:        u8
    inset:            Math.Vector4 = {9.6, 4.8, 9.6, 4.8}
    picture:          bool
    connector:        bool
    connectorLine:    bool
    unsupported:      bool
    hidden:           bool
    omittedImages:    u64
}

private func emuValue(token: const *Package.Token, name: string)->f32
{
    let value = catch StrConv.toS64(token.attribute(name) orelse "") orelse 0

    // Keep hostile coordinates from creating enormous layout or paint regions.
    return cast(f32, Math.clamp(value, -100_000_000_s64, 100_000_000_s64)) / 9525
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
        var inFillColor  = false
        var inText       = false
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("pic")
                {
                    result.picture = true
                }

                if token.isElement("cxnSp")
                {
                    result.connector = true
                }

                if token.isElement("ph")
                {
                    result.placeholder      = true
                    result.placeholderKind  = token.attribute("type") orelse "obj"
                    result.placeholderIndex = catch StrConv.toU32(token.attribute("idx") orelse "0") orelse 0
                }
                else if token.isElement("cNvPr")
                {
                    result.hidden = token.attribute("hidden") == "1" or token.attribute("hidden") == "true"
                }
                else if token.isElement("spPr")
                {
                    inProperties = not token.empty
                }
                else if token.isElement("xfrm")
                {
                    inTransform = not token.empty
                    let rotation      = token.attribute("rot") orelse "0"
                    let rotationUnits = catch StrConv.toS64(rotation) orelse Swag.S64.Max
                    if rotationUnits < -21_600_000 or rotationUnits > 21_600_000
                    {
                        result.unsupported = true
                    }
                    else
                    {
                        result.rotation = cast(f32, rotationUnits) / 60_000
                    }

                    result.flipHorizontal = token.attribute("flipH") == "1" or token.attribute("flipH") == "true"
                    result.flipVertical   = token.attribute("flipV") == "1" or token.attribute("flipV") == "true"
                }
                else if inTransform and token.isElement("off")
                {
                    result.bounds.x  = emuValue(&token, "x")
                    result.bounds.y  = emuValue(&token, "y")
                    result.hasOffset = true
                }
                else if inTransform and token.isElement("ext")
                {
                    result.bounds.width  = emuValue(&token, "cx")
                    result.bounds.height = emuValue(&token, "cy")
                    result.hasExtent     = result.bounds.width > 0 and result.bounds.height > 0
                }
                else if token.isElement("txBody")
                {
                    inText = not token.empty
                }
                else if inText and token.isElement("bodyPr")
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
                else if inText and token.isElement("defRPr") and not result.fontSize
                {
                    result.fontSize = catch StrConv.toU32(token.attribute("sz") orelse "") orelse 0
                }
                else if inProperties and token.isElement("prstGeom")
                {
                    let kind = token.attribute("prst") orelse "rect"
                    result.round         = kind == "roundRect"
                    result.ellipse       = kind == "ellipse"
                    result.connectorLine = result.connector and kind == "line"
                    if kind != "rect" and
                       kind != "roundRect" and
                       kind != "ellipse" and
                       not result.connectorLine
                    {
                        result.unsupported = true
                    }
                }
                else if inProperties and token.isElement("custGeom")
                {
                    result.unsupported = true
                }
                else if inProperties and token.isElement("ln")
                {
                    inLine = not token.empty
                    result.lineWidth = Math.max(emuValue(&token, "w"), 1)
                }
                else if inLine and
                        (token.isElement("headEnd") or token.isElement("tailEnd")) and
                        token.attribute("type") != null and
                        token.attribute("type") != "none"
                {
                    result.unsupported = true
                }
                else if inLine and token.isElement("prstDash") and token.attribute("val") != "solid"
                {
                    result.unsupported = true
                }
                else if inProperties and token.isElement("noFill")
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
                else if inProperties and token.isElement("solidFill")
                {
                    inFill = not token.empty
                    if not inLine
                    {
                        result.hasFill = true
                    }
                }
                else if inFill and (token.isElement("srgbClr") or token.isElement("schemeClr"))
                {
                    let value = token.attribute("val") orelse ""
                    let color = token.isElement("schemeClr") ? theme.color(value) : String.from(value)
                    if Package.isRgbHex(color)
                    {
                        if inLine
                        {
                            result.line = color
                        }
                        else
                        {
                            result.fill = color
                        }
                    }

                    inFillColor = not token.empty
                }
                else if inFillColor and (token.isElement("tint") or token.isElement("shade"))
                {
                    let amount = catch StrConv.toU32(token.attribute("val") orelse "") orelse Swag.U32.Max
                    if amount <= 100_000 and inLine
                    {
                        result.line = theme.transformColor(result.line, amount, token.isElement("tint"))
                    }
                    else if amount <= 100_000
                    {
                        result.fill = theme.transformColor(result.fill, amount, token.isElement("tint"))
                    }
                }
            }
            else if token.kind == .End
            {
                if token.isElement("xfrm")
                {
                    inTransform = false
                }
                else if token.isElement("spPr")
                {
                    inProperties = false
                }
                else if token.isElement("txBody")
                {
                    inText = false
                }
                else if token.isElement("solidFill")
                {
                    inFill = false
                }
                else if token.isElement("srgbClr") or token.isElement("schemeClr")
                {
                    inFillColor = false
                }
                else if token.isElement("ln")
                {
                    inLine = false
                }
            }
        }

        if scan.damaged
        {
            fail Errors.InvalidFormatError{texts().err_Invalid}
        }

        if result.connector
        {
            let horizontal      = result.bounds.width > 0 and result.bounds.height == 0
            let vertical        = result.bounds.width == 0 and result.bounds.height > 0
            let diagonal        = result.bounds.width > 0 and result.bounds.height > 0
            let simpleTransform = not result.rotation and not result.flipHorizontal and not result.flipVertical
            result.positioned  = result.hasOffset and simpleTransform and (horizontal or vertical or diagonal)
            result.unsupported = result.unsupported or
                                 not result.connectorLine or
                                 not result.positioned or
                                 result.line.isEmpty()
        }
        else
        {
            result.positioned = result.hasOffset and result.hasExtent
        }

        if images
        {
            let text = try SlideText.parse(source, images, theme, pageWidth)
            result.html          = text.html
            result.plainText     = text.plainText
            result.omittedImages = text.omittedImages
            result.unsupported   = result.unsupported or text.requiresSimplified
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
        if not .fontSize
        {
            .fontSize = parent.fontSize
        }

        if not .bodyProperties
        {
            .centered       = parent.centered
            .bodyProperties = parent.bodyProperties
        }

        if not (.insetMask & 1)
        {
            .inset.x = parent.inset.x
        }

        if not (.insetMask & 2)
        {
            .inset.y = parent.inset.y
        }

        if not (.insetMask & 4)
        {
            .inset.z = parent.inset.z
        }

        if not (.insetMask & 8)
        {
            .inset.w = parent.inset.w
        }

        .insetMask |= parent.insetMask
        if .textColor.isEmpty()
        {
            .textColor = parent.textColor
        }

        if not .hasFill
        {
            .fill    = parent.fill
            .hasFill = parent.hasFill
        }
    }

    mtd const isTitle()->bool => .placeholderKind == "title" or .placeholderKind == "ctrTitle"

    mtd const placeholderIn(shapes: const [..] SlideShape)->const *SlideShape?
    {
        if not .placeholder
        {
            return null
        }

        for shape in shapes where shape.placeholder and shape.placeholderIndex == .placeholderIndex
        {
            return shape
        }

        for shape in shapes where shape.placeholder and
                                  ((.isTitle() and shape.isTitle()) or shape.placeholderKind == .placeholderKind)
        {
            return shape
        }

        return null
    }
}
