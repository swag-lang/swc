#global internal
#global namespace Viewers.Xlsx

using Core

private struct SheetReference
{
    name:   String
    path:   String
    hidden: bool
}

// The readable cells of a spreadsheet, in workbook sheet order.
struct Workbook
{
    styles:         CellStyles
    sheets:         Array!{Sheet}
    activeSheet:    u64
    hiddenSheets:   u64
    cells:          u64
    omittedFormats: u64
}

private func readSheets(source: string, relations: const [..] Package.Relationship)->Array!{SheetReference} fail
{
    var scan = Package.Scanner.create(source)
    var token:  Package.Token
    var result: #returntype
    while scan.next(&token)
    {
        if token.kind != .Start or not token.isElement("sheet")
        {
            continue
        }

        let name = token.attribute("name")
        let id   = token.attribute("id")
        if not name or not id
        {
            fail Errors.InvalidFormatError{texts().err_Invalid}
        }

        var found = false
        for relation in relations where relation.id == id and Utf8.endsWith(relation.kind, "/worksheet")
        {
            result.add(SheetReference{name, relation.path, token.attribute("state") == "hidden" or token.attribute("state") == "veryHidden"})
            found = true
            break
        }

        if not found
        {
            fail Errors.InvalidFormatError{texts().err_Invalid}
        }

        if result.count > 200
        {
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }
    }

    if scan.damaged or result.isEmpty()
    {
        fail Errors.InvalidFormatError{texts().err_Invalid}
    }

    return result
}

private func readSharedStrings(source: string)->Array!{String} fail
{
    var scan   = Package.Scanner.create(source)
    var token:  Package.Token
    var result: #returntype
    var value:  String
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
            else if inItem and token.isElement("t")
            {
                inText = true
            }
        }
        else if token.kind == .End
        {
            if token.isElement("si")
            {
                result.add(value)
                inItem = false
            }
            else if token.isElement("t")
            {
                inText = false
            }
        }
        else if inItem and inText
        {
            value += token.text
        }
    }

    if scan.damaged
    {
        fail Errors.InvalidFormatError{texts().err_Invalid}
    }

    return result
}

private func appendCell(result: *Sheet, value, kind: string, shared: const *Array!{String}, formats: const *CellFormats, style: u32, numeric = true, formula: string = "") fail
{
    var display: String
    let numericCell = numeric and (kind == "" or kind == "n") and value.count
    if kind == "s"
    {
        let index = catch StrConv.toU64(value) { fail Errors.InvalidFormatError{texts().err_Invalid} }
        if index >= shared.count
        {
            fail Errors.InvalidFormatError{texts().err_Invalid}
        }

        display = shared[index]
    }
    else if kind == "b"
    {
        display = value == "1" ? texts().ui_True : texts().ui_False
    }
    else if numericCell
    {
        let formatted = try formats.format(value, style)
        display = formatted.text
        if formatted.omitted
        {
            result.omittedFormats += 1
        }
    }
    else
    {
        display = value
    }

    var cell: Cell
    cell.text    = #move display
    cell.style   = style
    cell.numeric = numericCell
    cell.formula = formula
    if cell.text.count > 1024 * 1024 or cell.formula.count > 64 * 1024
    {
        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
    }

    result.rows.backPtr().cells.add(cell)
    result.cells        += 1
    result.readingBytes += cell.text.count + cell.formula.count + 80
    for byte in cell.text
    {
        if byte == '&'_u8
        {
            result.readingBytes += 4
        }
        else if byte == '<'_u8 or byte == '>'_u8
        {
            result.readingBytes += 3
        }
        else if byte == '"'_u8
        {
            result.readingBytes += 5
        }
    }
}

