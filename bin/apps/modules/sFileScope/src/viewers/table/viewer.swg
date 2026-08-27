#global internal

using Core, Core.Errors, Pixel, Gui

private const TableFileLimit = 32 * 1024 * 1024'u64
private const TableColumnLimit = 256'u64
private const TableColumnMinWidth = 96.0
private const TableColumnMaxWidth = 320.0
private const TableCellWidth = 8.0
internal const TableCellPreviewBytes = 1024'u64

internal struct TableRow
{
    cells: Array'String
}

internal struct TableDocument
{
    columns:   Array'String
    rows:      Array'TableRow
    delimiter: u8
}

private func loadTableDocument(fileName: string)->TableDocument fail
{
    let info = try File.info(fileName)
    if info.size > TableFileLimit do
        fail UnsupportedFormatError{Errors.mkString(tableStrings().err_TooLarge)}

    let source    = try File.readAllText(fileName)
    let delimiter = detectTableDelimiter(fileName, source.toString())
    return try parseTableDocument(source.toString(), delimiter)
}

// Bounds the text handed to the single-line rich-text renderer. A table keeps the complete cell
// for search, but shaping a megabyte-long CSV field merely to paint its first few glyphs makes
// every virtual-row repaint linear in the hidden tail.
internal func tableCellPreviewRange(value: string, focus = Swag.U64.Max)->{ start, end: u64 }
{
    var result: retval
    result.end = @countof(value)
    if result.end <= TableCellPreviewBytes do
        return result

    if focus != Swag.U64.Max and focus < result.end and focus > TableCellPreviewBytes / 3 do
        result.start = focus - TableCellPreviewBytes / 3

    while result.start and (value[result.start] & 0xC0) == 0x80 do
        result.start -= 1

    result.end = Math.min(result.start + TableCellPreviewBytes, @countof(value))
    while result.end < @countof(value) and (value[result.end] & 0xC0) == 0x80 do
        result.end -= 1
    return result
}

