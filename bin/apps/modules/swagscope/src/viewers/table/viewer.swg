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
        .textual      = true
        .smokeFixture = "viewer.csv"
        .addSelectors(".csv;.tsv;.tab")
    }

    return result
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

// The air between the table and the edges of the window, and the height of its title and facts.
const PageMargin = 112.0
const HeadHeight = 72.0

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

// Reports whether the commas of `text` only group its thousands: each followed by three digits.
func isThousands(text: string)->bool
{
    for byte, at in text where byte == ','
    {
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

// Writes `value` with its thousands grouped by a narrow space, two decimals when `decimal`.
func groupThousands(value: f64, decimal: bool)->String
{
    let negative = value < 0
    let whole    = cast(u64, Math.abs(value))
    var digits   = Format.toString("%", whole)
    var result: String
    for byte, at in digits.toString()
    {
        if at and (digits.length - at) % 3 == 0 do
            result += " "
        result += cast(rune, byte)
    }

    if decimal
    {
        let cents = cast(u64, Math.round((Math.abs(value) - cast(f64, whole)) * 100))
        result += Format.toString(".%{02}", cents)
    }

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
    }

    let decimalComma = not hasDot and commas == 1 and digitsAfterComma != 3
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

// Reports whether `text` is a date written year first: four digits, a dash or a slash, then more.
func isDateCell(text: string)->bool
{
    if text.count < 8 do
        return false
    for at in 4 where not Latin1.isDigit(text[at]) do
        return false
    return text[4] == '-' or text[4] == '/'
}

// The table viewer: the file as a page — its name as the title over a mono line of what it holds,
// then its rows under the name and the kind of each column, numbers in mono on the right, a
// hairline between two rows — and where the current search match lies.
struct Panel
{
    using wnd: Wnd

    late
    {
        list:  *ListCtrl
        head:  *Wnd
        title: *Label
        facts: *Label
    }

    fileName:      String
    kinds:         Array'ColumnKind
    built:         bool     // Whether the parts exist: a resize reaches the panel while it is built.

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
            Clipboard.addString(.selectionText())
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

            .numeric.add(numeric and not textual)

            // The kind of a column, from its first rows: dates, whole numbers, decimals or words.
            var kind = ColumnKind.Text
            if numeric and not textual
            {
                kind = .Integer
                for row in .document.rows.toSlice()[until Math.min(.document.rows.count, 128)] where index < row.cells.count
                {
                    let cell = row.cells[index].toString()
                    if Utf8.contains(cell, ".") or (Utf8.contains(cell, ",") and not isThousands(cell)) do
                        kind = .Decimal
                }
            }
            elif textual
            {
                var dates = true
                for row in .document.rows.toSlice()[until Math.min(.document.rows.count, 128)] where index < row.cells.count and row.cells[index].length
                {
                    if not isDateCell(row.cells[index].toString()) do
                        dates = false
                }

                if dates do
                    kind = .Date
            }

            .kinds.add(kind)
            let width = Math.clamp(cast(f32, longest) * CellWidth + 32, ColumnMinWidth, ColumnMaxWidth)
            let range = cellPreviewRange(column.toString())
            let align = numeric and not textual ? StringHorzAlignment.Right : StringHorzAlignment.Left
            let item  = .list.header.addColumn(column.toString()[range.start until range.end], width, {}, align)
            item.detail = kindName(kind)
        }

        .list.header.fitHeight()
        .title.setText(Path.fileName(.fileName) orelse "")
        .title.show(.fileName.length != 0)

        .order.clear()
        .rowLines.clear()
        .list.setVirtualCount(cast(u32, .document.rows.count))
        .applyLayout()
        .fitWidth()
        .setInitialFocus(.list)

        .refreshDetails()
    }

    // Keeps the table as wide as its columns, its hairlines ending with its last column.
    mtd fitWidth()
    {
        let room = .clientRect().width - .padding.x - .padding.z
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

    // Returns the selected lines, or the focused one when none is selected, as a spreadsheet pastes
    // them: complete cell values separated by tabs, one row per line, in the order shown.
    internal mtd selectionText()->String
    {
        var result: #returntype
        let anySelected = .hasSelection()
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
                result += cell.toString()
            }

            result += "\n"
        }

        return result
    }

    mtd hasSelection()->bool
    {
        for line in .document.rows.count where .list.isLineSelected(cast(u32, line)) do
            return true
        return false
    }

    // Returns the document row shown at line `index`, and the line document row `row` is shown at.
    mtd documentRow(index: u64)->u64      => .order.count ? .order[index] : index
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

        let numeric = column < .numeric.count and .numeric[column]
        var keys:  Array'SortKey
        var empty: Array'u32
        for row, index in .document.rows
        {
            let text = column < row.cells.count ? row.cells[column].toString() : ""
            var key  = SortKey{row: cast(u32, index), numeric: numeric, text: text}
            if text.count == 0 or (numeric and not quantityOf(text, &key.quantity)) do
                empty.add(key.row)
            else do
                keys.add(key)
        }

        keys.sort(func(a, b)->s32
        {
            let order = a.numeric ? (a.quantity <=> b.quantity) : Latin1.compareNatural(a.text, b.text)
            return order != 0 ? order : a.row <=> b.row
        })

        .order.clear()
        .rowLines.resize(.document.rows.count)
        for index in keys.count do
            .order.add(keys[.descending ? keys.count - 1 - index : index].row)
        for row in empty do
            .order.add(row)
        for row, line in .order do
            .rowLines[row] = cast(u32, line)

        .list.header.setSortIndicator(column, .descending ? .Descending : .Ascending)
        .list.unselectAll()
        if focused != Swag.U64.Max do
            .list.setFocusedIndex(.lineOfRow(focused))
        .list.invalidate()
    }

    // Writes what the table holds under its title, and at the foot the row the keyboard is on
    // and the sum of the column of quantities.
    mtd refreshDetails()
    {
        let rows    = countText(.document.rows.count, texts().ui_Row, texts().ui_Rows)
        let columns = countText(.document.columns.count, texts().ui_OneColumn, texts().ui_Columns)
        .facts.setText(Format.toString("% · % · % · UTF-8", rows, columns, delimiterKind(.document.delimiter)))

        var foot: String
        if .list.focusIndex < .document.rows.count
        {
            let row = &.document.rows[.documentRow(.list.focusIndex)]
            foot = Format.toString(texts().ui_RowAt, .list.focusIndex + 1)
            if row.cells.count and row.cells[0].length do
                foot = Format.toString("% · %", foot, row.cells[0].toString())
        }
        else
        {
            foot = Format.toString(texts().ui_Details, delimiterKind(.document.delimiter), rows, columns)
        }

        let column = .sumColumn()
        if column != Swag.U64.Max and column < .document.columns.count do
            foot = Format.toString("% · Σ % %", foot, .document.columns[column].toString(), .sumText(column))
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
                    var marked: String
                    if markedStart < markedEnd
                    {
                        if range.start do
                            marked += "\u2026"
                        marked += value[range.start until markedStart]
                        marked += "<b>"
                        marked += value[markedStart until markedEnd]
                        marked += "</b>"
                        marked += value[markedEnd until range.end]
                        if range.end < value.count do
                            marked += "\u2026"
                        item.name = marked.toString()
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

        // The page: the file's name as its title, then a mono line of what it holds.
        with result.head = Wnd.create'Wnd(result, Math.Rectangle{0, 0, 0, HeadHeight})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Transparent
        }

        with result.facts = Label.create(result.head, "", Math.Rectangle{0, 0, 0, 24}, null, .Ellipsis)
        {
            .dockStyle = .Bottom
            .style.setFont(result.theme().createDefaultFontFs(12), .Regular)
            .style.addStyleSheetColors("label_Text $label_TextFaint")
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with result.title = Label.create(result.head, "", {}, null, .Ellipsis)
        {
            .dockStyle = .Center
            .style.setFont(result.theme().createDefaultFont(28, .Bold), .Regular)
            .setTextAlignment(.Left, .Bottom)
            .hide()
        }

        with result.list = ListCtrl.createMultiColumns(result)
        {
            .dockStyle = .Center
            .setSelectionMode(.Multi)
            .setFirstColumnIconMargin(false)
            .updateFlags(.HotTrack | .HorizontalLines | .Ellipsis)
            .header.form             = .Transparent
            .onFillVirtualLine       = &fillVirtualLine

            // The name of a column is the text ink in bold over its kind in faint mono.
            .header.style.setFont(result.theme().createDefaultFont(result.themeMetrics().defaultFontSize, .Bold), .Regular)
            .header.style.addStyleSheetColors("headerItem_Text $label_Text")
            .header.sigColumnClicked += func|result|(_, column) { result.sortBy(column) }
            .sigSelectionChanged     += func|result|(_) { result.refreshDetails() }
        }

        result.built = true
        result.applyLayout()
        result.setInitialFocus(result.list)
        return result
    }
}

// These operations let another format supply an already parsed table while preserving the same
// virtual rows, matching, and highlighted result behavior as CSV and TSV files.
impl Panel
{
    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for row, rowIndex in .document.rows
        {
            for cell, column in row.cells do
                Viewer.collectTextMatches(cell.toString(), text, options, rowIndex, column, 0, result)
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
            .fileName = fileName
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

// Creates the integrated CSV/TSV table view.
func createViewer(host: Viewer.Host)
{
    let services = host.services()
    let view     = Panel.create(host.contentParent(), host.fileName(), services)
    host.attachView(view)

    host.setSearch(Viewer.searchApi(view))

    host.setLifecycle(Viewer.loadLifecycle(view))
}
