#global internal
#global namespace Viewers.Xlsx

using Core

struct Cell
{
    column:  u32
    text:    String
    formula: String
    style:   u32
    numeric: bool
    merge:   u32 = Swag.U32.Max
    covered: bool
}

struct Row
{
    index:  u32
    height: f32 = 20
    hidden: bool
    cells:  Array'Cell
}

struct Column
{
    width:    f32 = 64
    hidden:   bool
    authored: bool
}

struct Address
{
    row:    u32
    column: u32
}

impl Address
{
    func parse(reference: string)->Address fail
    {
        var result: #returntype
        var at     = 0'u64
        var column = 0'u32
        while at < reference.count and reference[at] >= 'A'u8 and reference[at] <= 'Z'u8
        {
            column = column * 26 + reference[at] - 'A'u8 + 1
            if column > 512 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            at += 1
        }

        if not column or at == reference.count do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        var row = 0'u32
        while at < reference.count
        {
            let byte = reference[at]
            if byte < '0'u8 or byte > '9'u8 do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            row = row * 10 + byte - '0'u8
            if row > 1_048_576 do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            at += 1
        }

        if not row do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        result.row    = row - 1
        result.column = column - 1
        return result
    }

    mtd const label()->String
    {
        var result = columnName(.column)
        result += Format.toString("%", .row + 1)
        return result
    }
}

struct MergedCells
{
    first: Address
    last:  Address
}

func columnName(column: u32)->String
{
    var result: String
    if column >= 26 do
        result += cast(u8, 'A'u8 + cast(u8, column / 26 - 1))
    result += cast(u8, 'A'u8 + cast(u8, column % 26))
    return result
}

// Sparse authored rows retain their addresses; empty gaps do not become allocated cell arrays.
struct Sheet
{
    name:             String
    rows:             Array'Row
    columns:          Array'Column
    merges:           Array'MergedCells
    defaultRowHeight: f32  = 20
    rowCount:         u32
    cells:            u64
    readingBytes:     u64
    simplifiedStyles: bool
    showGridLines:    bool = true
    omittedFormats:   u64
    hidden:           bool
    hiddenRanges:     bool
}

impl Sheet
{
    mtd const details()->String
    {
        var result = Format.toString(.cells == 1 ? texts().ui_Cell : texts().ui_Cells, .name, .cells)
        if .omittedFormats do
            result += Format.toString(texts().ui_FormatsOmitted, .omittedFormats)
        if .simplifiedStyles do
            result += texts().ui_StylesSimplified
        return result
    }

    mtd const findRow(index: u32)->u64
    {
        var first = 0'u64
        var last  = .rows.count
        while first < last
        {
            let middle = first + (last - first) / 2
            if .rows[middle].index < index do
                first = middle + 1
            else do
                last = middle
        }

        return first
    }

    mtd const cellAt(address: Address)->const *Cell?
    {
        let row = .findRow(address.row)
        if row >= .rows.count or .rows[row].index != address.row do
            return null
        for &cell in .rows[row].cells where cell.column == address.column do
            return cell
        return null
    }

    // A theme-aware reflow remains available when the authored grid is not the desired reading mode.
    mtd const readingHtml(includeHidden = false)->String
    {
        var html: String = "<html><body>"
        if .omittedFormats
        {
            html += "<p><small>"
            Package.appendHtmlEscaped(&html, texts().ui_FormatNotice)
            html += "</small></p>"
        }

        html += "<h2>"
        Package.appendHtmlEscaped(&html, .name)
        html += "</h2><table><tr><th></th>"
        for column, index in .columns where includeHidden or not column.hidden
        {
            html += "<th>"
            html += columnName(cast(u32, index))
            html += "</th>"
        }

        html += "</tr>"
        for row in .rows where includeHidden or not row.hidden
        {
            html += Format.toString("<tr><th style=\"padding-right:8px\">%</th>", row.index + 1)
            var nextColumn = 0'u32
            for cell in row.cells
            {
                while nextColumn < cell.column
                {
                    if includeHidden or not .columns[nextColumn].hidden do
                        html += "<td></td>"
                    nextColumn += 1
                }

                nextColumn = cell.column + 1
                if not includeHidden and .columns[cell.column].hidden do
                    continue
                html += cell.numeric ? "<td style=\"text-align:right;padding-right:8px\">" : "<td>"
                Package.appendHtmlEscaped(&html, cell.text)
                html += "</td>"
            }

            html += "</tr>"
        }

        html += "</table></body></html>"
        return html
    }
}