private func finishTableCell(row: *TableRow, cell: *Array'u8)
{
    row.cells.add(String.from(cell.isEmpty() ? "" : @mkstring(cell.buffer!, cell.count)))
    cell.clear()
}

private func finishTableRow(document: *TableDocument, row: *TableRow, cell: *Array'u8)
{
    finishTableCell(row, cell)
    document.rows.add(#move row[])
    row[] = {}
}

// Parses RFC-4180 quoting and the line-ending forms commonly found in CSV and TSV files.
internal func parseTableDocument(text: string, delimiter: u8)->TableDocument fail
{
    var result: retval
    result.delimiter = delimiter

    var row:         TableRow
    var cell:        Array'u8
    var quoted:      bool
    var closedQuote: bool
    var touched:     bool
    var at = 0'u64
    while at < @countof(text)
    {
        let value = text[at]
        if quoted
        {
            if value == '"'
            {
                if at + 1 < @countof(text) and text[at + 1] == '"'
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
                at += at + 1 < @countof(text) and text[at + 1] == '\n' ? 2 : 1
                continue
            }

            cell.add(value)
            at += 1
            continue
        }

        if value == delimiter
        {
            finishTableCell(&row, &cell)
            touched     = true
            closedQuote = false
            at          += 1
            continue
        }

        if value == '\r' or value == '\n'
        {
            finishTableRow(&result, &row, &cell)
            touched     = false
            closedQuote = false
            at          += value == '\r' and at + 1 < @countof(text) and text[at + 1] == '\n' ? 2 : 1
            continue
        }

        if value == '"' and cell.isEmpty() and !closedQuote
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
        fail InvalidFormatError{Errors.mkString(tableStrings().err_UnclosedQuote)}
    if touched or !cell.isEmpty() or !row.cells.isEmpty() do
        finishTableRow(&result, &row, &cell)
    if result.rows.isEmpty() do
        return result

    result.columns = #move result.rows[0].cells
    result.rows.removeAtOrdered(0)

    var columnCount = result.columns.count
    for one in result.rows do
        columnCount = Math.max(columnCount, one.cells.count)
    if columnCount > TableColumnLimit do
        fail UnsupportedFormatError{Errors.mkString(tableStrings().err_TooManyColumns)}

    while result.columns.count < columnCount do
        result.columns.add(Format.toString(tableStrings().ui_Column, result.columns.count + 1))
    for column, index in result.columns where column.isEmpty() do
        result.columns[index] = Format.toString(tableStrings().ui_Column, index + 1)
    return result
}

private func delimiterCount(text: string, delimiter: u8)->u64
{
    var result: u64
    var quoted: bool
    var at      = 0'u64
    var records = 0'u32
    while at < @countof(text) and at < 16 * 1024 and records < 8
    {
        let value = text[at]
        if value == '"'
        {
            if quoted and at + 1 < @countof(text) and text[at + 1] == '"' do
                at += 2
            else
            {
                quoted = !quoted
                at     += 1
            }

            continue
        }

        if !quoted and value == delimiter do
            result += 1
        if !quoted and (value == '\r' or value == '\n')
        {
            records += 1
            if value == '\r' and at + 1 < @countof(text) and text[at + 1] == '\n' do
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
internal func detectTableDelimiter(fileName, text: string)->u8
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

private func tableCountText(count: u64, one, many: string)->String
{
    if count == 1 do
        return String.from(one)
    return Format.toString(many, count)
}

internal struct TableViewer
{
    using wnd: Wnd

    #[Swag.Late]
    list: *ListCtrl

    document:             TableDocument
    searchRow:            u64 = Swag.U64.Max
    searchColumn:         u64
    searchOffset:         u64
    searchLength:         u64
    load:                 ViewerBackgroundLoad'TableDocument
    loadTimer:            #null *Timer
    reportFailure:        #null ViewerReportFailure
    reportDetails:        #null ViewerReportDetails
    reportLoadingChanged: #null ViewerReportLoadingChanged
    failureReason:        String
}

private impl IWnd for TableViewer
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        if !.load.isDone() do
            return

        .removeTimer(evt.timer)
        .loadTimer     = null
        .failureReason = .load.finish(&.document)
        if !.failureReason.isEmpty()
        {
            if .reportFailure do
                .reportFailure!(me, .failureReason.toString())
            return
        }

        .publishDocument()
        if .reportLoadingChanged do
            .reportLoadingChanged!(me)
    }
}

private impl TableViewer
{
    mtd publishDocument()
    {
        for column, index in .document.columns
        {
            var longest = column.length
            for row in .document.rows.toSlice()[0 until Math.min(.document.rows.count, 128)] where index < row.cells.count do
                longest = Math.max(longest, row.cells[index].length)
            let width = Math.clamp(cast(f32) longest * TableCellWidth + 24, TableColumnMinWidth, TableColumnMaxWidth)
            let range = tableCellPreviewRange(column.toString())
            .list.addColumn(column.toString()[range.start until range.end], width)
        }

        .list.setVirtualCount(cast(u32) .document.rows.count)
        .applyLayout()
        .setInitialFocus(.list)

        let rows    = tableCountText(.document.rows.count, tableStrings().ui_Row, tableStrings().ui_Rows)
        let columns = tableCountText(.document.columns.count, tableStrings().ui_OneColumn, tableStrings().ui_Columns)
        let kind    = .document.delimiter == '\t' ? "TSV" : "CSV"
        if .reportDetails do
            .reportDetails!(me, Format.toString(tableStrings().ui_Details, kind, rows.toString(), columns.toString()).toString())
    }

    mtd retire()->bool
    {
        if !.load.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer!)
            .loadTimer = null
        }

        return true
    }

    mtd fillLine(line: *ListLine, index: u32)
    {
        if index >= .document.rows.count do
            return
        let row = &.document.rows[index]
        for column in .document.columns.count
        {
            let value = column < row.cells.count ? row.cells[column].toString() : ""
            let range = tableCellPreviewRange(value, index == .searchRow and column == .searchColumn ? .searchOffset : Swag.U64.Max)
            let item  = line.setItem(cast(u32) column, value[range.start until range.end])
            if index == .searchRow and column == .searchColumn
            {
                item.colorBk = .themeColors().edit_SelectedBk
                item.colorFg = .themeColors().label_Text
                if .searchLength and .searchOffset + .searchLength <= @countof(value)
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
                        if range.end < @countof(value) do
                            marked += "\u2026"
                        item.name = marked.toString()
                    }
                }
            }
        }
    }

    mtd collectMatches(text: string, options: ViewerSearchOptions, result: *Array'ViewerSearchMatch)
    {
        for row, rowIndex in .document.rows
        {
            for cell, column in row.cells do
                collectViewerTextMatches(cell.toString(), text, options, rowIndex, column, 0, result)
        }
    }

    mtd revealMatch(match: ViewerSearchMatch)->bool
    {
        if match.major >= .document.rows.count or match.minor >= .document.rows[match.major].cells.count do
            return false

        .searchRow    = match.major
        .searchColumn = match.minor
        .searchOffset = match.offset
        .searchLength = match.length
        .list.unselectAll()
        .list.setFocusedIndex(cast(u32) match.major)
        .list.invalidate()
        return true
    }

    mtd searchBounds(result: *Math.Rectangle)->bool
    {
        if .searchRow >= .document.rows.count do
            return false
        return listRowSearchBounds(.list, cast(u32) .searchRow, result)
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

    func create(parent: *Wnd, fileName: string, reportFailure: #null ViewerReportFailure, reportDetails: #null ViewerReportDetails, reportLoadingChanged: #null ViewerReportLoadingChanged)->*TableViewer
    {
        let result = Wnd.create'TableViewer(parent, "sFileScope.table")
        result.backgroundStyle      = .View
        result.reportFailure        = reportFailure
        result.reportDetails        = reportDetails
        result.reportLoadingChanged = reportLoadingChanged

        with result.list = ListCtrl.createMultiColumns(result)
        {
            .dockStyle = .Center
            .style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
            .setSelectionMode(.Single)
            .setFirstColumnIconMargin(false)
            .updateFlags(.HotTrack | .AlternateLines | .Ellipsis)
            .header.form       = .Transparent
            .onFillVirtualLine = &fillTableVirtualLine
        }

        result.applyLayout()
        result.setInitialFocus(result.list)
        result.load.start(fileName, &loadTableDocument)
        result.loadTimer = result.addTimer(ViewerBackgroundPollInterval)
        return result
    }
}

private func fillTableVirtualLine(list: *ListCtrl, line: #null *ListLine, index: u32)
{
    if line == null do
        return
    (cast(*TableViewer) list.parent!).fillLine(line!, index)
}

// Creates the integrated CSV/TSV table view.
func createTableViewer(request: const *ViewerRequest, result: *ViewerResult)
{
    registerTableStrings(request.contentParent.app())
    let view = TableViewer.create(request.contentParent, request.fileName, request.reportFailure, request.reportDetails, request.reportLoadingChanged)
    result.view           = view
    result.collectMatches = func(wnd, text, options, matches) { (cast(*TableViewer) wnd).collectMatches(text, options, matches) }
    result.revealMatch    = func(wnd, match, text)->bool
    {
        discard text
        return (cast(*TableViewer) wnd).revealMatch(match)
    }
    result.searchBounds = func(wnd, match, bounds)->bool
    {
        discard match
        return (cast(*TableViewer) wnd).searchBounds(bounds)
    }
    result.clearSearch         = func(wnd) { (cast(*TableViewer) wnd).clearSearch() }
    result.isLoading           = func(wnd)->bool { return (cast(*TableViewer) wnd).loadTimer != null }
    result.needsLoadingOverlay = func(wnd)->bool { return (cast(*TableViewer) wnd).loadTimer != null }
    result.retire              = func(wnd)->bool { return (cast(*TableViewer) wnd).retire() }
}
