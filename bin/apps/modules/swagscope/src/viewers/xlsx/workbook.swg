#global internal
#global namespace Viewers.Xlsx

using Core

private struct Sheet
{
    name: String
    path: String
}

// The readable cells of a spreadsheet, in workbook sheet order.
struct Workbook
{
    html:           String
    sheets:         u64
    cells:          u64
    omittedFormats: u64
}

private func readSheets(source: string, relations: const [..] Package.Relationship)->Array'Sheet fail
{
    var scan = Package.Scanner.create(source)
    var token:  Package.Token
    var result: #returntype
    while scan.next(&token)
    {
        if token.kind != .Start or not token.isElement("sheet") do
            continue
        let name = token.attribute("name")
        let id   = token.attribute("id")
        if not name or not id do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        var found = false
        for relation in relations where relation.id == id and Utf8.endsWith(relation.kind, "/worksheet")
        {
            result.add(Sheet{name, relation.path})
            found = true
            break
        }

        if not found do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        if result.count > 200 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
    }

    if scan.damaged or result.isEmpty() do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return result
}

private func readSharedStrings(source: string)->Array'String fail
{
    var scan = Package.Scanner.create(source)
    var token: Package.Token
    var result: #returntype
    var value: String
    var inItem = false
    var inText = false
    while scan.next(&token)
    {
        if token.kind == .Start
        {
            if token.isElement("si")
            {
                value.clear()
                inItem = true
            }
            elif inItem and token.isElement("t") do
                inText = true
        }
        elif token.kind == .End
        {
            if token.isElement("si")
            {
                result.add(value)
                inItem = false
            }
            elif token.isElement("t") do
                inText = false
        }
        elif inItem and inText do
            value += token.text
    }
    if scan.damaged do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return result
}

private func cellColumn(reference: string)->u64
{
    var result = 0'u64
    for value in reference
    {
        if value < 'A'u8 or value > 'Z'u8 do
            break
        result = result * 26 + value - 'A'u8 + 1
        if result > 512 do
            return Swag.U64.Max
    }
    return result ? result - 1 : Swag.U64.Max
}

private func checkedCellColumn(reference: string)->u64 fail
{
    let column = cellColumn(reference)
    if column != Swag.U64.Max or not reference.count do
        return column
    if reference[0] >= 'A'u8 and reference[0] <= 'Z'u8 do
        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
    fail Errors.InvalidFormatError{texts().err_Invalid}
}

private func sheetColumns(source: string)->u64 fail
{
    var scan = Package.Scanner.create(source)
    var token: Package.Token
    var nextColumn = 0'u64
    var columns = 0'u64
    while scan.next(&token)
    {
        if token.kind != .Start do
            continue
        if token.isElement("row") do
            nextColumn = 0
        elif token.isElement("c")
        {
            let column = try checkedCellColumn(token.attribute("r") orelse "")
            if column != Swag.U64.Max and column > nextColumn do
                nextColumn = column
            nextColumn += 1
            if nextColumn > columns do
                columns = nextColumn
            if columns > 512 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }
    }
    if scan.damaged do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return columns
}

private func appendColumnName(result: *String, column: u64)
{
    if column >= 26 do
        result[] += cast(u8, 'A'u8 + cast(u8, column / 26 - 1))
    result[] += cast(u8, 'A'u8 + cast(u8, column % 26))
}

