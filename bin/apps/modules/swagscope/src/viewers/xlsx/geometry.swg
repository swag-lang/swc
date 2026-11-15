#global internal
#global namespace Viewers.Xlsx

using Core

private func dimension(value: string, maximum: f64)->f32 fail
{
    let number = catch StrConv.toF64(value) { fail Errors.InvalidFormatError{texts().err_Invalid} }
    if not Math.isFinite(number) or number < 0 or number > maximum do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return cast(f32, number)
}

private func columnPixels(value: f32)->f32
{
    if value < 1 do
        return Math.floor(value * 12 + 0.5)
    return Math.floor(value * 7 + 5)
}

impl Sheet
{
    mtd readGeometry(source: string) fail
    {
        var columnCount = 1'u32
        for row in .rows do
            for cell in row.cells do
                columnCount = Math.max(columnCount, cell.column + 1)
        var defaultWidth  = 64.0'f32
        var authoredWidth = false
        var defaultHeight = 20.0'f32
        var scan          = Package.Scanner.create(source)
        var token: Package.Token
        while scan.next(&token)
        {
            if token.kind != .Start do
                continue
            if token.isElement("sheetView")
            {
                .showGridLines = (token.attribute("showGridLines") orelse "1") != "0" and token.attribute("showGridLines") != "false"
            }
            elif token.isElement("sheetFormatPr")
            {
                if let width = token.attribute("defaultColWidth")
                {
                    defaultWidth  = columnPixels(try dimension(width, 255))
                    authoredWidth = true
                }

                if let height = token.attribute("defaultRowHeight") do
                    defaultHeight = try dimension(height, 409.5) * 4 / 3
            }
            elif token.isElement("mergeCell")
            {
                let reference = token.attribute("ref") orelse ""
                let colon     = Utf8.indexOf(reference, ':'rune)
                if colon == Swag.U64.Max do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                let first = try Address.parse(reference[until colon])
                let last  = try Address.parse(reference[colon + 1 to])
                if first.column > last.column or first.row > last.row do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                for previous in .merges where first.column <= previous.last.column and
                                              last.column >= previous.first.column and
                                              first.row <= previous.last.row and
                                              last.row >= previous.first.row do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                .merges.add(MergedCells{first, last})
                if .merges.count > 2048 do
                    fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                columnCount = Math.max(columnCount, last.column + 1)
                .rowCount   = Math.max(.rowCount, last.row + 1)
            }
        }

        if scan.damaged do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        .rowCount         = Math.max(.rowCount, 1)
        .defaultRowHeight = defaultHeight
        .hiddenRanges     = defaultHeight == 0 or defaultWidth == 0
        .columns.resize(columnCount)
        for &column in .columns
        {
            column.width    = defaultWidth
            column.authored = authoredWidth
        }

        for &row in .rows do
            row.height = defaultHeight

        scan = Package.Scanner.create(source)
        var rowIndex = 0'u64
        while scan.next(&token)
        {
            if token.kind != .Start do
                continue
            if token.isElement("col")
            {
                let first = catch StrConv.toU64(token.attribute("min") orelse "") orelse 0
                let last  = catch StrConv.toU64(token.attribute("max") orelse "") orelse 0
                if not first or last < first or last > 16384 do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                var width = defaultWidth
                if let authored = token.attribute("width") do
                    width = columnPixels(try dimension(authored, 255))
                let hidden = token.attribute("hidden") == "1" or token.attribute("hidden") == "true"
                var index  = first - 1
                while index < .columns.count and index < last
                {
                    .columns[index] = Column{width, hidden or width == 0, authoredWidth or token.attribute("width") != null}
                    .hiddenRanges   = .hiddenRanges or hidden or width == 0
                    index           += 1
                }
            }
            elif token.isElement("row")
            {
                if rowIndex >= .rows.count do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                let row = &.rows[rowIndex]
                if let height = token.attribute("ht") do
                    row.height = try dimension(height, 409.5) * 4 / 3
                row.hidden    = token.attribute("hidden") == "1" or token.attribute("hidden") == "true"
                .hiddenRanges = .hiddenRanges or row.hidden or row.height == 0
                rowIndex      += 1
            }
        }

        // Without an authored width, a reading grid fits ordinary labels instead of guessing an
        // editor's default font metrics. Explicit column and workbook defaults always take precedence.
        for row in .rows
        {
            for cell in row.cells where not .columns[cell.column].authored
            {
                var characters = 0'u64
                Utf8.visitRunes(cell.text.toString())
                {
                    characters += 1
                }

                .columns[cell.column].width = Math.max(.columns[cell.column].width, Math.min(cast(f32, characters) * 8 + 16, 360))
            }
        }

        // Each disjoint merge visits only its declared sparse row interval, never blank grid cells.
        for range, index in .merges
        {
            var row = .findRow(range.first.row)
            while row < .rows.count and .rows[row].index <= range.last.row
            {
                for &cell in .rows[row].cells where cell.column >= range.first.column and cell.column <= range.last.column
                {
                    cell.merge   = cast(u32, index)
                    cell.covered = .rows[row].index != range.first.row or cell.column != range.first.column
                }

                row += 1
            }
        }
    }
}
