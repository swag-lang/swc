#global internal
#global namespace Viewers.Pptx

using Core

private const TableRowLimit    = 64_u64
private const TableColumnLimit = 32_u64
private const TableCellLimit   = 2048_u64
private const TableOutputLimit = 32 * 1024 * 1024_u64

// A bounded static DrawingML table rendered as slide-sized HTML.
struct SlideTable
{
    html:      String
    plainText: String
    requiresSimplified: bool
}

impl SlideTable
{
    func parse(source: string, theme: const *SlideTheme, pageWidth: f32)->SlideTable fail
    {
        var result:       #returntype
        var scan                     = Package.Scanner.create(source)
        var token:        Package.Token
        var sawTable                 = false
        var inTable                  = false
        var rowStart                 = Swag.U64.Max
        var rowCount                 = 0_u64
        var rowCells                 = 0_u64
        var rowColumns               = 0_u64
        var cellStart                = Swag.U64.Max
        var cellColumnSpan           = 1_u64
        var cellRowSpan              = 1_u64
        var cellVerticalContinue     = false
        var inferredVerticalContinue = false
        var cellStartColumn          = 0_u64
        var nextColumn               = 0_u64
        var inCellProperties         = false
        var columnWidths: Array!{u64}
        var coveredRows:  Array!{u64}
        for TableColumnLimit
        {
            coveredRows.add(0)
        }

        func cellFill(source: string, theme: const *SlideTheme)->String fail
        {
            var result:    String
            var cellScan     = Package.Scanner.create(source)
            var cellToken: Package.Token
            var inProperties = false
            var inFill       = false
            var inColor      = false
            while cellScan.next(&cellToken)
            {
                if cellToken.kind == .Start
                {
                    if cellToken.isElement("tcPr")
                    {
                        inProperties = not cellToken.empty
                    }
                    else if inProperties and cellToken.isElement("solidFill")
                    {
                        inFill = not cellToken.empty
                    }
                    else if inFill and (cellToken.isElement("srgbClr") or cellToken.isElement("schemeClr"))
                    {
                        let value = cellToken.attribute("val") orelse ""
                        let color = cellToken.isElement("schemeClr") ? theme.color(value) : String.from(value)
                        if Package.isRgbHex(color)
                        {
                            result = color
                        }

                        inColor = not cellToken.empty
                    }
                    else if inColor and (cellToken.isElement("tint") or cellToken.isElement("shade"))
                    {
                        let amount = catch StrConv.toU32(cellToken.attribute("val") orelse "") orelse Swag.U32.Max
                        if amount <= 100_000
                        {
                            result = theme.transformColor(result, amount, cellToken.isElement("tint"))
                        }
                    }
                }
                else if cellToken.kind == .End
                {
                    if cellToken.isElement("tcPr")
                    {
                        inProperties = false
                    }
                    else if cellToken.isElement("solidFill")
                    {
                        inFill = false
                    }
                    else if cellToken.isElement("srgbClr") or cellToken.isElement("schemeClr")
                    {
                        inColor = false
                    }
                }
            }

            if cellScan.damaged
            {
                fail Errors.InvalidFormatError{texts().err_Invalid}
            }

            return result
        }

        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("tbl")
                {
                    sawTable    = true
                    inTable     = not token.empty
                    result.html = "<table style=\"width:100%;height:100%;border-collapse:collapse;table-layout:fixed\"><tbody>"
                }
                else if inTable and token.isElement("tr")
                {
                    if rowCount == TableRowLimit
                    {
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    }

                    rowStart   = scan.offset
                    rowCells   = 0
                    rowColumns = 0
                    nextColumn = 0
                    if rowCount
                    {
                        result.plainText += "\n"
                    }

                    result.html += "<tr>"
                }
                else if inTable and token.isElement("gridCol")
                {
                    if columnWidths.count == TableColumnLimit
                    {
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    }

                    let width = catch StrConv.toU64(token.attribute("w") orelse "") orelse 0
                    if width and width <= 100_000_000
                    {
                        columnWidths.add(width)
                    }
                    else
                    {
                        result.requiresSimplified = true
                    }
                }
                else if inTable and token.isElement("tc")
                {
                    rowCells += 1
                    if rowCells > TableColumnLimit or rowCount * TableColumnLimit + rowCells > TableCellLimit
                    {
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    }

                    cellColumnSpan           = 1
                    cellRowSpan              = 1
                    cellVerticalContinue     = false
                    inferredVerticalContinue = false
                    cellStartColumn          = nextColumn
                    if rowCells > 1
                    {
                        result.plainText += "\t"
                    }

                    if token.empty
                    {
                        nextColumn += 1
                        if nextColumn > rowColumns
                        {
                            rowColumns = nextColumn
                        }

                        result.html += "<td style=\"border:1px solid #808080;padding:0.25em;overflow-wrap:anywhere;"
                        result.html += "\"></td>"
                    }
                    else
                    {
                        cellStart = scan.offset
                    }
                }
                else if inTable and token.isElement("tcPr")
                {
                    inCellProperties = not token.empty
                    let gridSpan        = catch StrConv.toU64(token.attribute("gridSpan") orelse "") orelse 1
                    let rowSpan         = catch StrConv.toU64(token.attribute("rowSpan") orelse "") orelse 1
                    let verticalMerge   = token.attribute("vMerge")
                    let horizontalMerge = token.attribute("hMerge")
                    if gridSpan > 1 and gridSpan <= TableColumnLimit
                    {
                        cellColumnSpan = gridSpan
                    }
                    else if gridSpan != 1
                    {
                        result.requiresSimplified = true
                    }

                    if rowSpan > 1 and rowSpan <= TableRowLimit
                    {
                        cellRowSpan = rowSpan
                    }
                    else if rowSpan != 1
                    {
                        result.requiresSimplified = true
                    }

                    if verticalMerge != null
                    {
                        let value = verticalMerge orelse ""
                        if value != "0" and value != "false" and value != "off"
                        {
                            cellVerticalContinue = true
                        }
                    }

                    if horizontalMerge != null
                    {
                        let value = horizontalMerge orelse ""
                        if value != "0" and value != "false" and value != "off"
                        {
                            result.requiresSimplified = true
                        }
                    }
                }
                else if inTable and inCellProperties and token.isElement("gridSpan")
                {
                    let span = catch StrConv.toU64(token.attribute("val") orelse "") orelse 0
                    if span == 0 or span > TableColumnLimit
                    {
                        result.requiresSimplified = true
                    }
                    else
                    {
                        cellColumnSpan = span
                    }
                }
                else if inTable and inCellProperties and token.isElement("rowSpan")
                {
                    let span = catch StrConv.toU64(token.attribute("val") orelse "") orelse 0
                    if span < 2 or span > TableRowLimit
                    {
                        result.requiresSimplified = true
                    }
                    else
                    {
                        cellRowSpan = span
                    }
                }
                else if inTable and inCellProperties and token.isElement("vMerge")
                {
                    let value = token.attribute("val") orelse "1"
                    if value == "1" or value == "true"
                    {
                        cellVerticalContinue = true
                    }
                    else if value != "0" and value != "false" and value != "off"
                    {
                        result.requiresSimplified = true
                    }
                }
                else if inTable and
                        token.isElement("hMerge")
                {
                    result.requiresSimplified = true
                }
            }
            else if token.kind == .End
            {
                if token.isElement("tcPr")
                {
                    inCellProperties = false
                }

                if token.isElement("tc") and cellStart != Swag.U64.Max
                {
                    let cellSource = source[cellStart until scan.offset]
                    var images: Package.ImageCatalog
                    let cellText   = try SlideText.parse(cellSource, &images, theme, pageWidth)
                    result.requiresSimplified = result.requiresSimplified or cellText.requiresSimplified
                    var cellPlainText = cellText.plainText
                    cellPlainText.trim()
                    let fill = try cellFill(cellSource, theme)
                    if not cellVerticalContinue and
                       nextColumn < TableColumnLimit and
                       coveredRows[nextColumn] and
                       cellPlainText.isEmpty()
                    {
                        inferredVerticalContinue = true
                        cellVerticalContinue     = true
                    }

                    if cellVerticalContinue
                    {
                        while nextColumn < TableColumnLimit and coveredRows[nextColumn] == 0
                        {
                            nextColumn += 1
                        }

                        if nextColumn == TableColumnLimit
                        {
                            result.requiresSimplified = true
                            cellVerticalContinue      = false
                            nextColumn = cellStartColumn
                        }
                    }

                    if not cellVerticalContinue
                    {
                        while nextColumn < TableColumnLimit and coveredRows[nextColumn]
                        {
                            nextColumn += 1
                        }
                    }

                    cellStartColumn = nextColumn
                    nextColumn      = cellStartColumn + cellColumnSpan
                    if nextColumn > TableColumnLimit
                    {
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    }

                    if nextColumn > rowColumns
                    {
                        rowColumns = nextColumn
                    }

                    if cellVerticalContinue
                    {
                        if not cellPlainText.isEmpty()
                        {
                            result.requiresSimplified = true
                        }

                        if not inferredVerticalContinue and coveredRows[cellStartColumn] == 0
                        {
                            result.requiresSimplified = true
                            result.html += "<td style=\"border:1px solid #808080;padding:0.25em;overflow-wrap:anywhere;\">"
                            result.html += cellText.html.toString()
                            result.html += "</td>"
                        }
                    }
                    else
                    {
                        var coverageColumn = cellStartColumn
                        while coverageColumn < nextColumn
                        {
                            if coveredRows[coverageColumn]
                            {
                                result.requiresSimplified = true
                            }

                            if cellRowSpan > 1
                            {
                                coveredRows[coverageColumn] = cellRowSpan
                            }

                            coverageColumn += 1
                        }

                        result.html += "<td"
                        if cellColumnSpan > 1
                        {
                            result.html += Format.toString(" colspan=\"%\"", cellColumnSpan)
                        }

                        if cellRowSpan > 1
                        {
                            result.html += Format.toString(" rowspan=\"%\"", cellRowSpan)
                        }

                        result.html += " style=\"border:1px solid #808080;padding:0.25em;overflow-wrap:anywhere;"
                        if not fill.isEmpty()
                        {
                            result.html += Format.toString("background-color:#%;", fill)
                        }

                        result.html += "\">"
                        result.html += cellText.html.toString()
                        result.html += "</td>"
                    }

                    result.plainText += cellPlainText
                    let additionalTabCount = cellColumnSpan - 1
                    for additionalTabCount
                    {
                        result.plainText += "\t"
                    }

                    cellStart = Swag.U64.Max
                }
                else if token.isElement("tr") and rowStart != Swag.U64.Max
                {
                    result.html += "</tr>"
                    if columnWidths.count and rowColumns != columnWidths.count
                    {
                        result.requiresSimplified = true
                    }

                    var coveredRowsIndex = 0_u64
                    while coveredRowsIndex < TableColumnLimit
                    {
                        if coveredRows[coveredRowsIndex]
                        {
                            coveredRows[coveredRowsIndex] -= 1
                        }

                        coveredRowsIndex += 1
                    }

                    rowStart = Swag.U64.Max
                    rowCount += 1
                }
                else if token.isElement("tbl")
                {
                    inTable     = false
                    result.html += "</tbody></table>"
                }
            }

            if scan.offset > TableOutputLimit or result.html.count > TableOutputLimit
            {
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            }
        }

        if scan.damaged or cellStart != Swag.U64.Max or rowStart != Swag.U64.Max
        {
            fail Errors.InvalidFormatError{texts().err_Invalid}
        }

        var coveredRowsIndex = 0_u64
        while coveredRowsIndex < TableColumnLimit
        {
            if coveredRows[coveredRowsIndex]
            {
                result.requiresSimplified = true
            }

            coveredRowsIndex += 1
        }

        if not sawTable
        {
            return {}
        }

        if rowCount == 0
        {
            return {}
        }

        return result
    }
}
