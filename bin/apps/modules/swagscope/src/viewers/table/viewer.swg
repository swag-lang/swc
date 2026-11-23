#global internal
#global namespace Viewers.Table

using Core, Core.Errors, Pixel, Gui

// Describes the delimited-text table viewer to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "table"
        .staticName   = "Table"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Table)
        .create       = &createViewer
        .thumbnail    = &loadThumbnail
        .textual      = true
        .smokeFixture = "viewer.csv"
        .addSelectors(".csv;.tsv;.tab")
    }

    return result
}

// Draws a small sample of the parsed rows without reading the rest of a large table.
private func loadThumbnail(fileName: string, maxSide: u32)->Image fail
{
    const SourceLimit = 16 * 1024'u64
    const MaxColumns  = 5'u64
    const MaxRows     = 5'u64
    const Margin      = 8.0

    let width  = cast(s32, Math.max(Math.min(maxSide, 256'u32), 64'u32))
    let height = Math.max(width * 3 / 4, 64)
    var canvas = try ImageCanvas.create(width, height)
    canvas.clear(Color.fromRgb(248, 249, 250))

    var stream = catch File.openReadLive(fileName) { return {} }
    let sample = catch stream.readUtf8Chunk(SourceLimit) { return {} }
    let model  = catch parseDocument(sample.toString(), detectDelimiter(fileName, sample.toString())) { return {} }
    if model.columns.isEmpty() do
        return try canvas.toImage()

    let columns     = Math.min(model.columns.count, MaxColumns)
    let shownRows   = Math.min(model.rows.count, MaxRows)
    let left        = Margin
    let top         = Margin
    let tableWidth  = cast(f32, width) - Margin * 2
    let rowHeight   = cast(f32, height - cast(s32, Margin * 2)) / cast(f32, shownRows + 1)
    let columnWidth = tableWidth / cast(f32, columns)
    let painter     = &canvas.painter
    painter.fillRect({left, top, tableWidth, rowHeight}, Color.fromRgb(232, 235, 238))

    let face       = try Gui.embeddedTypeFace(false, .Regular)
    let fonts      = painter.renderer().fontCache()
    let headerFont = fonts.createFont(face, 10, .Bitmap, true)
    let bodyFont   = fonts.createFont(face, 10, .Bitmap, false)
    for rowIndex in 0 to shownRows
    {
        let header = rowIndex == 0
        let y      = top + cast(f32, rowIndex) * rowHeight
        if rowIndex > 0 and rowIndex % 2 == 0 do
            painter.fillRect({left, y, tableWidth, rowHeight}, Color.fromRgb(248, 249, 250))

        for column in columns
        {
            var value = model.columns[column].toString()
            if not header
            {
                let row = &model.rows[rowIndex - 1]
                value = column < row.cells.count ? row.cells[column].toString() : ""
            }

            var text:   RichString = String.from(value)
            var format: RichStringFormat
            format.font.regular = header ? headerFont : bodyFont
            format.palette      = [Color.fromRgb(45, 52, 59), Color.fromRgb(45, 52, 59),
                                   Color.fromRgb(45, 52, 59), Color.fromRgb(45, 52, 59)]
            format.minLineHeight = format.font.regular.height
            format.maxLines      = 1
            format.flags         = .Clip
            painter.drawRichString({left + cast(f32, column) * columnWidth + 3,
                                    y + 2,
                                    Math.max(columnWidth - 6, 1),
                                    Math.max(rowHeight - 4, 1)},
                                   &text,
                                   format)
            painter.fillRect({left + cast(f32, column + 1) * columnWidth - 1, y, 1, rowHeight},
                             Color.fromRgb(224, 227, 230))
        }

        painter.fillRect({left, y + rowHeight - 1, tableWidth, 1}, Color.fromRgb(224, 227, 230))
    }

    return try canvas.toImage()
}

private
{
    const FileLimit      = 32 * 1024 * 1024'u64
    const ColumnLimit    = 256'u64
    const ColumnMinWidth = 96.0
    const ColumnMaxWidth = 320.0
    const CellWidth      = 8.0
}

const CellPreviewBytes = 1024'u64     // Most bytes of one cell handed to the list renderer.

// One record of a table.
struct Row
{
    cells: Array'String
}

impl Row
{
    // Closes the cell being read: its bytes become the next cell of the row, and `cell` is emptied.
    mtd finishCell(cell: *Array'u8)
    {
        .cells.add(cast(string, cell.toSlice()))
        cell.clear()
    }
}

// A parsed delimited-text table: the header row, the records below it, and the delimiter that
// separated them.
struct Document
{
    columns:          Array'String     // Column names, generated for the ones the header leaves empty.
    rows:             Array'Row
    delimiter:        u8
    generatedColumns: Array'u32     // Columns whose name was generated rather than read.
}

impl Document
{
    // Turns the first row into the column names, as wide as the widest row, and names each column
    // the header leaves empty. False when the rows are wider than `ColumnLimit`.
    mtd promoteHeader()->bool
    {
        if .rows.isEmpty() do
            return true

        .columns = #move .rows[0].cells
        .rows.removeAtOrdered(0)

        var count = .columns.count
        for row in .rows do
            count = Math.max(count, row.cells.count)
        if count > ColumnLimit do
            return false

        while .columns.count < count do
            .columns.add({})
        for column, index in .columns where column.isEmpty()
        {
            .columns[index] = Format.toString(texts().ui_Column, index + 1)
            .generatedColumns.add(cast(u32, index))
        }

        return true
    }

    // Closes the cell and the row being read, and appends the row to the document.
    mtd finishRow(row: *Row, cell: *Array'u8)
    {
        row.finishCell(cell)
        .rows.add(#move row[])
        row[] = {}
    }
}

private func loadDocument(fileName: string)->Document fail
{
    let info = try File.info(fileName)
    if info.size > FileLimit do
        fail UnsupportedFormatError{Errors.mkString(texts().err_TooLarge)}

    let source    = try File.readAllText(fileName)
    let delimiter = detectDelimiter(fileName, source)
    return try parseDocument(source, delimiter)
}

// Bounds the text handed to the single-line rich-text renderer. A table keeps the complete cell
// for search, but shaping a megabyte-long CSV field merely to paint its first few glyphs makes
// every virtual-row repaint linear in the hidden tail.
func cellPreviewRange(value: string, focus = Swag.U64.Max)->{ start, end: u64 }
{
    var result: #returntype
    result.end = value.count
    if result.end <= CellPreviewBytes do
        return result

    if focus != Swag.U64.Max and focus < result.end and focus > CellPreviewBytes / 3 do
        result.start = focus - CellPreviewBytes / 3

    while result.start and (value[result.start] & 0xC0) == 0x80 do
        result.start -= 1

    result.end = Math.min(result.start + CellPreviewBytes, value.count)
    while result.end < value.count and (value[result.end] & 0xC0) == 0x80 do
        result.end -= 1
    return result
}

// Parses RFC-4180 quoting and the line-ending forms commonly found in CSV and TSV files.
func parseDocument(text: string, delimiter: u8)->Document fail
{
    var result: #returntype
    result.delimiter = delimiter

    var row:         Row
    var cell:        Array'u8
    var quoted:      bool
    var closedQuote: bool
    var touched:     bool
    var at = 0'u64
    while at < text.count
    {
        let value = text[at]
        if quoted
        {
            if value == '"'
            {
                if at + 1 < text.count and text[at + 1] == '"'
                {
                    cell.add('"'u8)
                    at += 2
                    continue
                }

                quoted      = false
                closedQuote = true
                at          += 1
                continue
            }

            if value == '\r'
            {
                cell.add('\n'u8)
                at += at + 1 < text.count and text[at + 1] == '\n' ? 2 : 1
                continue
            }

            cell.add(value)
            at += 1
            continue
        }

        if value == delimiter
        {
            row.finishCell(&cell)
            touched     = true
            closedQuote = false
            at          += 1
            continue
        }

        if value == '\r' or value == '\n'
        {
            result.finishRow(&row, &cell)
            touched     = false
            closedQuote = false
            at          += value == '\r' and at + 1 < text.count and text[at + 1] == '\n' ? 2 : 1
            continue
        }

        if value == '"' and cell.isEmpty() and not closedQuote
        {
            quoted  = true
            touched = true
            at      += 1
            continue
        }

        // Spaces after a closing quote are presentation whitespace, not part of the field.
        if closedQuote and (value == ' ' or value == '\t')
        {
            at += 1
            continue
        }

        cell.add(value)
        touched     = true
        closedQuote = false
        at          += 1
    }

    if quoted do
        fail InvalidFormatError{Errors.mkString(texts().err_UnclosedQuote)}
    if touched or not cell.isEmpty() or not row.cells.isEmpty() do
        result.finishRow(&row, &cell)
    if not result.promoteHeader() do
        fail UnsupportedFormatError{Errors.mkString(texts().err_TooManyColumns)}
    return result
}

// Counts `delimiter` outside quotes in the first records of `text`, a sample bounded in bytes and records.
private func delimiterCount(text: string, delimiter: u8)->u64
{
    var result: u64
    var quoted: bool
    var at      = 0'u64
    var records = 0'u32
    while at < text.count and at < 16 * 1024 and records < 8
    {
        let value = text[at]
        if value == '"'
        {
            if quoted and at + 1 < text.count and text[at + 1] == '"'
            {
                at += 2
            }
            else
            {
                quoted = not quoted
                at     += 1
            }

            continue
        }

        if not quoted and value == delimiter do
            result += 1
        if not quoted and (value == '\r' or value == '\n')
        {
            records += 1
            if value == '\r' and at + 1 < text.count and text[at + 1] == '\n' do
                at += 2
            else do
                at += 1
            continue
        }

        at += 1
    }

    return result
}

// Chooses the strongest delimiter in the first records; a TSV extension remains unambiguous.
func detectDelimiter(fileName, text: string)->u8
{
    let extension = Path.lowercaseExtension(fileName)
    if extension == ".tsv" or extension == ".tab" do
        return '\t'

    const Candidates: [4] u8 = [','u8, ';'u8, '\t'u8, '|'u8]
    var result = ','u8
    var best: u64
    for candidate in Candidates
    {
        let count = delimiterCount(text, candidate)
        if count > best
        {
            best   = count
            result = candidate
        }
    }

    return result
}

// The air between the table and the edges of the window, as the columns fit their content.
const PageMargin = 112.0

// What the values of one column add up to: how many cells are empty and, over those reading as
// quantities, their range and their sum.
struct ColumnProfile
{
    empty:        u64
    inconsistent: u64
    quantities:   u64
    minimum:      f64
    maximum:      f64
    sum:          f64
}

// The most columns the information sheet profiles; a wider table names how many it leaves out.
const ProfiledColumnLimit = 48'u64

// Names the kind of values of a column, as its header writes it under its name.
func kindName(kind: ColumnKind)->string
{
    switch #complete kind
    {
    case .Text:    return texts().ui_KindText
    case .Integer: return texts().ui_KindInteger
    case .Decimal: return texts().ui_KindDecimal
    case .Date:    return texts().ui_KindDate
    }
}

// Reports whether commas before the decimal point group thousands in three-digit blocks.
func isThousands(text: string)->bool
{
    var decimalPoint = false
    for byte, at in text
    {
        if byte == '.' do
            decimalPoint = true
        if byte != ',' do
            continue
        if decimalPoint do
            return false

        var digits = 0'u64
        var next   = at + 1
        while next < text.count and Latin1.isDigit(text[next])
        {
            digits += 1
            next   += 1
        }

        if digits != 3 do
            return false
    }

    return true
}

// Writes `value` with its thousands grouped by a narrow space, rounded to two decimals when
// `decimal` and to a whole number otherwise.
func groupThousands(value: f64, decimal: bool)->String
{
    // Cents are rounded before the whole part is taken, so 1.999 reads 2.00 rather than 1.100. A
    // value that rounds to nothing has no sign: -0.001 reads 0.00, not -0.00.
    let cents    = cast(u64, Math.round(Math.abs(value) * 100))
    let whole    = decimal ? cents / 100 : cast(u64, Math.round(Math.abs(value)))
    let negative = value < 0 and (decimal ? cents : whole) != 0
    var digits   = Format.toString("%", whole)
    var result: String
    for byte, at in digits.toString()
    {
        if at and (digits.length - at) % 3 == 0 do
            result += " "
        result += cast(rune, byte)
    }

    if decimal do
        result += Format.toString(".%{02}", cents % 100)

    return negative ? Format.toString("-%", result) : result
}

// Names the kind of delimited text that `delimiter` separates. Comma- and tab-separated text keep
// the format names every language uses; the other delimiters are described.
func delimiterKind(delimiter: u8)->string
{
    switch delimiter
    {
    case '\t': return "TSV"
    case ';':  return texts().ui_SemicolonKind
    case '|':  return texts().ui_PipeKind
    default:   return "CSV"
    }
}

// Reports whether `text` reads as a quantity: digits, with signs, separators, and a percent sign
// as the only other characters.
func isNumericCell(text: string)->bool
{
    var digits = false
    for byte in text
    {
        if byte >= '0' and byte <= '9' do
            digits = true
        elif byte != '+' and byte != '-' and byte != '.' and byte != ',' and byte != '%' and byte != ' ' do
            return false
    }

    return digits
}

// Reads the quantity `text` spells into `result`, and reports whether it spells one. Spaces and a
// percent sign are dropped; a comma is a thousands separator beside a decimal point or before a
// group of three digits, and a decimal comma otherwise.
func quantityOf(text: string, result: *f64)->bool
{
    var hasDot, commas, digitsAfterComma: u64
    var dropped = false
    for byte in text
    {
        if byte == '.'
        {
            hasDot += 1
        }
        elif byte == ','
        {
            commas += 1
            digitsAfterComma = 0
        }
        elif byte >= '0' and byte <= '9'
        {
            digitsAfterComma += 1
        }
        elif byte == ' ' or byte == '%'
        {
            dropped = true
        }
    }

    // Sorting, summing and profiling read every cell of a column: a quantity written plainly is
    // read where it stands rather than copied first.
    if not commas and not dropped
    {
        let value = catch StrConv.toF64(text) { return false }
        result[] = value
        return true
    }

    let decimalComma = not hasDot and commas == 1 and digitsAfterComma != 3
    if commas and not decimalComma and not isThousands(text) do
        return false

    var clean: String
    for byte in text
    {
        if byte == ' ' or byte == '%' do
            continue
        if byte == ','
        {
            if decimalComma do
                clean += '.'
            continue
        }

        clean += cast(rune, byte)
    }

    let value = catch StrConv.toF64(clean.toString()) { return false }
    result[] = value
    return true
}

// What one row is ordered by when its table is sorted on a column.
private struct SortKey
{
    row:      u32
    numeric:  bool
    quantity: f64
    text:     string
}

// Compares the selected value in the requested direction while keeping equal rows in file order.
private func compareSortKeys(a, b: SortKey, descending: bool)->s32
{
    var order: s32
    if a.numeric
    {
        order = descending ? (b.quantity <=> a.quantity) : (a.quantity <=> b.quantity)
        if not order do
            order = descending ? Text.compareNames(b.text, a.text) : Text.compareNames(a.text, b.text)
    }
    else
    {
        order = descending ? Text.compareNames(b.text, a.text) : Text.compareNames(a.text, b.text)
    }

    return order != 0 ? order : a.row <=> b.row
}

private func countText(count: u64, one, many: string)->String
{
    if count == 1 do
        return one
    return Format.toString(many, count)
}

// What the values of a column read as, written under its name.
enum ColumnKind
{
    Text
    Integer
    Decimal
    Date
}

// Reports whether `text` begins with a valid year-first date, optionally followed by a timestamp.
func isDateCell(text: string)->bool
{
    if text.count < 10 do
        return false
    if text[4] != '-' and text[4] != '/' do
        return false
    if text[7] != text[4] do
        return false
    for at in 4 where not Latin1.isDigit(text[at]) do
        return false
    if text.count > 10 and text[10] != 'T' and text[10] != ' ' do
        return false

    let month = cast(u32, (text[5] - '0') * 10 + (text[6] - '0'))
    let day   = cast(u32, (text[8] - '0') * 10 + (text[9] - '0'))
    var year: u32
    for at in 4 do
        year = year * 10 + cast(u32, text[at] - '0')
    for at in 5 until 7 where not Latin1.isDigit(text[at]) do
        return false
    for at in 8 until 10 where not Latin1.isDigit(text[at]) do
        return false

    var daysInMonth = 31'u32
    switch month
    {
    case 2: daysInMonth = year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) ? 29 : 28
    case 4, 6, 9, 11: daysInMonth = 30
    }

    return month >= 1 and month <= 12 and day >= 1 and day <= daysInMonth
}

// Returns a sortable YYYYMMDD key for a valid year-first date or timestamp.
private func dateKey(text: string)->u32
{
    if not isDateCell(text) do
        return Swag.U32.Max

    var year: u32
    for at in 4 do
        year = year * 10 + cast(u32, text[at] - '0')
    let month = cast(u32, (text[5] - '0') * 10 + (text[6] - '0'))
    let day   = cast(u32, (text[8] - '0') * 10 + (text[9] - '0'))
    return year * 10_000 + month * 100 + day
}

// The table viewer: rows under each column's name and kind, quantities aligned on the right,
// and search matches highlighted in place. File and selection facts use the host's reading line.
struct Panel
{
    using wnd: Wnd

    late list: *ListCtrl

    kinds:    Array'ColumnKind
    profiles: Array'ColumnProfile     // What each column holds, counted the first time the sheet asks.
    built:    bool     // Whether the parts exist: a resize reaches the panel while it is built.

    document:      Document
    numeric:       Array'bool
    order:         Array'u32     // Document row shown at each line, in the sorted order.
    rowLines:      Array'u32     // Line each document row is shown at.
    sortColumn:    u32 = Swag.U32.Max
    descending:    bool
    searchRow:     u64 = Swag.U64.Max
    searchColumn:  u64
    searchOffset:  u64
    searchLength:  u64
    load:          Viewer.BackgroundLoad'Document
    services:      Viewer.HostServices
    failureReason: String

    // The sum the foot shows and the column it adds up. Moving the focus renames the row in the
    // foot but leaves the sum alone, so the column is added up again only when it changes.
    footSum:       String
    footSumColumn: u64 = Swag.U64.Max
}

private impl IWnd for Panel
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .built do
            .fitWidth()
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged and not .load.isPending() and .failureReason.isEmpty()
        {
            .refreshColumnNames()
            .refreshDetails()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .load.claim(evt)
        {
            evt.accepted = false
            return
        }

        .failureReason = .load.finish(&.document)
        if not .failureReason.isEmpty()
        {
            .services.failed(me, .failureReason)
            return
        }

        .publishDocument()
        .services.loadingChanged(me)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed and evt.modifiers == .Control and evt.key == .C do
            Clipboard.setString(.selectionText())
        else do
            evt.accepted = false
    }
}

private impl Panel
{
    mtd refreshColumnNames()
    {
        for index in .document.generatedColumns
        {
            .document.columns[index] = Format.toString(texts().ui_Column, index + 1)
            if index < .list.header.items.count do
                .list.header.items[index]!.name.set(.document.columns[index])
        }

        .list.header.invalidate()
    }

    // Creates the columns, each sized from its name and the first 128 rows, then shows the rows
    // virtually. A column whose values all read as quantities is aligned on the right, where
    // their digits line up the way a reader compares them.
    mtd publishDocument()
    {
        .refreshColumnNames()
        for column, index in .document.columns
        {
            var longest = column.length
            var numeric = false
            var textual = false
            for row in .document.rows.toSlice()[until Math.min(.document.rows.count, 128)] where index < row.cells.count
            {
                let cell = row.cells[index].toString()
                longest = Math.max(longest, row.cells[index].length)
                if isNumericCell(cell) do
                    numeric = true
                elif cell.count do
                    textual = true
            }

            // Year-first dates can contain only digits and dashes, so recognize a complete date
            // column before treating its punctuation as a numeric sign.
            var kind     = ColumnKind.Text
            var hasDates = false
            var dates    = true
            for row in .document.rows.toSlice()[until Math.min(.document.rows.count, 128)] where index < row.cells.count and row.cells[index].length
            {
                hasDates = true
                if not isDateCell(row.cells[index].toString()) do
                    dates = false
            }

            if hasDates and dates
            {
                kind = .Date
            }
            elif numeric and not textual
            {
                kind = .Integer
                for row in .document.rows.toSlice()[until Math.min(.document.rows.count, 128)] where index < row.cells.count
                {
                    let cell = row.cells[index].toString()
                    if Utf8.contains(cell, ".") or (Utf8.contains(cell, ",") and not isThousands(cell)) do
                        kind = .Decimal
                }
            }

            .numeric.add(numeric and not textual and kind != .Date)
            .kinds.add(kind)
            let width = Math.clamp(cast(f32, longest) * CellWidth + 32, ColumnMinWidth, ColumnMaxWidth)
            let range = cellPreviewRange(column.toString())
            let align = numeric and not textual and kind != .Date ? StringHorzAlignment.Right : StringHorzAlignment.Left
            let item  = .list.header.addColumn(column.toString()[range.start until range.end], width, {}, align)
            item.detail = kindName(kind)
        }

        .list.header.fitHeight()

        .order.clear()
        .rowLines.clear()
        .footSumColumn = Swag.U64.Max
        .list.setVirtualCount(cast(u32, .document.rows.count))
        .applyLayout()
        .fitWidth()

        .refreshDetails()
    }

    // Keeps the table as wide as its columns, its hairlines ending with its last column, and the
    // words of its first column on the page margin. The row ground extends by its own inset.
    mtd fitWidth()
    {
        if .list.header.items.isEmpty() do
            return
        // Keep the broad reading margin when the columns fit. A narrow cell spends its width on data.
        let inset  = .themeMetrics().floating_Inset
        let spare  = .clientRect().width - .list.header.contentWidth()
        let margin = Math.clamp(Math.floor(spare / 2), inset, PageMargin)
        if .padding.x != margin
        {
            .padding.x = margin
            .padding.z = margin
            .applyLayout()
        }

        let textLeft = .list.header.surfaceRect().x + .list.header.itemPositionForColumn(0) + .list.header.itemPadding
        let delta    = Math.round(textLeft - .localToSurface(Math.Point{.padding.x, 0}).x)
        if delta != 0
        {
            .list.margin.x -= delta
            .applyLayout()
        }

        let room = .clientRect().width - .padding.x - .padding.z - .list.margin.x
        let used = .list.header.contentWidth() + 8
        let rest = Math.max(room - used, 0)
        if .list.margin.z == rest do
            return
        .list.margin.z = rest
        .applyLayout()
    }

    // Returns the column whose values the foot sums: the one the table is sorted on when it holds
    // quantities, the first one holding them otherwise.
    mtd sumColumn()->u64
    {
        if .sortColumn < .numeric.count and .numeric[.sortColumn] do
            return .sortColumn
        for numeric, column in .numeric where numeric do
            return column
        return Swag.U64.Max
    }

    // Writes the sum of the quantities of `column`, grouped by thousands.
    mtd sumText(column: u64)->String
    {
        var total   = 0.0'f64
        var decimal = false
        for row in .document.rows where column < row.cells.count
        {
            var value: f64
            if quantityOf(row.cells[column].toString(), &value) do
                total += value
        }

        if column < .kinds.count do
            decimal = .kinds[column] == .Decimal
        return groupThousands(total, decimal)
    }

    // Returns the selected rows, or the focused one, as tab-separated text in the order on screen,
    // after the column names with `withNames`. A value holding a tab, a line break or a quote is
    // quoted, its quotes doubled, as spreadsheets read tab-separated text back.
    internal mtd selectionText(withNames = false)->String
    {
        func quoted(value: string)->String
        {
            var needed = false
            for c in value where c == '\t' or c == '\n' or c == '\r' or c == '"' do
                needed = true
            if not needed do
                return String.from(value)

            var escaped = String.from(value)
            escaped.replace('"', "\"\"")
            return Format.toString("\"%\"", escaped)
        }

        var result: #returntype
        if withNames
        {
            for name, column in .document.columns
            {
                if column do
                    result += "\t"
                result += quoted(name.toString())
            }

            result += "\n"
        }

        let anySelected = .list.selectedLineCount() != 0
        for line in .document.rows.count
        {
            let selected = anySelected ? .list.isLineSelected(cast(u32, line)) : line == .list.focusIndex
            if not selected do
                continue
            let row = &.document.rows[.documentRow(line)]
            for cell, column in row.cells
            {
                if column do
                    result += "\t"
                result += quoted(cell.toString())
            }

            result += "\n"
        }

        return result
    }

    // Returns the document row shown at line `index`.
    mtd documentRow(index: u64)->u64 => .order.count ? .order[index] : index

    // Returns the values of `column`, one per line in the order shown, an empty cell as an empty line.
    internal mtd columnText(column: u64)->String
    {
        var result: String
        for line in .document.rows.count
        {
            if line do
                result += "\n"
            let row = &.document.rows[.documentRow(line)]
            if column < row.cells.count do
                result += row.cells[column]
        }

        return result
    }

    // Returns the line document row `row` is shown at.
    internal mtd lineOfRow(row: u64)->u32 => .rowLines.count ? .rowLines[row] : cast(u32, row)

    // Orders the rows by `column`, ascending first and descending when the same column is chosen
    // again. Quantities compare as numbers and words in natural order; empty cells stay last
    // either way, and equal cells keep the order of the file.
    internal mtd sortBy(column: u32)
    {
        if column >= .document.columns.count do
            return
        .descending = .sortColumn == column and not .descending
        .sortColumn = column

        // The keyboard stays on the row it was on, wherever the order moves it.
        let focused = .list.focusIndex < .document.rows.count ? .documentRow(.list.focusIndex) : Swag.U64.Max

        let numeric      = column < .numeric.count and .numeric[column]
        let isDateColumn = column < .kinds.count and .kinds[column] == .Date
        var keys:  Array'SortKey
        var empty: Array'u32
        let descending   = .descending
        for row, index in .document.rows
        {
            let text = column < row.cells.count ? row.cells[column].toString() : ""
            var key  = SortKey{row: cast(u32, index), numeric: numeric, text: text}
            if isDateColumn and text.count
            {
                key.numeric  = true
                key.quantity = cast(f64, dateKey(text))
            }

            if text.count == 0 or
               (isDateColumn and key.quantity == cast(f64, Swag.U32.Max)) or
               (numeric and not quantityOf(text, &key.quantity)) do
                empty.add(key.row)
            else do
                keys.add(key)
        }

        keys.sort(func|descending|(a, b)->s32
        {
            return compareSortKeys(a, b, descending)
        })

        .order.clear()
        .rowLines.resize(.document.rows.count)
        for key in keys do
            .order.add(key.row)
        for row in empty do
            .order.add(row)
        for row, line in .order do
            .rowLines[row] = cast(u32, line)

        .list.header.setSortIndicator(column, .descending ? .Descending : .Ascending)
        .list.unselectAll()
        if focused != Swag.U64.Max do
            .list.setFocusedIndex(.lineOfRow(focused))
        .list.invalidate()

        // The focused row now stands on another line, and the foot sums the sorted column.
        .refreshDetails()
    }

    // Reports structure, selected row and numeric summary together on the host's reading line.
    mtd refreshDetails()
    {
        let rows    = countText(.document.rows.count, texts().ui_Row, texts().ui_Rows)
        let columns = countText(.document.columns.count, texts().ui_OneColumn, texts().ui_Columns)
        var foot = Format.toString("% · % · % · UTF-8", rows, columns, delimiterKind(.document.delimiter))
        if .list.focusIndex < .document.rows.count
        {
            let row = &.document.rows[.documentRow(.list.focusIndex)]
            foot = Format.toString("% · %", foot, Format.toString(texts().ui_RowAt, .list.focusIndex + 1))
            if row.cells.count and row.cells[0].length do
                foot = Format.toString("% · %", foot, row.cells[0].toString())
        }

        let column = .sumColumn()
        if column != Swag.U64.Max and column < .document.columns.count
        {
            if .footSumColumn != column
            {
                .footSum       = .sumText(column)
                .footSumColumn = column
            }

            let sum = Format.toString("Σ % %", .document.columns[column].toString(), .footSum)
            foot = foot.isEmpty() ? sum : Format.toString("% · %", foot, sum)
        }

        .services.showDetails(me, foot)
    }

    internal mtd retire()->bool
    {
        return .load.retire()
    }

    // Fills list line `index` with previews of the row's cells. The cell holding the current search
    // hit is highlighted, with the match in bold and the preview window moved to show it.
    internal mtd fillLine(line: *ListLine, index: u32)
    {
        if index >= .document.rows.count do
            return
        let rowIndex = .documentRow(index)
        let row      = &.document.rows[rowIndex]
        for column in .document.columns.count
        {
            let value = column < row.cells.count ? row.cells[column].toString() : ""
            let range = cellPreviewRange(value, rowIndex == .searchRow and column == .searchColumn ? .searchOffset : Swag.U64.Max)
            let item  = line.setItem(cast(u32, column), value[range.start until range.end])
            if column < .numeric.count and .numeric[column]
            {
                item.horzAlign = .Right
                item.mono      = true
            }

            if rowIndex == .searchRow and column == .searchColumn
            {
                item.colorBk = .themeColors().edit_SelectedBk
                item.colorFg = .themeColors().label_Text
                if .searchLength and Viewer.isByteRangeInBounds(value.count, .searchOffset, .searchLength)
                {
                    let markedStart = Math.max(.searchOffset, range.start)
                    let markedEnd   = Math.min(.searchOffset + .searchLength, range.end)
                    if markedStart < markedEnd
                    {
                        // The cell is data, set literally; the match is its bold run.
                        with item.name
                        {
                            .clear()
                            if range.start do
                                .append("\u2026")
                            .append(value[range.start until markedStart])
                            .append(value[markedStart until markedEnd], {bold: true})
                            .append(value[markedEnd until range.end])
                            if range.end < value.count do
                                .append("\u2026")
                        }
                    }
                }
            }
        }
    }

    // Builds the panel both table entry points share: a virtual multi-column list whose lines are
    // filled on demand from the document.
    func createBase(parent: *Wnd)->*Panel
    {
        registerTexts(parent.app())
        let result = Wnd.create'Panel(parent, "scope.table")
        result.backgroundStyle = .View
        result.padding         = Math.Vector4{PageMargin, 24, PageMargin, 0}

        with result.list = ListCtrl.createMultiColumns(result)
        {
            .dockStyle = .Center
            .setSelectionMode(.Multi)
            .setFirstColumnIconMargin(false)
            .updateFlags(.HotTrack | .HorizontalLines | .Ellipsis)
            .header.form       = .Transparent
            .onFillVirtualLine = &fillVirtualLine

            // The name of a column is the text ink in bold over its kind in faint mono.
            .header.style.setFont(result.theme().createDefaultFont(result.themeMetrics().defaultFontSize, .Bold), .Regular)
            .header.style.addStyleSheetColors("headerItem_Text $label_Text")
            .header.sigColumnClicked += func|result|(_, column) { result.sortBy(column) }
            .sigSelectionChanged     += func|result|(_) { result.refreshDetails() }
        }

        result.built = true
        result.applyLayout()
        return result
    }
}

// These operations let another format supply an already parsed table while preserving the same
// virtual rows, matching, and highlighted result behavior as CSV and TSV files.
impl Panel
{
    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        var matcher = catch Viewer.createNameMatcher(text, options) { return; }
        for row, rowIndex in .document.rows
        {
            for cell, column in row.cells do
                Viewer.collectTextMatches(cell.toString(), &matcher, rowIndex, column, 0, result)
        }
    }

    mtd revealMatch(match: Viewer.SearchMatch, _: string)->bool
    {
        if match.major >= .document.rows.count or match.minor >= .document.rows[match.major].cells.count do
            return false

        .searchRow    = match.major
        .searchColumn = match.minor
        .searchOffset = match.offset
        .searchLength = match.length
        .list.unselectAll()
        .list.setFocusedIndex(.lineOfRow(match.major))
        .list.invalidate()
        return true
    }

    // A cell shows a window of its value, with an ellipsis on each side it had to cut, so the
    // mark is placed in the text the reader can actually see rather than in the stored value.
    mtd searchBounds(result: *Math.Rectangle)->bool
    {
        if .searchRow >= .document.rows.count or .searchColumn >= .document.rows[.searchRow].cells.count do
            return false

        let value = .document.rows[.searchRow].cells[.searchColumn].toString()
        if not Viewer.isByteRangeInBounds(value.count, .searchOffset, .searchLength) do
            return false

        let range       = cellPreviewRange(value, .searchOffset)
        let markedStart = Math.max(.searchOffset, range.start)
        let markedEnd   = Math.min(.searchOffset + .searchLength, range.end)
        if markedEnd <= markedStart do
            return false

        var shown: String
        if range.start do
            shown += "\u2026"
        let lead = shown.length
        shown += value[range.start until range.end]
        return Viewer.listCellMatchBounds(.list, .lineOfRow(.searchRow), cast(u32, .searchColumn), shown, lead + markedStart - range.start, markedEnd - markedStart, result)
    }

    // Moves the keyboard focus to row `line` as the table shows it, the one the row readout names,
    // and brings it into view.
    internal mtd revealLine(line: u32)
    {
        if line >= .document.rows.count do
            return
        .list.unselectAll()
        .list.setFocusedIndex(line)
        .refreshDetails()
    }

    // Answers `:` and a number in the lens with that row of the table, counted as the row readout
    // counts it: from one, in the order on screen. Any other query is answered with the copy
    // commands.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        if entries.results.prefix != .Line
        {
            let empty = not .document.rows.count
            entries.add(texts().ui_CopyRows, .Copy, func|view = me|() { Clipboard.setString(view.selectionText()) }, disabled: empty, defaultKey: {modifiers: .Control, key: .C}, bindId: "scope.table.copyRows")
            entries.add(texts().ui_CopyRowsNames, .Copy, func|view = me|() { Clipboard.setString(view.selectionText(withNames: true)) }, disabled: empty, bindId: "scope.table.copyRowsNames")

            // The column the table is sorted on, its values one per line in the order shown.
            if .sortColumn < .document.columns.count do
                entries.add(Format.toString(texts().ui_CopyColumn, .document.columns[.sortColumn]), .Copy, func|view = me|() { Clipboard.setString(view.columnText(view.sortColumn)) }, bindId: "scope.table.copyColumn")
            return
        }

        let query = Latin1.trim(entries.query.toString())
        if not query.count do
            return
        for c in query where not Latin1.isDigit(c) do
            return
        let row = catch StrConv.toU64(query) { return; }
        if not row or row > .document.rows.count do
            return

        let entry = entries.add(Format.toString(texts().ui_GoToRow, row), .GoTo, func|view = me, row|() { view.revealLine(cast(u32, row - 1)) })
        if entry do
            entry.lead = Format.toString("%", row)
    }

    mtd clearSearch()
    {
        .searchRow    = Swag.U64.Max
        .searchColumn = 0
        .searchOffset = 0
        .searchLength = 0
        .list.unselectAll()
        .list.invalidate()
    }

    func create(parent: *Wnd, fileName: string, services: Viewer.HostServices)->*Panel
    {
        with let result = Panel.createBase(parent)
        {
            .services = services
            .load.start(fileName, &loadDocument, result)
        }

        return result
    }

    // Hosts a table decoded by another reader without introducing a temporary CSV file.
    func createDocument(parent: *Wnd, document: #move Document)->*Panel
    {
        with let result = Panel.createBase(parent)
        {
            .document = #move document
            .publishDocument()
        }

        return result
    }
}

private func fillVirtualLine(list: *ListCtrl, line: *ListLine?, index: u32)
{
    if line == null do
        return
    assume cast(*Panel, list.parent).fillLine(line, index)
}

// What the information sheet says of a table and of each of its columns.
impl Panel
{
    // Describes the table in the information sheet: its rows and columns, then how they are
    // separated and encoded.
    mtd describeInformation(sheet: *InfoSheet)
    {
        var data: MediaInfoData
        data.addFigure(.Custom, countText(.document.rows.count, texts().ui_Row, texts().ui_Rows))
        data.addFigure(.Custom, countText(.document.columns.count, texts().ui_OneColumn, texts().ui_Columns))
        data.add(.Table, group: true)
        data.add(.Separator, delimiterKind(.document.delimiter))
        data.add(.Encoding, "UTF-8")

        // Each column under its name: its kind, the range and mean of its quantities, its empty cells.
        let shown = Math.min(.document.columns.count, ProfiledColumnLimit)
        if shown and .kinds.count >= shown
        {
            .profileColumns()
            data.add(.Columns, group: true)
            for column in shown do
                data.addText(.document.columns[column], .profileText(column))
            if .document.columns.count > shown do
                data.addText("…", Format.toString(texts().ui_MoreColumns, .document.columns.count - shown))
        }

        data.describe(sheet)
    }

    // Counts what each profiled column holds, once.
    mtd profileColumns()
    {
        let shown = Math.min(.document.columns.count, ProfiledColumnLimit)
        if .profiles.count == shown do
            return
        .profiles.clear()
        .profiles.resize(shown)
        for &row in .document.rows
        {
            for column in shown
            {
                let profile = &.profiles[column]
                let text    = column < row.cells.count ? Latin1.trim(row.cells[column].toString()) : ""
                if not text.count
                {
                    profile.empty += 1
                    continue
                }

                if column < .kinds.count
                {
                    let kind = .kinds[column]
                    var value: f64
                    if (kind == .Integer and
                        (not quantityOf(text, &value) or
                         Utf8.contains(text, ".") or
                         (Utf8.contains(text, ",") and not isThousands(text)))) or
                       (kind == .Decimal and not quantityOf(text, &value)) or
                       (kind == .Date and not isDateCell(text))
                        do
                        profile.inconsistent += 1
                }

                var value: f64
                if column < .numeric.count and .numeric[column] and quantityOf(text, &value)
                {
                    profile.minimum    = profile.quantities ? Math.min(profile.minimum, value) : value
                    profile.maximum    = profile.quantities ? Math.max(profile.maximum, value) : value
                    profile.sum        += value
                    profile.quantities += 1
                }
            }
        }
    }

    // Describes one profiled column: its kind, then the range and the mean of its quantities, then
    // its empty cells.
    mtd profileText(column: u64)->String
    {
        let profile = &.profiles[column]
        var result  = String.from(kindName(.kinds[column]))
        if profile.quantities
        {
            let decimal = .kinds[column] == .Decimal
            result += Format.toString(" · %", Format.toString(texts().ui_Range, groupThousands(profile.minimum, decimal), groupThousands(profile.maximum, decimal)))
            result += Format.toString(" · %", Format.toString(texts().ui_Mean, groupThousands(profile.sum / cast(f64, profile.quantities), true)))
        }

        if profile.empty do
            result += Format.toString(" · %", Format.toString(texts().ui_Empty, profile.empty))
        if profile.inconsistent do
            result += Format.toString(" · %", Format.toString(texts().ui_Inconsistent, profile.inconsistent))
        return result
    }
}

func createViewer(host: Viewer.Host)
{
    let services = host.services()
    let view     = Panel.create(host.contentParent(), host.fileName(), services)
    host.attachView(view)

    host.setSearch(Viewer.searchApi(view))
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })

    host.setLifecycle(Viewer.loadLifecycle(view))
}
