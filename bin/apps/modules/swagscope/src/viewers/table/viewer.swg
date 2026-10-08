#global internal
#global namespace Viewers.Table

using Core, Core.Errors, Pixel, Gui

// Describes the delimited-text table viewer to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
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
            .columns.add(String{})
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
    var result: retval
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
    var result: retval
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

private func countText(count: u64, one, many: string)->String
{
    if count == 1 do
        return one
    return Format.toString(many, count)
}

// The table viewer: the parsed table in a virtual list, and where the current search match lies.
struct Panel
{
    using wnd: Wnd

    late list: *ListCtrl

    document:      Document
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
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged and not .load.isPending() and .failureReason.isEmpty()
        {
            .refreshColumnNames()
            .refreshDetails()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .load.timer
        {
            evt.accepted = false
            return
        }

        if not .load.poll() do
            return

        .failureReason = .load.finish(&.document)
        if not .failureReason.isEmpty()
        {
            .services.failed(me, .failureReason)
            return
        }

        .publishDocument()
        .services.loadingChanged(me)
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

    mtd publishDocument()
    {
        .refreshColumnNames()
        for column, index in .document.columns
        {
            var longest = column.length
            for row in .document.rows.toSlice()[until Math.min(.document.rows.count, 128)] where index < row.cells.count do
                longest = Math.max(longest, row.cells[index].length)
            let width = Math.clamp(cast(f32, longest) * CellWidth + 24, ColumnMinWidth, ColumnMaxWidth)
            let range = cellPreviewRange(column.toString())
            .list.addColumn(column.toString()[range.start until range.end], width)
        }

        .list.setVirtualCount(cast(u32, .document.rows.count))
        .applyLayout()
        .setInitialFocus(.list)

        .refreshDetails()
    }

    mtd refreshDetails()
    {
        let rows    = countText(.document.rows.count, texts().ui_Row, texts().ui_Rows)
        let columns = countText(.document.columns.count, texts().ui_OneColumn, texts().ui_Columns)
        let kind    = .document.delimiter == '\t' ? "TSV" : "CSV"
        .services.showDetails(me, Format.toString(texts().ui_Details, kind, rows, columns))
    }

    mtd retire()->bool
    {
        return .load.retire()
    }

    mtd fillLine(line: *ListLine, index: u32)
    {
        if index >= .document.rows.count do
            return
        let row = &.document.rows[index]
        for column in .document.columns.count
        {
            let value = column < row.cells.count ? row.cells[column].toString() : ""
            let range = cellPreviewRange(value, index == .searchRow and column == .searchColumn ? .searchOffset : Swag.U64.Max)
            let item  = line.setItem(cast(u32, column), value[range.start until range.end])
            if index == .searchRow and column == .searchColumn
            {
                item.colorBk = .themeColors().edit_SelectedBk
                item.colorFg = .themeColors().label_Text
                if .searchLength and .searchOffset + .searchLength <= value.count
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

    func createBase(parent: *Wnd)->*Panel
    {
        registerTexts(parent.app())
        let result = Wnd.create'Panel(parent, "scope.table")
        result.backgroundStyle = .View

        with result.list = ListCtrl.createMultiColumns(result)
        {
            .dockStyle = .Center
            .style.setFont(result.theme().createDefaultFontFamilyFs(result.themeMetrics().defaultFixedFontSize))
            .setSelectionMode(.Single)
            .setFirstColumnIconMargin(false)
            .updateFlags(.HotTrack | .AlternateLines | .Ellipsis)
            .header.form       = .Transparent
            .onFillVirtualLine = &fillVirtualLine
        }

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

    mtd revealMatch(match: Viewer.SearchMatch, ?: string)->bool
    {
        if match.major >= .document.rows.count or match.minor >= .document.rows[match.major].cells.count do
            return false

        .searchRow    = match.major
        .searchColumn = match.minor
        .searchOffset = match.offset
        .searchLength = match.length
        .list.unselectAll()
        .list.setFocusedIndex(cast(u32, match.major))
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
        if .searchOffset + .searchLength > value.count do
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
        return Viewer.listCellMatchBounds(.list, cast(u32, .searchRow), cast(u32, .searchColumn), shown, lead + markedStart - range.start, markedEnd - markedStart, result)
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
            .load.startPolled(result, fileName, &loadDocument)
        }

        return result
    }

    // Hosts a table decoded by another reader without introducing a temporary CSV file.
    func createDocument(parent: *Wnd, document: Document)->*Panel
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
