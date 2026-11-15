#global internal
#global namespace Viewers.Ods

using Core

private func repeatCount(token: const *Package.Token, name: string, maximum: u32)->u32 fail
{
    let count = catch StrConv.toU32(token.attribute(name) orelse "1") orelse 0
    if not count do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    if count > maximum do
        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
    return count
}

private struct EmptyRows
{
    row:   Xlsx.Row
    count: u32
}

private struct Reader
{
    late styles:      const *Styles
    workbook:         Xlsx.Workbook
    sheet:            Xlsx.Sheet
    row:              Xlsx.Row
    cell:             Xlsx.Cell
    columnDefaults:   [512] u32
    rowDefault:       u32 = Swag.U32.Max
    rowIndex:         u32
    columnIndex:      u32
    columnDefinition: u32
    rowRepeat:        u32 = 1
    cellRepeat:       u32 = 1
    spanColumns:      u32 = 1
    spanRows:         u32 = 1
    value:            String
    kind:             String
    paragraphs:       u32
    inParagraph:      bool
    covered:          bool
    inheritColumns:   bool
    cellPresent:      bool
    readingBytes:     u64
    emptyRows:        Array'EmptyRows
    rowOmitted:       u64
    rowBytes:         u64
}

private impl Reader
{
    mtd beginSheet(token: const *Package.Token) fail
    {
        .sheet = {}
        .emptyRows.clear()
        .sheet.name = token.attribute("name") orelse ""
        if .sheet.name.isEmpty() or .sheet.name.count > 1024 do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        let geometry = .styles.geometry(token.attribute("style-name") orelse "", "table")
        .sheet.hidden           = geometry.display == .Off or token.attribute("display") == "false"
        .sheet.simplifiedStyles = geometry.look.limited
        .rowIndex               = 0
        .columnDefinition       = 0
        for index in 512 do
            .columnDefaults[index] = 0
        .sheet.columns.resize(512)
    }

    mtd column(token: const *Package.Token) fail
    {
        let count = try repeatCount(token, "number-columns-repeated", 16384)
        if .columnDefinition > 16384 - count do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        let geometry  = .styles.geometry(token.attribute("style-name") orelse "", "table-column")
        let cellStyle = .styles.cellId(token.attribute("default-cell-style-name") orelse "")
        let next      = .columnDefinition + count
        let last      = Math.min(next, 512)
        while .columnDefinition < last
        {
            let item = &.sheet.columns[.columnDefinition]
            if geometry.width >= 0
            {
                item.width    = geometry.width
                item.authored = true
            }

            item.hidden = token.attribute("visibility") == "collapse" or
                          token.attribute("visibility") == "filter" or
                          item.width == 0
            .columnDefaults[.columnDefinition] = cellStyle
            .columnDefinition += 1
        }

        .columnDefinition       = next
        .sheet.simplifiedStyles = .sheet.simplifiedStyles or geometry.look.limited
    }

    mtd beginRow(token: const *Package.Token) fail
    {
        .rowRepeat = try repeatCount(token, "number-rows-repeated", 1_048_576)
        if .rowIndex > 1_048_576 - .rowRepeat do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        .row        = {}
        .rowOmitted = 0
        .rowBytes   = 0
        .row.index  = .rowIndex
        let geometry = .styles.geometry(token.attribute("style-name") orelse "", "table-row")
        .row.height = geometry.height >= 0 ? geometry.height : .sheet.defaultRowHeight
        .row.hidden = token.attribute("visibility") == "collapse" or
                      token.attribute("visibility") == "filter" or
                      .row.height == 0
        .rowDefault = .styles.cellId(token.attribute("default-cell-style-name") orelse "")
        if token.attribute("default-cell-style-name") == null do
            .rowDefault = Swag.U32.Max
        .columnIndex = 0
        .sheet.simplifiedStyles = .sheet.simplifiedStyles or geometry.look.limited
    }