private func appendSheet(result: *Sheet, source: string, shared: const *Array!{String}, formats: const *CellFormats, cellBudget, htmlBudget: u64) fail
{
    let defaults       = try SheetStyleDefaults.parse(source)
    var rowStyle       = 0_u32
    var hasRowStyle    = false
    var scan           = Package.Scanner.create(source)
    var token:   Package.Token
    var inRow          = false
    var inCell         = false
    var inValue        = false
    var inInlineText   = false
    var inFormula      = false
    var hasFormula     = false
    var hasCachedValue = false
    var nextColumn     = 0_u64
    var nextRow        = 1_u64
    var style          = 0_u32
    var kind:    String
    var value:   String
    var formula: String
    while scan.next(&token)
    {
        if result.cells > cellBudget or result.readingBytes > htmlBudget
        {
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        if token.kind == .Start
        {
            if token.isElement("pane") and (token.attribute("state") == "frozen" or token.attribute("state") == "frozenSplit")
            {
                // Frozen panes split at integral cells; reject fractional or unbounded requests.
                if let split = token.attribute("xSplit")
                {
                    let columns = catch StrConv.toU32(split) { fail Errors.InvalidFormatError{texts().err_Invalid} }
                    if columns > 255
                    {
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    }

                    result.frozenColumns = columns
                }

                if let split = token.attribute("ySplit")
                {
                    let rows = catch StrConv.toU32(split) { fail Errors.InvalidFormatError{texts().err_Invalid} }
                    if rows > 256
                    {
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    }

                    result.frozenRows = rows
                }
            }
            else if token.isElement("row")
            {
                let rowValue  = token.attribute("r") orelse ""
                let rowNumber = rowValue.count ?
                                catch StrConv.toU64(rowValue) { fail Errors.InvalidFormatError{texts().err_Invalid} } : nextRow
                if rowNumber < nextRow or rowNumber > 1_048_576
                {
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                }

                nextRow     = rowNumber + 1
                hasRowStyle = token.attribute("customFormat") == "1" or token.attribute("customFormat") == "true"
                if hasRowStyle
                {
                    rowStyle = catch StrConv.toU32(token.attribute("s") orelse "0") { fail Errors.InvalidFormatError{texts().err_Invalid} }
                }

                var row: Row
                row.index = cast(u32, rowNumber - 1)
                result.rows.add(row)
                result.rowCount     = cast(u32, rowNumber)
                result.readingBytes += 80
                inRow               = true
                nextColumn          = 0
                if token.empty
                {
                    inRow = false
                }
            }
            else if inRow and token.isElement("c")
            {
                inCell = true
                value.clear()
                formula.clear()
                hasFormula     = false
                hasCachedValue = false
                let typeName = token.attribute("t")
                kind = typeName ? typeName : ""
                if let reference = token.attribute("r")
                {
                    let address = try Address.parse(reference)
                    if address.row + 1 != nextRow - 1 or address.column < nextColumn
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    nextColumn = address.column
                }

                if nextColumn >= 512
                {
                    fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                }

                if let direct = token.attribute("s")
                {
                    style = catch StrConv.toU32(direct) { fail Errors.InvalidFormatError{texts().err_Invalid} }
                }
                else
                {
                    style = hasRowStyle ? rowStyle : defaults.columns[nextColumn]
                }

                if token.empty
                {
                    try appendCell(result, "", "", shared, formats, style)
                    result.rows.backPtr().cells.backPtr().column = cast(u32, nextColumn)
                    nextColumn += 1
                    inCell     = false
                }
            }
            else if inCell and token.isElement("v")
            {
                hasCachedValue = true
                inValue        = not token.empty
            }
            else if inCell and token.isElement("f")
            {
                hasFormula = true
                inFormula  = not token.empty
            }
            else if inCell and token.isElement("t")
            {
                inInlineText = true
            }
        }
        else if token.kind == .End
        {
            if token.isElement("v")
            {
                inValue = false
            }
            else if token.isElement("f")
            {
                inFormula = false
            }
            else if token.isElement("t")
            {
                inInlineText = false
            }
            else if token.isElement("c")
            {
                if hasFormula and not hasCachedValue
                {
                    kind.clear()
                    if formula.isEmpty()
                    {
                        value = texts().ui_FormulaUnavailable
                    }
                    else
                    {
                        value = "="
                        value += formula
                    }
                }

                try appendCell(result, value, kind, shared, formats, style, numeric: not hasFormula or hasCachedValue, formula: formula)
                result.rows.backPtr().cells.backPtr().column = cast(u32, nextColumn)
                nextColumn += 1
                inCell     = false
            }
            else if token.isElement("row")
            {
                inRow = false
            }
        }
        else if inCell and inFormula
        {
            formula += token.text
        }
        else if inCell and (inValue or inInlineText)
        {
            value += token.text
        }
    }

    if scan.damaged or inCell or inRow
    {
        fail Errors.InvalidFormatError{texts().err_Invalid}
    }
}

impl Workbook
{
    mtd const details()->String
    {
        var result = Format.toString(texts().ui_Details, .sheets.count, .cells)
        if .omittedFormats
        {
            result += Format.toString(texts().ui_FormatsOmitted, .omittedFormats)
        }

        return result
    }

    // Reads visible cell values without executing workbook macros, formulas, or links.
    func load(fileName: string)->Workbook fail
    {
        let archive     = try Archive.Zip.load(fileName)
        let parts       = Package.PartReader{fileName, &archive, texts().err_Invalid, texts().err_TooLarge}
        let source      = try parts.text("xl/workbook.xml")
        let relations   = try parts.relationships("xl/workbook.xml")
        let sheets      = try readSheets(source, relations.toSlice())
        var activeSheet = 0_u64
        var date1904    = false
        var scan        = Package.Scanner.create(source)
        var token: Package.Token
        while scan.next(&token)
        {
            if token.kind == .Start and token.isElement("workbookPr")
            {
                date1904 = token.attribute("date1904") == "1" or token.attribute("date1904") == "true"
            }
            else if token.kind == .Start and token.isElement("workbookView")
            {
                activeSheet = catch StrConv.toU64(token.attribute("activeTab") orelse "0") { fail Errors.InvalidFormatError{texts().err_Invalid} }
            }
        }

        var stylePath = Package.relationshipPath(relations.toSlice(), "/styles")
        if stylePath.isEmpty()
        {
            stylePath = "xl/styles.xml"
        }

        let styleSource = try parts.text(stylePath, required: false)
        let formats     = try CellFormats.parse(styleSource, date1904)
        var theme       = Package.OfficeTheme.defaults()
        var themePath   = Package.relationshipPath(relations.toSlice(), "/theme")
        if themePath.isEmpty()
        {
            themePath = "xl/theme/theme1.xml"
        }

        theme.read(try parts.text(themePath, required: false))
        var shared: Array!{String}
        var sharedPath = Package.relationshipPath(relations.toSlice(), "/sharedStrings")
        if sharedPath.isEmpty()
        {
            sharedPath = "xl/sharedStrings.xml"
        }

        if archive.tryFindEntry(sharedPath)
        {
            shared = try readSharedStrings(try parts.text(sharedPath))
        }

        var result: #returntype
        result.activeSheet = activeSheet < sheets.count ? activeSheet : 0
        result.styles      = try CellStyles.parse(styleSource, &theme)
        var htmlBytes = 0_u64
        for &reference in sheets
        {
            var sheet: Sheet
            sheet.name   = reference.name
            sheet.hidden = reference.hidden
            let source = try parts.text(reference.path)
            try appendSheet(&sheet, source, &shared, &formats, 100_000 - result.cells, 32 * 1024 * 1024 - htmlBytes)
            try sheet.readGeometry(source)
            for row in sheet.rows
            {
                for cell in row.cells where result.styles.look(cell.style).limited
                {
                    sheet.simplifiedStyles = true
                }
            }

            result.cells += sheet.cells
            result.omittedFormats += sheet.omittedFormats
            htmlBytes    += sheet.readingBytes
            if result.cells > 100_000 or htmlBytes > 32 * 1024 * 1024
            {
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            }

            if sheet.hidden
            {
                result.hiddenSheets += 1
            }

            result.sheets.add(sheet)
        }

        return result
    }
}
