#global internal
#global namespace Viewers.Xlsx

using Core, Pixel

private struct FillStyle
{
    color:   u32 = 0xFF000000
    solid:   bool
    limited: bool
}

private struct BorderStyle
{
    edges:   [4] CellEdge
    limited: bool
}

private struct StyleReference
{
    font:           u32  = Swag.U32.Max
    fill:           u32  = Swag.U32.Max
    border:         u32  = Swag.U32.Max
    parent:         u32
    limited:        bool
    applyFont:      bool = true
    applyFill:      bool = true
    applyBorder:    bool = true
    applyAlignment: bool = true
    alignment:      CellAlignment
}

private func styleEnabled(value: string?)->bool => value != "0" and value != "false"

private func styleIndex(token: const *Package.Token, name: string)->u32
{
    if let value = token.attribute(name) do
        return catch StrConv.toU32(value) orelse Swag.U32.Max
    return Swag.U32.Max
}

// Flattens direct and base XFs once; painting never follows a style inheritance chain.
struct CellStyles
{
    normalFont: CellFont
    fonts:      Array'CellFont
    fills:      Array'FillStyle
    borders:    Array'BorderStyle
    styles:     Array'CellLook
}

impl CellStyles
{
    func parse(source: string, theme: const *Package.OfficeTheme)->CellStyles fail
    {
        var result:    #returntype
        let colors            = try CellColors.parse(source, theme)
        var scan              = Package.Scanner.create(source)
        var token:     Package.Token
        var normalIndex       = 0'u32
        var section:   string = ""
        var font:      CellFont
        var fill:      FillStyle
        var border:    BorderStyle
        var reference: StyleReference
        var bases:     Array'StyleReference
        var cells:     Array'StyleReference
        var side              = -1's32
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("fonts")
                {
                    section = "fonts"
                }
                elif token.isElement("fills")
                {
                    section = "fills"
                }
                elif token.isElement("borders")
                {
                    section = "borders"
                }
                elif token.isElement("cellStyleXfs")
                {
                    section = "bases"
                }
                elif token.isElement("cellXfs")
                {
                    section = "cells"
                }
                elif token.isElement("cellStyle") and token.attribute("builtinId") == "0"
                {
                    normalIndex = catch StrConv.toU32(token.attribute("xfId") orelse "0") orelse 0
                }
                elif section == "fonts"
                {
                    if token.isElement("font")
                    {
                        font = {}
                    }
                    elif token.isElement("b")
                    {
                        font.bold = styleEnabled(token.attribute("val"))
                    }
                    elif token.isElement("i")
                    {
                        font.italic = styleEnabled(token.attribute("val"))
                    }
                    elif token.isElement("strike")
                    {
                        font.strike = styleEnabled(token.attribute("val"))
                    }
                    elif token.isElement("u")
                    {
                        let value = token.attribute("val") orelse "single"
                        font.underline = value != "none"
                        font.limited   = font.limited or (value != "none" and value != "single")
                    }
                    elif token.isElement("sz")
                    {
                        let size = catch StrConv.toF64(token.attribute("val") orelse "11") orelse 0
                        if Math.isFinite(size) and size >= 1 and size <= 409 do
                            font.size = cast(f32, size)
                        else do
                            font.limited = true
                    }
                    elif token.isElement("color")
                    {
                        let color = colors.color(&token)
                        font.color   = color.argb
                        font.limited = font.limited or not color.valid
                    }
                    elif token.isElement("name")
                    {
                        let name = String.from(token.attribute("val") orelse "").toLower()
                        font.mono = name == "courier new" or
                                    name == "courier" or
                                    name == "consolas" or
                                    name == "cascadia mono" or
                                    name == "cascadia code" or
                                    name == "monospace"
                    }
                    elif (token.isElement("outline") or token.isElement("shadow")) and styleEnabled(token.attribute("val"))
                    {
                        font.limited = true
                    }
                    elif token.isElement("vertAlign") and (token.attribute("val") orelse "baseline") != "baseline"
                    {
                        font.limited = true
                    }
                }
                elif section == "fills"
                {
                    if token.isElement("fill")
                    {
                        fill = {}
                    }
                    elif token.isElement("patternFill")
                    {
                        let pattern = token.attribute("patternType") orelse "none"
                        fill.solid   = pattern == "solid"
                        fill.limited = pattern != "none" and pattern != "solid"
                    }
                    elif token.isElement("fgColor")
                    {
                        let color = colors.color(&token)
                        fill.color   = color.argb
                        fill.limited = fill.limited or not color.valid
                    }
                    elif token.isElement("gradientFill")
                    {
                        fill.limited = true
                    }
                }
                elif section == "borders"
                {
                    if token.isElement("border")
                    {
                        border = {}
                        side   = -1
                    }
                    elif token.isElement("color") and side >= 0
                    {
                        let color = colors.color(&token)
                        border.edges[cast(u32, side)].color = color.argb
                        border.limited = border.limited or not color.valid
                    }
                    else
                    {
                        side = token.isElement("left") ? 0 : token.isElement("right") ? 1 : token.isElement("top") ? 2 : token.isElement("bottom") ? 3 : -1
                        let kind = token.attribute("style") orelse "none"
                        if side >= 0
                        {
                            let edge = &border.edges[cast(u32, side)]
                            edge.color = 0xFF000000
                            switch kind
                            {
                            case "none":
                                edge.width = 0

                            case "hair":
                                edge.width = 0.5

                            case "thin":
                                edge.width = 1

                            case "medium":
                                edge.width = 2

                            case "thick":
                                edge.width = 3

                            case "double":
                                edge.width      = 1
                                edge.doubleLine = true

                            case "dotted":
                                edge.width = 1
                                edge.dash  = .Dot

                            case "dashed":
                                edge.width = 1
                                edge.dash  = .Dash

                            case "mediumDashed":
                                edge.width = 2
                                edge.dash  = .Dash

                            case "dashDot":
                                edge.width = 1
                                edge.dash  = .DashDot

                            case "mediumDashDot":
                                edge.width = 2
                                edge.dash  = .DashDot

                            default:
                                border.limited = true
                            }
                        }
                        elif kind != "none"
                        {
                            border.limited = true
                        }
                    }
                }
                elif section == "bases" or section == "cells"
                {
                    if token.isElement("xf")
                    {
                        reference                = {}
                        reference.font           = styleIndex(&token, "fontId")
                        reference.fill           = styleIndex(&token, "fillId")
                        reference.border         = styleIndex(&token, "borderId")
                        reference.parent         = catch StrConv.toU32(token.attribute("xfId") orelse "0") orelse Swag.U32.Max
                        reference.applyFont      = styleEnabled(token.attribute("applyFont"))
                        reference.applyFill      = styleEnabled(token.attribute("applyFill"))
                        reference.applyBorder    = styleEnabled(token.attribute("applyBorder"))
                        reference.applyAlignment = styleEnabled(token.attribute("applyAlignment"))
                        reference.limited        = (reference.font == Swag.U32.Max and token.attribute("fontId") != null) or
                                                   (reference.fill == Swag.U32.Max and token.attribute("fillId") != null) or
                                                   (reference.border == Swag.U32.Max and token.attribute("borderId") != null) or
                                                   reference.parent == Swag.U32.Max
                    }
                    elif token.isElement("alignment")
                    {
                        reference.alignment.read(&token)
                    }
                }
            }