    mtd beginCell(token: const *Package.Token) fail
    {
        .cellRepeat = try repeatCount(token, "number-columns-repeated", 16384)
        if .columnIndex > 16384 - .cellRepeat do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        .covered     = token.isElement("covered-table-cell")
        .cell        = {}
        .cell.column = .columnIndex
        let styleName = token.attribute("style-name")
        .inheritColumns = not styleName and .rowDefault == Swag.U32.Max
        .cell.style     = styleName ? .styles.cellId(styleName) : .rowDefault
        if not styleName and .cell.style == Swag.U32.Max do
            .cell.style = .columnIndex < 512 ? .columnDefaults[.columnIndex] : 0
        .cell.formula = token.attribute("formula") orelse ""
        .kind         = token.attribute("value-type") orelse ""
        .value        = token.attribute("string-value") orelse token.attribute("value") orelse token.attribute("date-value") orelse token.attribute("time-value") orelse token.attribute("boolean-value") orelse ""
        .cell.numeric = .kind == "float" or
                        .kind == "currency" or
                        .kind == "percentage" or
                        .kind == "date" or
                        .kind == "time"
        .spanColumns = try repeatCount(token, "number-columns-spanned", 16384)
        .spanRows    = try repeatCount(token, "number-rows-spanned", 1_048_576)
        .paragraphs  = 0
        .inParagraph = false
        .cellPresent = true
    }

    mtd finishCell() fail
    {
        if not .paragraphs
        {
            .cell.text = .value
            if .kind == "boolean" do
                .cell.text = .value == "true" or .value == "1" ? Xlsx.texts().ui_True : Xlsx.texts().ui_False
        }

        if .cell.text.isEmpty() and not .cell.formula.isEmpty() do
            .cell.text = .cell.formula
        if .cell.text.count > 1024 * 1024 or .cell.formula.count > 64 * 1024 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        let look    = .styles.cells.look(.cell.style)
        let content = not .cell.text.isEmpty() or not .cell.formula.isEmpty() or .spanColumns > 1 or .spanRows > 1
        let paint   = look.fill != 0 or look.hasBorder()
        if not .covered
        {
            if (content or (paint and not .inheritColumns)) and
               (.columnIndex + .cellRepeat > 512 or
                .spanColumns > 512 - .columnIndex or
                .spanRows > 1_048_576 - .rowIndex) do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            if (.spanColumns > 1 or .spanRows > 1) and (.cellRepeat > 1 or .rowRepeat > 1) do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            let count = .columnIndex < 512 ? Math.min(.cellRepeat, 512 - .columnIndex) : 0
            for offset in count
            {
                var item = .cell
                item.column += offset
                if .inheritColumns do
                    item.style = .columnDefaults[item.column]
                let itemLook = .styles.cells.look(item.style)
                .sheet.simplifiedStyles = .sheet.simplifiedStyles or itemLook.limited
                if content or itemLook.fill != 0 or itemLook.hasBorder()
                {
                    let cost = item.text.count * 6 + item.formula.count + 80
                    if cost > 32 * 1024 * 1024 - .readingBytes - .sheet.readingBytes - .rowBytes do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    .rowBytes += cost
                    .row.cells.add(item)
                    if not .paragraphs and .cell.numeric and not .value.isEmpty() do
                        .rowOmitted += 1
                }
            }

            if .spanColumns > 1 or .spanRows > 1
            {
                let first = Xlsx.Address{.rowIndex, .columnIndex}
                let last  = Xlsx.Address{.rowIndex + .spanRows - 1, .columnIndex + .spanColumns - 1}
                for range in .sheet.merges where first.column <= range.last.column and
                                                 last.column >= range.first.column and
                                                 first.row <= range.last.row and
                                                 last.row >= range.first.row do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                .sheet.merges.add(Xlsx.MergedCells{first, last})
                if .sheet.merges.count > 2048 do
                    fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                .sheet.rowCount = Math.max(.sheet.rowCount, last.row + 1)
            }
        }

        .columnIndex += .cellRepeat
        .cellPresent = false
    }

