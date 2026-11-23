#global internal
#global namespace Viewers.Pptx

using Core

private const TableRowLimit    = 64'u64
private const TableColumnLimit = 32'u64
private const TableCellLimit   = 2048'u64
private const TableOutputLimit = 32 * 1024 * 1024'u64

// A bounded static DrawingML table rendered as slide-sized HTML.
struct SlideTable
{
    html:                String
    plainText:           String
    requiresSimplified:  bool
}

impl SlideTable
{
    func parse(source: string, theme: const *SlideTheme, pageWidth: f32)->SlideTable fail
    {
        var result: #returntype
        var scan = Package.Scanner.create(source)
        var token: Package.Token
        var sawTable = false
        var inTable = false
        var rowStart = Swag.U64.Max
        var rowCount = 0'u64
        var rowCells = 0'u64
        var cellStart = Swag.U64.Max
        var columnWidths: Array'u64

        func cellFill(source: string, theme: const *SlideTheme)->String fail
        {
            var result: String
            var cellScan = Package.Scanner.create(source)
            var cellToken: Package.Token
            var inProperties = false
            var inFill = false
            var inColor = false
            while cellScan.next(&cellToken)
            {
                if cellToken.kind == .Start
                {
                    if cellToken.isElement("tcPr")
                    {
                        inProperties = not cellToken.empty
                    }
                    elif inProperties and cellToken.isElement("solidFill")
                    {
                        inFill = not cellToken.empty
                    }
                    elif inFill and (cellToken.isElement("srgbClr") or cellToken.isElement("schemeClr"))
                    {
                        let value = cellToken.attribute("val") orelse ""
                        let color = cellToken.isElement("schemeClr") ? theme.color(value) : String.from(value)
                        if Package.isRgbHex(color) do
                            result = color
                        inColor = not cellToken.empty
                    }
                    elif inColor and (cellToken.isElement("tint") or cellToken.isElement("shade"))
                    {
                        let amount = catch StrConv.toU32(cellToken.attribute("val") orelse "") orelse Swag.U32.Max
                        if amount <= 100_000 do
                            result = theme.transformColor(result, amount, cellToken.isElement("tint"))
                    }
                }
                elif cellToken.kind == .End
                {
                    if cellToken.isElement("tcPr") do
                        inProperties = false
                    elif cellToken.isElement("solidFill") do
                        inFill = false
                    elif cellToken.isElement("srgbClr") or cellToken.isElement("schemeClr") do
                        inColor = false
                }
            }

            if cellScan.damaged do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            return result
        }

        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("tbl")
                {
                    sawTable = true
                    inTable = not token.empty
                    result.html = "<table style=\"width:100%;height:100%;border-collapse:collapse;table-layout:fixed\"><tbody>"
                }
                elif inTable and token.isElement("tr")
                {
                    if rowCount == TableRowLimit do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    rowStart = scan.offset
                    rowCells = 0
                    if rowCount do
                        result.plainText += "\n"
                    result.html += "<tr>"
                }
                elif inTable and token.isElement("gridCol")
                {
                    if columnWidths.count == TableColumnLimit do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    let width = catch StrConv.toU64(token.attribute("w") orelse "") orelse 0
                    if width and width <= 100_000_000
                    {
                        columnWidths.add(width)
                    }
                    else do
                        result.requiresSimplified = true
                }
                elif inTable and token.isElement("tc")
                {
                    rowCells += 1
                    if rowCells > TableColumnLimit or rowCount * TableColumnLimit + rowCells > TableCellLimit do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    if rowCells > 1 do
                        result.plainText += "\t"
                    if token.empty
                    {
                        result.html += "<td style=\"border:1px solid #808080;padding:0.25em;overflow-wrap:anywhere;"
                        result.html += "\"></td>"
                    }
                    else do
                        cellStart = scan.offset
                }
                elif inTable and
                     (token.isElement("gridSpan") or token.isElement("rowSpan") or token.isElement("hMerge") or token.isElement("vMerge"))
                {
                    result.requiresSimplified = true
                }
            }
            elif token.kind == .End
            {
                if token.isElement("tc") and cellStart != Swag.U64.Max
                {
                    let cellSource = source[cellStart until scan.offset]
                    var images: Package.ImageCatalog
                    let cellText = try SlideText.parse(cellSource, &images, theme, pageWidth)
                    var cellPlainText = cellText.plainText
                    cellPlainText.trim()
                    let fill = try cellFill(cellSource, theme)
                    result.html += "<td style=\"border:1px solid #808080;padding:0.25em;overflow-wrap:anywhere;"
                    if not fill.isEmpty() do
                        result.html += Format.toString("background-color:#%;", fill)
                    result.html += "\">"
                    result.html += cellText.html.toString()
                    result.html += "</td>"
                    result.plainText += cellPlainText
                    cellStart = Swag.U64.Max
                }
                elif token.isElement("tr") and rowStart != Swag.U64.Max
                {
                    result.html += "</tr>"
                    if columnWidths.count and rowCells != columnWidths.count do
                        result.requiresSimplified = true
                    rowStart = Swag.U64.Max
                    rowCount += 1
                }
                elif token.isElement("tbl")
                {
                    inTable = false
                    result.html += "</tbody></table>"
                }
            }

            if scan.offset > TableOutputLimit or result.html.count > TableOutputLimit do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        if scan.damaged or cellStart != Swag.U64.Max or rowStart != Swag.U64.Max do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        if not sawTable do
            return {}
        if rowCount == 0 do
            return {}
        return result
    }
}
