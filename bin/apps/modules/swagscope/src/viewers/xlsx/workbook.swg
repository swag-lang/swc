#global internal
#global namespace Viewers.Xlsx

using Core

private struct Sheet
{
    name: String
    path: String
}

private struct Relationship
{
    id:     String
    target: String
}

// The readable cells of a spreadsheet, in workbook sheet order.
struct Workbook
{
    html:   String
    sheets: u64
    cells:  u64
}

private func readPart(fileName: string, archive: const *Archive.Zip, path: string)->String fail
{
    let entry = archive.tryFindEntry(path)
    if not entry do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    if entry.uncompressedSize > 16 * 1024 * 1024 do
        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
    let data = try Archive.Zip.loadEntry(fileName, entry)
    return String.from(cast(string, data.toSlice()))
}

private func readRelationships(source: string)->Array'Relationship fail
{
    var scan = Package.Scanner.create(source)
    var token: Package.Token
    var result: #returntype
    while scan.next(&token)
    {
        if token.kind != .Start or not token.isElement("Relationship") do
            continue
        let id = token.attribute("Id")
        let target = token.attribute("Target")
        let kind = token.attribute("Type")
        if not id or not target or not kind do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        if Utf8.contains(kind, "/worksheet")
        {
            let path = Package.resolveRelationshipTarget("xl", target)
            if path.isEmpty() do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            result.add(Relationship{id, path})
        }
    }
    if scan.damaged do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return result
}

private func readSheets(source: string, relations: const *Array'Relationship)->Array'Sheet fail
{
    var scan = Package.Scanner.create(source)
    var token: Package.Token
    var result: #returntype
    while scan.next(&token)
    {
        if token.kind != .Start or not token.isElement("sheet") do
            continue
        let name = token.attribute("name")
        let id = token.attribute("id")
        if not name or not id do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        var found = false
        for &relation in relations[] where relation.id == id
        {
            result.add(Sheet{name, relation.target})
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
            let column = cellColumn(token.attribute("r") orelse "")
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

private func appendCell(result: *Workbook, value, kind: string, shared: const *Array'String) fail
{
    result.html += "<td>"
    if kind == "s"
    {
        let index = catch StrConv.toU64(value) { fail Errors.InvalidFormatError{texts().err_Invalid} }
        if index >= shared.count do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        Package.appendHtmlEscaped(&result.html, shared[index])
    }
    elif kind == "b" do
        result.html += value == "1" ? texts().ui_True : texts().ui_False
    else do
        Package.appendHtmlEscaped(&result.html, value)
    result.html += "</td>"
    result.cells += 1
    if result.cells > 100_000 or result.html.count > 32 * 1024 * 1024 do
        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
}

private func appendSheet(result: *Workbook, source: string, shared: const *Array'String) fail
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
    var nextColumn = 0'u64
    var nextRow = 1'u64
    var kind: String
    var value: String
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
                result.html += "<tr><th>"
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
                value.clear()
                let typeName = token.attribute("t")
                kind = typeName ? typeName : ""
                let referenceName = token.attribute("r")
                let reference = referenceName ? referenceName : ""
                let column = cellColumn(reference)
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
                    try appendCell(result, "", "", shared)
                    nextColumn += 1
                    inCell = false
                }
            }
            elif inCell and token.isElement("v") do
                inValue = true
            elif inCell and token.isElement("t") do
                inInlineText = true
        }
        elif token.kind == .End
        {
            if token.isElement("v") do
                inValue = false
            elif token.isElement("t") do
                inInlineText = false
            elif token.isElement("c")
            {
                try appendCell(result, value, kind, shared)
                nextColumn += 1
                inCell = false
            }
            elif token.isElement("row")
            {
                result.html += "</tr>"
                inRow = false
            }
        }
        elif inCell and (inValue or inInlineText) do
            value += token.text
    }
    if scan.damaged or inCell or inRow do
        fail Errors.InvalidFormatError{texts().err_Invalid}
}

impl Workbook
{
    // Reads visible cell values without executing workbook macros, formulas, or links.
    func load(fileName: string)->Workbook fail
    {
        let archive = try Archive.Zip.load(fileName)
        let relations = try readRelationships(try readPart(fileName, &archive, "xl/_rels/workbook.xml.rels"))
        let sheets = try readSheets(try readPart(fileName, &archive, "xl/workbook.xml"), &relations)
        var shared: Array'String
        if archive.tryFindEntry("xl/sharedStrings.xml") do
            shared = try readSharedStrings(try readPart(fileName, &archive, "xl/sharedStrings.xml"))

        var result: #returntype
        result.html = "<html><body>"
        for &sheet in sheets
        {
            result.html += "<h2>"
            Package.appendHtmlEscaped(&result.html, sheet.name)
            result.html += "</h2><table>"
            let source = try readPart(fileName, &archive, sheet.path)
            try appendSheet(&result, source, &shared)
            result.html += "</table>"
            result.sheets += 1
        }
        result.html += "</body></html>"
        return result
    }
}