    mtd finishRow() fail
    {
        // Producers append vast empty repeated tails. Advance their address without allocating them.
        if not .row.cells.isEmpty()
        {
            if .rowBytes * .rowRepeat > 32 * 1024 * 1024 - .readingBytes - .sheet.readingBytes do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}

            // Interior empty geometry matters; a producer's unused trailing rows do not.
            for run in .emptyRows
            {
                if run.count > 100_000 - .sheet.rows.count do
                    fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                for offset in run.count
                {
                    var item = run.row
                    item.index += offset
                    .sheet.rows.add(item)
                }

                .sheet.hiddenRanges = .sheet.hiddenRanges or run.row.hidden
            }

            .emptyRows.clear()
            if .row.cells.count * .rowRepeat > 100_000 - .workbook.cells - .sheet.cells do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            for offset in .rowRepeat
            {
                var row = .row
                row.index += offset
                .sheet.hiddenRanges = .sheet.hiddenRanges or row.hidden
                .sheet.rows.add(row)
                .sheet.cells += row.cells.count
                for cell in row.cells
                {
                    .sheet.readingBytes += cell.text.count * 6 + cell.formula.count + 80
                    if .sheet.readingBytes + .readingBytes > 32 * 1024 * 1024 do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                }
            }

            .sheet.rowCount       = Math.max(.sheet.rowCount, .rowIndex + .rowRepeat)
            .sheet.omittedFormats += .rowOmitted * .rowRepeat
        }
        elif .row.hidden or Math.abs(.row.height - .sheet.defaultRowHeight) > 0.05
        {
            if .emptyRows.count >= 100_000 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            .emptyRows.add(EmptyRows{.row, .rowRepeat})
        }

        .rowIndex += .rowRepeat
    }

    mtd finishSheet() fail
    {
        var columns = 1'u32
        for row in .sheet.rows do
            for cell in row.cells do
                columns = Math.max(columns, cell.column + 1)
        for range in .sheet.merges do
            columns = Math.max(columns, range.last.column + 1)
        .sheet.columns.resize(columns)
        for column in .sheet.columns do
            .sheet.hiddenRanges = .sheet.hiddenRanges or column.hidden
        for row in .sheet.rows
        {
            for cell in row.cells where not .sheet.columns[cell.column].authored
            {
                var characters = 0'u64
                Utf8.visitRunes(cell.text.toString())
                { characters += 1 }
                .sheet.columns[cell.column].width = Math.max(.sheet.columns[cell.column].width, Math.min(cast(f32, characters) * 8 + 16, 360))
            }
        }

        for range, index in .sheet.merges
        {
            var row = .sheet.findRow(range.first.row)
            while row < .sheet.rows.count and .sheet.rows[row].index <= range.last.row
            {
                for &cell in .sheet.rows[row].cells where cell.column >= range.first.column and cell.column <= range.last.column
                {
                    cell.merge   = cast(u32, index)
                    cell.covered = .sheet.rows[row].index != range.first.row or cell.column != range.first.column
                }

                row += 1
            }
        }

        .sheet.rowCount = Math.max(.sheet.rowCount, 1)
        .workbook.cells += .sheet.cells
        .workbook.omittedFormats += .sheet.omittedFormats
        .readingBytes   += .sheet.readingBytes
        if .sheet.hidden do
            .workbook.hiddenSheets += 1
        .workbook.sheets.add(#move .sheet)
        if .workbook.sheets.count > 200 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
    }

    mtd read(source: string)->Xlsx.Workbook fail
    {
        var scan        = Package.Scanner.create(source)
        var token: Package.Token
        var depth       = 0'u64
        var spreadsheet = Swag.U64.Max
        var table       = Swag.U64.Max
        var row         = Swag.U64.Max
        var skip        = Swag.U64.Max
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                depth += 1
                if token.isElement("spreadsheet")
                {
                    spreadsheet = depth
                }
                elif skip == Swag.U64.Max and spreadsheet != Swag.U64.Max
                {
                    if token.isElement("annotation") or
                       token.isElement("scripts") or
                       token.isElement("tracked-changes") or
                       token.isElement("frame") or
                       token.isElement("forms") or
                       token.isElement("shapes")
                    {
                        skip = depth
                        if table != Swag.U64.Max do
                            .sheet.simplifiedStyles = true
                    }
                    elif token.isElement("table")
                    {
                        if table != Swag.U64.Max do
                            fail Errors.UnsupportedFormatError{texts().err_Invalid}
                        table = depth
                        try .beginSheet(&token)
                    }
                    elif table != Swag.U64.Max
                    {
                        if token.isElement("table-column")
                        {
                            try .column(&token)
                        }
                        elif token.isElement("table-row")
                        {
                            row = depth
                            try .beginRow(&token)
                        }
                        elif row != Swag.U64.Max
                        {
                            if token.isElement("table-cell") or token.isElement("covered-table-cell")
                            {
                                try .beginCell(&token)
                            }
                            elif .cellPresent
                            {
                                if token.isElement("p")
                                {
                                    if .paragraphs do
                                        .cell.text += "\n"
                                    .paragraphs  += 1
                                    .inParagraph = true
                                }
                                elif token.isElement("line-break")
                                {
                                    .cell.text += "\n"
                                }
                                elif token.isElement("tab")
                                {
                                    .cell.text += "\t"
                                }
                                elif token.isElement("s")
                                {
                                    let count = try repeatCount(&token, "c", 8192)
                                    for count do
                                        .cell.text += " "
                                }
                            }
                        }
                    }
                }
            }
            elif token.kind == .Text and .cellPresent and .inParagraph and skip == Swag.U64.Max
            {
                .cell.text += token.text
            }

            if .cell.text.count > 1024 * 1024 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            if token.kind == .End or token.empty
            {
                if skip == depth
                {
                    skip = Swag.U64.Max
                }
                elif skip == Swag.U64.Max and table != Swag.U64.Max
                {
                    if token.isElement("p")
                    {
                        .inParagraph = false
                    }
                    elif token.isElement("table-cell") or token.isElement("covered-table-cell")
                    {
                        try .finishCell()
                    }
                    elif token.isElement("table-row")
                    {
                        try .finishRow()
                        row = Swag.U64.Max
                    }
                    elif token.isElement("table")
                    {
                        try .finishSheet()
                        table = Swag.U64.Max
                    }
                }

                if spreadsheet == depth do
                    spreadsheet = Swag.U64.Max
                depth -= 1
            }
        }

        if scan.damaged or .workbook.sheets.isEmpty() do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        return #move .workbook
    }
}