            if token.kind == .End or token.empty
            {
                if section == "fonts" and token.isElement("font")
                {
                    result.fonts.add(font)
                }
                elif section == "fills" and token.isElement("fill")
                {
                    result.fills.add(fill)
                }
                elif section == "borders" and token.isElement("border")
                {
                    result.borders.add(border)
                }
                elif (section == "bases" or section == "cells") and token.isElement("xf")
                {
                    if section == "bases" do
                        bases.add(reference)
                    else do
                        cells.add(reference)
                }
                elif token.isElement("fonts") or
                     token.isElement("fills") or
                     token.isElement("borders") or
                     token.isElement("cellStyleXfs") or
                     token.isElement("cellXfs")
                {
                    section = ""
                }

                if section == "borders" and
                   (token.isElement("left") or
                    token.isElement("right") or
                    token.isElement("top") or
                    token.isElement("bottom")) do
                    side = -1
            }

            if result.fonts.count > 4096 or
               result.fills.count > 4096 or
               result.borders.count > 4096 or
               bases.count > 65536 or
               cells.count > 65536 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        if scan.damaged do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        var parents: Array'CellLook
        for base in bases do
            parents.add(result.resolve(base, {}))
        if normalIndex < parents.count do
            result.normalFont = parents[normalIndex].font
        elif not result.fonts.isEmpty() do
            result.normalFont = result.fonts[0]
        for cell in cells
        {
            var parent: CellLook
            if cell.parent < parents.count do
                parent = parents[cell.parent]
            elif not parents.isEmpty() do
                parent.limited = true
            result.styles.add(result.resolve(cell, parent))
        }

        return result
    }

    private mtd const resolve(reference: const *StyleReference, parent: CellLook)->CellLook
    {
        var result = parent
        result.limited = result.limited or reference.limited
        if reference.applyFont and reference.font != Swag.U32.Max
        {
            if reference.font < .fonts.count do
                result.font = .fonts[reference.font]
            else do
                result.limited = true
        }

        if reference.applyFill and reference.fill != Swag.U32.Max
        {
            if reference.fill < .fills.count
            {
                let fill = .fills[reference.fill]
                result.fill    = fill.solid ? fill.color : 0
                result.limited = result.limited or fill.limited
            }
            else
            {
                result.limited = true
            }
        }

        if reference.applyBorder and reference.border != Swag.U32.Max
        {
            if reference.border < .borders.count
            {
                result.edges   = .borders[reference.border].edges
                result.limited = result.limited or .borders[reference.border].limited
            }
            else
            {
                result.limited = true
            }
        }

        if reference.applyAlignment do
            result.alignment.apply(&reference.alignment)
        result.limited = result.limited or result.font.limited or result.alignment.limited
        return result
    }

    mtd const look(index: u32)->CellLook
    {
        if index < .styles.count do
            return .styles[index]
        return CellLook{limited: index != 0 or not .styles.isEmpty()}
    }
}