private func appendCell(result: *Workbook, value, kind: string, shared: const *Array'String, formats: const *CellFormats, style: u32, numeric = true) fail
{
    var display: String
    let numericCell = numeric and (kind == "" or kind == "n") and value.count
    if kind == "s"
    {
        let index = catch StrConv.toU64(value) { fail Errors.InvalidFormatError{texts().err_Invalid} }
        if index >= shared.count do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        display = shared[index]
    }
    elif kind == "b"
    {
        display = value == "1" ? texts().ui_True : texts().ui_False
    }
    elif numericCell
    {
        let formatted = try formats.format(value, style)
        display = formatted.text
        if formatted.omitted do
            result.omittedFormats += 1
    }
    else
    {
        display = value
    }

    result.html += numericCell ? "<td style=\"text-align:right;padding-right:8px\">" : "<td>"
    Package.appendHtmlEscaped(&result.html, display)
    result.html  += "</td>"
    result.cells += 1
    if result.cells > 100_000 or result.html.count > 32 * 1024 * 1024 do
        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
}

private func appendSheet(result: *Workbook, source: string, shared: const *Array'String, formats: const *CellFormats) fail
{
    let columns = try sheetColumns(source)
    result.html += "<tr><th></th>"
    for column in 0 until columns
    {
        result.html += "<th>"
        appendColumnName(&result.html, column)
        result.html += "</th>"
    }
    result.html += "</tr>"
    var scan = Package.Scanner.create(source)
    var token: Package.Token
    var inRow = false
    var inCell = false
    var inValue = false
    var inInlineText = false
    var inFormula = false
    var hasFormula = false
    var hasCachedValue = false
    var nextColumn = 0'u64
    var nextRow = 1'u64
    var style = 0'u32
    var kind: String
    var value: String
    var formula: String
    while scan.next(&token)
    {
        if token.kind == .Start
        {
            if token.isElement("row")
            {
                let rowValue = token.attribute("r") orelse ""
                let rowNumber = rowValue.count ?
                    catch StrConv.toU64(rowValue) { fail Errors.InvalidFormatError{texts().err_Invalid} } : nextRow
                if not rowNumber or rowNumber > 1_048_576 do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                nextRow = rowNumber + 1
                result.html += "<tr><th style=\"padding-right:8px\">"
                result.html += Format.toString("%", rowNumber)
                result.html += "</th>"
                inRow = true
                nextColumn = 0
                if token.empty
                {
                    result.html += "</tr>"
                    inRow = false
                }
            }
            elif inRow and token.isElement("c")
            {
                inCell = true
                style = catch StrConv.toU32(token.attribute("s") orelse "0") { fail Errors.InvalidFormatError{texts().err_Invalid} }
                value.clear()
                formula.clear()
                hasFormula = false
                hasCachedValue = false
                let typeName = token.attribute("t")
                kind = typeName ? typeName : ""
                let referenceName = token.attribute("r")
                let reference = referenceName ? referenceName : ""
                let column = try checkedCellColumn(reference)
                if column != Swag.U64.Max and column > nextColumn
                {
                    while nextColumn < column
                    {
                        result.html += "<td></td>"
                        nextColumn += 1
                    }
                }
                if token.empty
                {
                    try appendCell(result, "", "", shared, formats, style)
                    nextColumn += 1
                    inCell = false
                }
            }
            elif inCell and token.isElement("v")
            {
                hasCachedValue = true
                inValue = not token.empty
            }
            elif inCell and token.isElement("f")
            {
                hasFormula = true
                inFormula = not token.empty
            }
            elif inCell and token.isElement("t") do
                inInlineText = true
        }
        elif token.kind == .End
        {
            if token.isElement("v") do
                inValue = false
            elif token.isElement("f") do
                inFormula = false
            elif token.isElement("t") do
                inInlineText = false
            elif token.isElement("c")
            {
                if hasFormula and not hasCachedValue
                {
                    kind.clear()
                    if formula.isEmpty() do
                        value = texts().ui_FormulaUnavailable
                    else
                    {
                        value = "="
                        value += formula
                    }
                }
                try appendCell(result, value, kind, shared, formats, style, numeric: not hasFormula or hasCachedValue)
                nextColumn += 1
                inCell = false
            }
            elif token.isElement("row")
            {
                result.html += "</tr>"
                inRow = false
            }
        }
        elif inCell and inFormula do
            formula += token.text
        elif inCell and (inValue or inInlineText) do
            value += token.text
    }
    if scan.damaged or inCell or inRow do
        fail Errors.InvalidFormatError{texts().err_Invalid}
}

impl Workbook
{
    mtd const details()->String
    {
        var result = Format.toString(texts().ui_Details, .sheets, .cells)
        if .omittedFormats do
            result += Format.toString(texts().ui_FormatsOmitted, .omittedFormats)
        return result
    }

    // Reads visible cell values without executing workbook macros, formulas, or links.
    func load(fileName: string)->Workbook fail
    {
        let archive   = try Archive.Zip.load(fileName)
        let parts     = Package.PartReader{fileName, &archive, texts().err_Invalid, texts().err_TooLarge}
        let source    = try parts.text("xl/workbook.xml")
        let relations = try parts.relationships("xl/workbook.xml")
        let sheets    = try readSheets(source, relations.toSlice())
        var date1904  = false
        var scan      = Package.Scanner.create(source)
        var token: Package.Token
        while scan.next(&token)
        {
            if token.kind == .Start and token.isElement("workbookPr") do
                date1904 = token.attribute("date1904") == "1" or token.attribute("date1904") == "true"
        }

        var stylePath = Package.relationshipPath(relations.toSlice(), "/styles")
        if stylePath.isEmpty() do
            stylePath = "xl/styles.xml"
        let formats    = try CellFormats.parse(try parts.text(stylePath, required: false), date1904)
        var shared: Array'String
        var sharedPath = Package.relationshipPath(relations.toSlice(), "/sharedStrings")
        if sharedPath.isEmpty() do
            sharedPath = "xl/sharedStrings.xml"
        if archive.tryFindEntry(sharedPath) do
            shared = try readSharedStrings(try parts.text(sharedPath))

        var result: #returntype
        result.html = "<html><body>"
        for &sheet in sheets
        {
            result.html += "<h2>"
            Package.appendHtmlEscaped(&result.html, sheet.name)
            result.html += "</h2><table>"
            let source = try parts.text(sheet.path)
            try appendSheet(&result, source, &shared, &formats)
            result.html   += "</table>"
            result.sheets += 1
        }

        result.html += "</body></html>"
        if result.omittedFormats
        {
            var notice: String = "<p><small>"
            Package.appendHtmlEscaped(&notice, texts().ui_FormatNotice)
            notice += "</small></p>"
            result.html.insert("<html><body>".count, notice)
        }

        return result
    }
}