// Uses saved display strings and cached values; formulas, links and macros are never evaluated.
func load(fileName: string)->Xlsx.Workbook fail
{
    let archive = try Odf.openPackage(fileName, "application/vnd.oasis.opendocument.spreadsheet", texts().err_Invalid, texts().err_TooLarge, texts().err_Encrypted)
    let parts   = Package.PartReader{fileName, &archive, texts().err_Invalid, texts().err_TooLarge}
    let source  = try parts.text("content.xml")
    var styles: Styles
    try styles.read(try parts.text("styles.xml", required: false, limit: 8 * 1024 * 1024))
    try styles.read(source)
    styles.finish()
    var reader: Reader
    reader.styles = &styles
    var result = try reader.read(source)
    result.styles = #move styles.cells
    let settings = try parts.text("settings.xml", required: false, limit: 2 * 1024 * 1024)
    var scan     = Package.Scanner.create(settings)
    var token: Package.Token
    var item:  String
    var value: String
    while scan.next(&token)
    {
        if token.kind == .Start and token.isElement("config-item")
        {
            item = token.attribute("name") orelse ""
            value.clear()
        }
        elif token.kind == .Text and not item.isEmpty()
        {
            value += token.text
        }

        if (token.kind == .End or token.empty) and token.isElement("config-item")
        {
            if item == "ActiveTable" do
                for sheet, index in result.sheets where sheet.name == value do
                    result.activeSheet = index
            if item == "ShowGrid" do
                for &sheet in result.sheets do
                    sheet.showGridLines = value != "false"
            item.clear()
        }
    }

    return result
}
