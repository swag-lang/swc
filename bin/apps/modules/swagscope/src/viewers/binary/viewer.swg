#global internal

using Core, Pixel, Gui

// Describes the executable and archive inspector to the host.
func binaryViewerPlugin()->Viewer.Plugin
{
    var result: retval
    result.key          = "binary"
    result.staticName   = "Binary"
    result.attach       = &registerBinaryStrings
    result.iconAtlas    = viewerIcons()
    result.iconIndex    = cast(s32) ViewerIcons.Binary
    result.create       = &createBinaryViewer
    result.smokeFixture = "appicon.ico"
    result.addSelectors(".exe;.dll;.sys;.ocx;.cpl;.scr;.efi;.drv;.mui;.mun;.winmd;.node;.pyd;.obj;.o;.lib;.a;.so;.elf;.ko;.axf;.dylib;.bundle;.wasm;.scc;.zip;.jar;.war;.apk;.aar;.epub;.whl;.nupkg;.vsix;.crx;.xpi;.docx;.xlsx;.pptx;.odt;.ods;.odp;.otf;.woff;.woff2;.ico;.cur;.gz;.tgz;.bz2;.tbz2;.xz;.txz;.zst;.tzst;.7z;.rar;.cab;.msi;.doc;.xls;.ppt;.ps;.eps;.class;.dex;.sqlite;.db;.pdb;.mid;.midi;.wav;.avi;.webp;.mp3;.flac;.ogg;.oga;.ogv;.mp4;.m4a;.m4v;.mov;.3gp;.3g2;.mkv;.webm;*")
    return result
}

private const BinaryOffsetWidth    = 116.0
private const BinaryDetailMinWidth = 200.0
private const BinaryFillRows       = 128'u64
private const BinaryCommandWidth   = 80.0

// Commands shared by the context menu, keyboard, and command bar.
internal struct ActionBinary {}

internal impl ActionBinary
{
    newCmdId("CopyAll")
    newCmdId("CopyLine")
    newCmdId("ExpandAll")
    newCmdId("CollapseAll")
    newCmdId("GoTo")
    newCmdId("Back")
    newCmdId("Forward")
}

// Lanes one row of the report is read across.
internal enum BinaryColumn
{
    Field      // Structure or field name, and the tree indentation.
    Value      // The value itself, in the spelling its type is read in.
    Offset     // Where in the file the value was read.
    Detail     // What the value means.
}

// Structured view of a binary file.
//
// Every format reader produces the same thing — a flat, levelled list of rows — so this view knows
// nothing about executables, libraries or containers. It turns rows into a tree, maps a byte offset
// the host searched for back onto the row that covers it, and copies the whole report as text.
internal struct BinaryViewer
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:      *Wnd
        backButton:    *IconButton
        forwardButton: *IconButton
        list:          *ListCtrl
    }

    previewBand:             #null *StackLayoutCtrl
    doc:                     BinaryDocument
    pendingDoc:              BinaryDocument
    rowLines:                Array'(#null *ListLine)     // Line created for each report row, in row order.
    fillParents:             Array'(#null *ListLine)
    fillIndex:               u64
    details:                 String
    failureReason:           String
    loadFileName:            String
    loadStrings:             BinaryStrings
    loadThread:              Threading.Thread
    loadTimer:               #null *Timer
    filterTimer:             #null *Timer
    loadState:               u32
    loadPublished:           bool
    reportFailure:           #null Viewer.ReportFailure
    reportDetails:           #null Viewer.ReportDetails
    reportLoadingChanged:    #null Viewer.ReportLoadingChanged
    retireRequested:         bool
    retired:                 bool
    reloadLanguageRequested: bool
    restoreExpanded:         Array'bool
    restoreSelected    = Swag.U64.Max
    history:                 Array'u64
    historyIndex       = Swag.U64.Max
    historyNavigating:       bool
    searchRow          = Swag.U64.Max
    searchColumn:            u64
    searchOffset:            u64
    searchLength:            u64
    searchVisibleIndex = Swag.U32.Max
    filterQuery:             String
    filterOptions:           Viewer.SearchOptions
    filterIncluded:          Array'bool
}

// Reads a hexadecimal file offset, with an optional sign relative to `current`.
private func parseBinaryOffset(text: string, current, fileSize: u64)->u64
{
    var index = 0'u64
    let count = text.count
    while index < count and (text[index] == ' 'u8 or text[index] == '\t'u8) do
        index += 1

    var relative = 0's32
    if index < count and (text[index] == '+'u8 or text[index] == '-'u8)
    {
        relative = text[index] == '+'u8 ? 1 : -1
        index    += 1
    }

    if index + 1 < count and text[index] == '0'u8 and (text[index + 1] == 'x'u8 or text[index + 1] == 'X'u8) do
        index += 2

    var value  = 0'u64
    var digits = 0'u64
    while index < count
    {
        let c      = text[index]
        var nibble = 16'u8
        if c >= '0'u8 and c <= '9'u8 do
            nibble = c - '0'u8
        elif c >= 'a'u8 and c <= 'f'u8 do
            nibble = c - 'a'u8 + 10
        elif c >= 'A'u8 and c <= 'F'u8 do
            nibble = c - 'A'u8 + 10
        elif c == ' 'u8 or c == '_'u8
        {
            index += 1
            continue
        }

        if nibble == 16 do
            return Swag.U64.Max
        if value > (Swag.U64.Max - nibble) / 16 do
            return Swag.U64.Max
        value  = value * 16 + nibble
        digits += 1
        index  += 1
    }

    if !digits or !fileSize do
        return Swag.U64.Max
    var target = value
    if relative > 0 do
        target = current + Math.min(value, Swag.U64.Max - current)
    elif relative < 0 do
        target = value >= current ? 0 : current - value
    return Math.min(target, fileSize - 1)
}

internal impl BinaryViewer
{
    // Returns the exact text displayed in one logical report cell.
    private mtd cellText(rowIndex, column: u64)->String
    {
        let row = &.doc.report.rows[rowIndex]
        switch #complete cast(BinaryColumn) column
        {
        case .Field:  return String.from(row.label.toString())
        case .Value:  return String.from(row.value.toString())
        case .Offset: return row.offset == Swag.U64.Max ? String.from("") : hexText(row.offset, 8)
        case .Detail: return String.from(row.detail.toString())
        }
    }

    // Gives every lane a stable semantic ink derived from the current theme.
    private mtd styleLine(rowIndex: u64, line: *ListLine)
    {
        let row    = &.doc.report.rows[rowIndex]
        let colors = .themeColors()
        let theme  = .theme()

        line.colorFg = row.kind == .Note ? theme.palette.caution.mark : {}
        line.itemAt(cast(u32) BinaryColumn.Value).colorFg  = theme.palette.alternate.mark
        line.itemAt(cast(u32) BinaryColumn.Offset).colorFg = colors.label_TextFaint
        line.itemAt(cast(u32) BinaryColumn.Detail).colorFg = colors.label_TextLight

        if row.kind == .Group
        {
            var marked = String.from("<b>")
            marked += row.label
            marked += "</b>"
            line.itemAt(cast(u32) BinaryColumn.Field).name = marked.toString()
        }
    }

    // Rebuilds the tree from the report, parents before the rows they own.
    mtd beginFillList()
    {
        .list.clear()
        .rowLines.clear()
        .rowLines.resize(.doc.report.rows.count)
        .fillParents.clear()
        .fillIndex = 0
    }

    // Publishes a bounded number of report rows per GUI turn.
    mtd fillListStep()->bool
    {
        let end = Math.min(.fillIndex + BinaryFillRows, .doc.report.rows.count)

        for index in .fillIndex until end
        {
            if !.filterIncluded.isEmpty() and !.filterIncluded[index] do
                continue

            let row   = &.doc.report.rows[index]
            let depth = cast(u64) row.level
            var parent: #null *ListLine = null
            if depth and depth <= .fillParents.count do
                parent = .fillParents[depth - 1]

            let line = .list.createLine(parent)
            line.setItem(cast(u32) BinaryColumn.Field, row.label.toString())
            line.setItem(cast(u32) BinaryColumn.Value, row.value.toString())
            line.setItem(cast(u32) BinaryColumn.Detail, row.detail.toString())

            if row.offset != Swag.U64.Max
            {
                let position = hexText(row.offset, 8)
                line.setItem(cast(u32) BinaryColumn.Offset, position.toString())
            }
            else do
                line.setItem(cast(u32) BinaryColumn.Offset, "")

            .styleLine(index, line)

            .fillParents.resize(depth + 1)
            .fillParents[depth] = line
            .rowLines[index]    = line
        }

        .fillIndex = end
        if end != .doc.report.rows.count do
            return false
        .applyExpansion()
        .restoreSelection()
        .list.computeLayout()
        return true
    }

    // Opens the groups the report asked to start open.
    //
    // A row the list has not made visible cannot be expanded through the list, so the deeper groups
    // are only marked; expanding a root then inserts its whole marked subtree in one pass.
    private mtd applyExpansion()
    {
        if !.filterQuery.isEmpty()
        {
            for row, index in .doc.report.rows where row.level and .rowLines[index] do
                .rowLines[index]!.expanded = true
            for row, index in .doc.report.rows where !row.level and .rowLines[index] do
                .list.expand(.rowLines[index]!)
            return
        }

        for row, index in .doc.report.rows
        {
            let open = index < .restoreExpanded.count ? .restoreExpanded[index] : row.open
            if open and row.level and .rowLines[index] do
                .rowLines[index]!.expanded = true
        }

        for row, index in .doc.report.rows
        {
            let open = index < .restoreExpanded.count ? .restoreExpanded[index] : row.open
            if open and !row.level and .rowLines[index] do
                .list.expand(.rowLines[index]!)
        }

        .restoreExpanded.clear()
    }

    private mtd restoreSelection()
    {
        if .restoreSelected >= .rowLines.count or !.rowLines[.restoreSelected]
        {
            if .filterQuery.isEmpty() do
                .restoreSelected = Swag.U64.Max
            return
        }

        discard .selectReportRow(.restoreSelected, recordHistory: false)
        .restoreSelected = Swag.U64.Max
    }

    // Opens or closes every group at once.
    mtd setExpandedAll(expand: bool)
    {
        .list.collapseAll()
        if expand
        {
            for row, index in .doc.report.rows where row.level and .rowLines[index] do
                .rowLines[index]!.expanded = true
            for row, index in .doc.report.rows where !row.level and .rowLines[index] do
                .list.expand(.rowLines[index]!)
        }

        .list.computeLayout()
        .invalidate()
    }

    // Reveals the structure the byte at `offset` belongs to.
    //
    // The host searches the raw bytes and knows nothing of the structure; this is what turns the
    // offset it found into a place in the file's layout. Group rows carry the range they cover, so
    // a hit deep inside a section's payload still lands on that section.
    mtd revealOffset(offset: u64, text: string)->bool
    {
        discard text

        let index = .doc.report.rowAt(offset)
        if index == Swag.U64.Max do
            return false
        return .selectReportRow(index)
    }

    // Selects one stable report row and opens its ancestors.
    private mtd selectReportRow(index: u64, recordHistory = true)->bool
    {
        if index >= .rowLines.count do
            return false
        let line = .rowLines[index]
        if !line do
            return false

        .expandTo(line!)
        let visible = .visibleIndexOf(line!)
        if visible == Swag.U32.Max do
            return false

        .list.unselectAll()
        .list.selectLine(visible)
        .list.setFocusedIndex(visible)
        .list.setFocus()
        .searchVisibleIndex = visible
        if recordHistory do
            .recordHistory(index)
        return true
    }

    private mtd reportIndexOf(line: #null *ListLine)->u64
    {
        if !line do
            return Swag.U64.Max
        for rowLine, index in .rowLines where rowLine == line do
            return index
        return Swag.U64.Max
    }

    private mtd selectedReportIndex()->u64 => .reportIndexOf(.list.selectedLine())

    private mtd recordHistory(index: u64)
    {
        if .historyNavigating or index >= .doc.report.rows.count do
            return
        if .historyIndex < .history.count and .history[.historyIndex] == index do
            return
        if .historyIndex != Swag.U64.Max and .historyIndex + 1 < .history.count do
            .history.resize(.historyIndex + 1)
        .history.add(index)
        .historyIndex = .history.count - 1
        .refreshHistoryCommands()
    }

    private mtd refreshHistoryCommands()
    {
        .backButton.enable(.historyIndex != Swag.U64.Max and .historyIndex != 0)
        .forwardButton.enable(.historyIndex != Swag.U64.Max and .historyIndex + 1 < .history.count)
    }

    mtd navigateHistory(direction: s32)->bool
    {
        if .historyIndex == Swag.U64.Max do
            return false
        let next = cast(s64) .historyIndex + direction
        if next < 0 or next >= cast(s64) .history.count do
            return false

        .historyNavigating = true
        defer .historyNavigating = false
        if !.selectReportRow(.history[cast(u64) next], recordHistory: false) do
            return false
        .historyIndex = cast(u64) next
        .refreshHistoryCommands()
        return true
    }

    // Indexes the decoded report rather than scanning unrelated raw bytes.
    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for row, rowIndex in .doc.report.rows
        {
            if !.filterIncluded.isEmpty() and !.filterIncluded[rowIndex] do
                continue
            Viewer.collectTextMatches(row.label.toString(), text, options, rowIndex, cast(u64) BinaryColumn.Field, 0, result)
            Viewer.collectTextMatches(row.value.toString(), text, options, rowIndex, cast(u64) BinaryColumn.Value, 0, result)
            if row.offset != Swag.U64.Max
            {
                let offset = hexText(row.offset, 8)
                Viewer.collectTextMatches(offset.toString(), text, options, rowIndex, cast(u64) BinaryColumn.Offset, 0, result)
            }

            Viewer.collectTextMatches(row.detail.toString(), text, options, rowIndex, cast(u64) BinaryColumn.Detail, 0, result)
        }
    }

    mtd revealMatch(match: Viewer.SearchMatch)->bool
    {
        if match.major >= .doc.report.rows.count or match.minor > cast(u64) BinaryColumn.Detail do
            return false
        .clearSearchHighlight()
        if !.selectReportRow(match.major) do
            return false

        let source = .cellText(match.major, match.minor)
        if match.offset + match.length > source.length do
            return false

        .searchRow    = match.major
        .searchColumn = match.minor
        .searchOffset = match.offset
        .searchLength = match.length
        .list.invalidate()
        return true
    }

    mtd searchBounds(result: *Math.Rectangle)->bool
    {
        if .searchVisibleIndex == Swag.U32.Max or .searchRow >= .rowLines.count or !.rowLines[.searchRow] do
            return false
        let source = .cellText(.searchRow, .searchColumn)
        return Viewer.listCellMatchBounds(.list, .searchVisibleIndex, cast(u32) .searchColumn, source.toString(), .searchOffset, .searchLength, result)
    }

    mtd clearSearch()
    {
        .clearSearchHighlight()
        .searchVisibleIndex = Swag.U32.Max
        .list.unselectAll()
        .list.invalidate()
    }

    private mtd clearSearchHighlight()
    {
        .searchRow    = Swag.U64.Max
        .searchColumn = 0
        .searchOffset = 0
        .searchLength = 0
    }

    private mtd rowMatchesFilter(rowIndex: u64, options: Viewer.SearchOptions)->bool
    {
        let query = .filterQuery.toString()
        let row   = &.doc.report.rows[rowIndex]
        var matches: Array'Viewer.SearchMatch
        Viewer.collectTextMatches(row.label.toString(), query, options, 0, 0, 0, &matches)
        Viewer.collectTextMatches(row.value.toString(), query, options, 0, 0, 0, &matches)
        Viewer.collectTextMatches(row.detail.toString(), query, options, 0, 0, 0, &matches)
        if row.offset != Swag.U64.Max
        {
            let offset = hexText(row.offset, 8)
            Viewer.collectTextMatches(offset.toString(), query, options, 0, 0, 0, &matches)
        }

        return !matches.isEmpty()
    }

    // Keeps direct matches and every ancestor needed to reach them. Filtering therefore never
    // turns a nested field into an orphan row or leaves it behind a collapsed parent.
    private mtd rebuildFilterIndex()
    {
        .filterIncluded.clear()
        if .filterQuery.isEmpty() do
            return

        .filterIncluded.resize(.doc.report.rows.count)
        var options = .filterOptions
        var expression: Parser.RegExp
        if options.regularExpression
        {
            catch expression.compile(.filterQuery.toString(), ignoreCase: !options.matchCase) as expressionError
            if expressionError == null do
                options.expression = &expression
        }

        for row, index in .doc.report.rows
        {
            discard row
            .filterIncluded[index] = .rowMatchesFilter(index, options)
        }

        // Rows are stored in preorder, so walking backward from a direct match finds each parent
        // at the first preceding shallower level. Mark that chain without leaking a match into an
        // earlier sibling branch.
        for matched in .doc.report.rows.count where .filterIncluded[matched]
        {
            var depth  = cast(u64) .doc.report.rows[matched].level
            var parent = matched
            while depth and parent
            {
                parent -= 1
                let candidateDepth = cast(u64) .doc.report.rows[parent].level
                if candidateDepth >= depth do
                    continue
                .filterIncluded[parent] = true
                depth = candidateDepth
            }
        }
    }

    mtd applyFilter(query: string, options: Viewer.SearchOptions)
    {
        let enteringFilter = .filterQuery.isEmpty() and query.count
        if enteringFilter and .loadPublished do
            .captureViewState()
        .filterQuery              = query
        .filterOptions            = options
        .filterOptions.expression = null
        if !.loadPublished do
            return

        .rebuildFilterIndex()
        if .filterTimer
        {
            .removeTimer(.filterTimer!)
            .filterTimer = null
        }

        .beginFillList()
        if .fillListStep()
        {
            .layoutColumns()
            .invalidate()
        }
        elif !.loadTimer do
            .filterTimer = .addTimer(1'ms)
    }

    // Opens every group between the root and `line`, outermost first.
    private mtd expandTo(line: *ListLine)
    {
        var chain: Array'(*ListLine)
        var walk = line.parent
        while walk
        {
            chain.add(walk!)
            walk = walk!.parent
        }

        for index in chain.count do
            .list.expand(chain[chain.count - 1 - index])
    }

    // Returns where `line` currently sits among the visible rows, or `Swag.U32.Max`.
    private mtd visibleIndexOf(line: *ListLine)->u32
    {
        for index in .list.lineCount() where .list.lineAt(index) == line do
            return index
        return Swag.U32.Max
    }

    mtd copyReport()
    {
        let text = .doc.report.toText()
        Clipboard.addString(text.toString())
    }

    mtd copySelectedLine()
    {
        let line = .list.selectedLine()
        if !line do
            return

        var text: String
        for column in 4
        {
            let item = line!.itemAt(cast(u32) column)
            if item.name.raw.isEmpty() do
                continue
            if !text.isEmpty() do
                text += "  "
            let plain = RichString.plainText(item.name.raw.toString())
            text += plain
        }

        Clipboard.addString(text.toString())
    }

    mtd goToTypedOffset(text: string)->bool
    {
        var current  = 0'u64
        let selected = .selectedReportIndex()
        if selected < .doc.report.rows.count and .doc.report.rows[selected].offset != Swag.U64.Max do
            current = .doc.report.rows[selected].offset

        let target = parseBinaryOffset(text, current, .doc.image.fileSize)
        if target == Swag.U64.Max do
            return false
        return .revealOffset(target, "")
    }

    mtd promptGoToOffset()
    {
        let surface = .surface
        if !surface or !.doc.image.fileSize do
            return

        var current  = 0'u64
        let selected = .selectedReportIndex()
        if selected < .doc.report.rows.count and .doc.report.rows[selected].offset != Swag.U64.Max do
            current = .doc.report.rows[selected].offset

        var options: EditDlgOptions
        let currentText = hexText(current, 8)
        options.title   = binStrings().ui_MenuGoTo
        options.message = binStrings().ui_GoToMessage
        options.text    = currentText.toString()
        let dialog = EditDlg.createSingleLine(surface!, options)
        if dialog.doModal() != Dialog.BtnOk do
            return
        let typed = dialog.text()
        discard .goToTypedOffset(typed.toString())
    }

    mtd createCommandMenu()->*MenuCtrl
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(ActionBinary.CopyAll)
        menu.addItem(ActionBinary.CopyLine)
        menu.addSeparator()
        menu.addItem(ActionBinary.ExpandAll)
        menu.addItem(ActionBinary.CollapseAll)
        menu.addSeparator()
        menu.addItem(ActionBinary.GoTo)
        menu.addItem(ActionBinary.Back)
        menu.addItem(ActionBinary.Forward)
        return menu
    }

    mtd showContextMenu(surfacePos: Math.Point)
    {
        let menu = .createCommandMenu()
        discard menu.doModal(surfacePos, .TopLeft, autoDestroy: true)
    }

    // Divides the visible width into the four lanes a row is read across.
    //
    // The meaning lane takes what the other three leave, because it is the only one whose content
    // has no natural width: a flag list is as long as the flags that are set.
    mtd layoutColumns()
    {
        if !Swag.isSet(.list) do
            return

        let room  = Math.max(.list.listView.paddedClientRect().width, 480.0)
        let field = Math.max(room * 0.28, 180.0)
        let value = Math.max(room * 0.20, 130.0)
        let lanes = field + value + BinaryOffsetWidth + BinaryDetailMinWidth

        .list.setColumnWidth(cast(u32) BinaryColumn.Field, field)
        .list.setColumnWidth(cast(u32) BinaryColumn.Value, value)
        .list.setColumnWidth(cast(u32) BinaryColumn.Offset, BinaryOffsetWidth)
        .list.setColumnWidth(cast(u32) BinaryColumn.Detail, BinaryDetailMinWidth)

        // The separators and the leading padding belong to the header's width but to no lane, so
        // what they take is measured rather than guessed: a lane sized past it puts a horizontal
        // scrollbar under a table that had room for its content.
        let chrome = .list.header.contentWidth() - lanes
        let detail = Math.max(room - chrome - field - value - BinaryOffsetWidth, BinaryDetailMinWidth)
        .list.setColumnWidth(cast(u32) BinaryColumn.Detail, detail)
        .list.computeLayout()
    }

    mtd fillPreviews()
    {
        if .doc.previews.isEmpty() do
            return

        let band = StackLayoutCtrl.create(me, .HorizontalCenter, {0, 0, 0, 152})
        band.dockStyle       = .Top
        band.backgroundStyle = .View
        band.padding         = {12, 10, 12, 8}
        band.spacing         = 8
        .previewBand         = band

        for preview in .doc.previews
        {
            let tile = StackLayoutCtrl.create(band, .Top, {0, 0, 160, 132})
            tile.spacing = 4
            with let image = ImageView.create(tile, {0, 0, 160, 104})
            {
                .backgroundStyle = .View
                .setImage(preview.image)
            }

            with let label = Label.create(tile, preview.label.toString(), {0, 0, 160, 24}, null, .SecondaryText | .Ellipsis)
            {
                .setTextAlignment(.Center, .Center)
            }
        }
    }

    // Keeps every recognized image in one restrained row. Large icon families get smaller cards
    // instead of forcing a second permanent toolbar-sized band into the document.
    mtd layoutPreviews()
    {
        if !.previewBand do
            return
        let band  = .previewBand!
        let count = band.children.count
        if !count do
            return
        let room = Math.max(band.paddedClientRect().width - cast(f32) (count - 1) * band.spacing, 1)

        // Leave one logical pixel per card for device-pixel rounding at fractional DPI scales.
        let width = Math.min(160.0, (room - cast(f32) count) / cast(f32) count)
        for child in band.children
        {
            child.resize(width, 132)
            for item in child.children do
                item.resize(width, item.position.height)
        }

        band.computeLayout()
    }
}

internal impl IActionUI for ActionBinary
{
    mtd impl accept(cxt: ActionContext)->bool
    {
        switch cxt.id
        {
        case ActionBinary.CopyAll, ActionBinary.CopyLine, ActionBinary.ExpandAll, ActionBinary.CollapseAll, ActionBinary.GoTo, ActionBinary.Back, ActionBinary.Forward: return true
        }

        return false
    }

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let view  = cast(*BinaryViewer) cxt.wnd!
        let s     = binStrings()
        let theme = view.theme()

        switch cxt.id
        {
        case ActionBinary.CopyAll:
            evt.updatedFields |= .Name | .Icon | .Shortcut
            evt.name          = s.ui_MenuCopyAll
            evt.icon          = theme.icon(.Copy)
            evt.shortcut      = "Ctrl+C"

        case ActionBinary.CopyLine:
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.name          = s.ui_MenuCopyLine
            evt.icon          = theme.icon(.Copy)
            evt.disabled      = view.list.selectedLine() == null

        case ActionBinary.ExpandAll:
            evt.updatedFields |= .Name | .Icon | .Shortcut
            evt.name          = s.ui_MenuExpand
            evt.icon          = theme.icon(.ChevronRight)
            evt.shortcut      = "Ctrl+E"

        case ActionBinary.CollapseAll:
            evt.updatedFields |= .Name | .Icon | .Shortcut
            evt.name          = s.ui_MenuCollapse
            evt.icon          = theme.icon(.ChevronDown)
            evt.shortcut      = "Ctrl+Shift+E"

        case ActionBinary.GoTo:
            evt.updatedFields |= .Name | .Shortcut | .Disabled
            evt.name          = s.ui_MenuGoTo
            evt.shortcut      = "Ctrl+G"
            evt.disabled      = !view.doc.image.fileSize

        case ActionBinary.Back:
            evt.updatedFields |= .Name | .Icon | .Shortcut | .Disabled
            evt.name          = s.ui_MenuBack
            evt.icon          = theme.icon(.ChevronLeft)
            evt.shortcut      = "Alt+Left"
            evt.disabled      = view.historyIndex == Swag.U64.Max or !view.historyIndex

        case ActionBinary.Forward:
            evt.updatedFields |= .Name | .Icon | .Shortcut | .Disabled
            evt.name          = s.ui_MenuForward
            evt.icon          = theme.icon(.ChevronRight)
            evt.shortcut      = "Alt+Right"
            evt.disabled      = view.historyIndex == Swag.U64.Max or view.historyIndex + 1 >= view.history.count
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let view = cast(*BinaryViewer) cxt.wnd!
        switch cxt.id
        {
        case ActionBinary.CopyAll:     view.copyReport()
        case ActionBinary.CopyLine:    view.copySelectedLine()
        case ActionBinary.ExpandAll:   view.setExpandedAll(true)
        case ActionBinary.CollapseAll: view.setExpandedAll(false)
        case ActionBinary.GoTo:        view.promptGoToOffset()
        case ActionBinary.Back:        discard view.navigateHistory(-1)
        case ActionBinary.Forward:     discard view.navigateHistory(1)
        }

        return true
    }
}

internal impl IWnd for BinaryViewer
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .retranslate()
            .requestLanguageReload()
        }
        elif evt.kind == .ThemeChanged
        {
            for line, index in .rowLines where line do
                .styleLine(index, line!)
            .list.invalidate()
        }
        else do
            evt.accepted = false
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .filterTimer
        {
            if !.fillListStep() do
                return
            .removeTimer(evt.timer)
            .filterTimer = null
            .layoutColumns()
            .invalidate()
            return
        }

        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        let state = Atomic.get(&.loadState)
        if !state do
            return
        if !.loadPublished
        {
            if .loadThread.isValid() do
                .loadThread.wait()
            if .reloadLanguageRequested
            {
                .reloadLanguageRequested = false
                .pendingDoc              = {}
                catch .startLoad() as reloadError
                if reloadError != null do
                    .publishLoadFailure(Errors.message(reloadError))
                return
            }

            if state == 2
            {
                .finishLoadTimer()
                .failureReason = #move .pendingDoc.image.failureReason
                if .reportFailure do
                    .reportFailure!(me, .failureReason.toString())
                return
            }

            if .previewBand
            {
                .previewBand!.destroy()
                .previewBand = null
            }

            .list.clear()
            .searchRow          = Swag.U64.Max
            .searchVisibleIndex = Swag.U32.Max
            .doc                = #move .pendingDoc
            .details            = .doc.report.summary
            .loadPublished      = true
            .rebuildFilterIndex()
            .beginFillList()
            if .reportDetails do
                .reportDetails!(me, .details.toString())
        }

        if !.fillListStep() do
            return
        .fillPreviews()
        .applyLayout()
        .layoutPreviews()
        .layoutColumns()
        .finishLoadTimer()
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
        .layoutPreviews()
        .layoutColumns()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        if evt.key == .E and evt.modifiers.has(.Control) and evt.modifiers.has(.Shift) do
            .sendCommandEvent(ActionBinary.CollapseAll)
        elif evt.key == .E and evt.modifiers.has(.Control) do
            .sendCommandEvent(ActionBinary.ExpandAll)
        elif evt.key == .C and evt.modifiers.has(.Control) do
            .sendCommandEvent(ActionBinary.CopyAll)
        elif evt.key == .G and evt.modifiers.has(.Control) do
            .sendCommandEvent(ActionBinary.GoTo)
        elif evt.key == .Left and evt.modifiers.has(.Alt) do
            .sendCommandEvent(ActionBinary.Back)
        elif evt.key == .Right and evt.modifiers.has(.Alt) do
            .sendCommandEvent(ActionBinary.Forward)
        else do
            evt.accepted = false
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        .retireBlocking()
    }
}

internal impl BinaryViewer
{
    mtd retranslate()
    {
        let s = binStrings()
        .list.header.itemAt(cast(u32) BinaryColumn.Field).name  = s.ui_ColField
        .list.header.itemAt(cast(u32) BinaryColumn.Value).name  = s.ui_ColValue
        .list.header.itemAt(cast(u32) BinaryColumn.Offset).name = s.ui_ColOffset
        .list.header.itemAt(cast(u32) BinaryColumn.Detail).name = s.ui_ColDetail
        .list.header.invalidate()
    }

    private mtd captureViewState()
    {
        .restoreExpanded.clear()
        .restoreExpanded.resize(.rowLines.count)
        for line, index in .rowLines where line do
            .restoreExpanded[index] = line!.expanded
        .restoreSelected = .selectedReportIndex()
    }

    private mtd requestLanguageReload()
    {
        if .retireRequested do
            return
        .captureViewState()
        if .loadThread.isValid()
        {
            .reloadLanguageRequested = true
            return
        }

        .pendingDoc = {}
        catch .startLoad() as reloadError
        if reloadError != null do
            .publishLoadFailure(Errors.message(reloadError))
    }

    private mtd startLoad(notify = true) fail
    {
        .loadStrings   = binStrings()[]
        .loadState     = 0
        .loadPublished = false
        try .loadThread.init(&runBinaryViewerLoad, me, priority: .BelowNormal)
        try .loadThread.start()
        if !.loadTimer do
            .loadTimer = .addTimer(1'ms)
        if notify and .reportLoadingChanged do
            .reportLoadingChanged!(me)
    }

    private mtd publishLoadFailure(reason: string)
    {
        .failureReason = String.from(reason)
        .finishLoadTimer()
        if .reportFailure do
            .reportFailure!(me, .failureReason.toString())
    }

    private mtd finishLoadTimer()
    {
        if .loadTimer
        {
            .removeTimer(.loadTimer!)
            .loadTimer = null
        }

        if .filterTimer
        {
            .removeTimer(.filterTimer!)
            .filterTimer = null
        }

        if .reportLoadingChanged do
            .reportLoadingChanged!(me)
    }

    mtd retire()->bool
    {
        if .retired do
            return true
        if !.retireRequested
        {
            .retireRequested = true
            if .loadTimer
            {
                .removeTimer(.loadTimer!)
                .loadTimer = null
            }

            if .loadThread.isValid() do
                .loadThread.safeForceEnd()
        }

        if .loadThread.isValid() and !.loadThread.isDone() do
            return false
        if .loadThread.isValid() do
            .loadThread.wait()
        .retired = true
        return true
    }

    mtd retireBlocking()
    {
        discard .retire()
        if .loadThread.isValid() do
            .loadThread.wait()
        .retired = true
    }

    func create(host: Viewer.Host)->#null *BinaryViewer fail
    {
        let s        = binStrings()
        let services = host.services()

        let result = Wnd.create'BinaryViewer(host.contentParent(), "scope.binary")
        result.backgroundStyle = .View
        result.registerAction'ActionBinary()
        result.reportDetails        = services.reportDetails
        result.reportFailure        = services.reportFailure
        result.reportLoadingChanged = services.reportLoadingChanged
        result.commands             = host.createCommandGroup(BinaryCommandWidth)

        with result.backButton = IconButton.create(result.commands, result.theme().icon(.ChevronLeft, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle = .Left
            .toolTip   = s.ui_MenuBack
            .enable(false)
            .sigPressed += func|view = result|(button)
            {
                discard button
                discard view.navigateHistory(-1)
            }
        }

        with result.forwardButton = IconButton.create(result.commands, result.theme().icon(.ChevronRight, themeActionIconSize(result.themeMetrics())), {0, 0, themeActionButtonSize(result.themeMetrics()), themeActionButtonSize(result.themeMetrics())})
        {
            .dockStyle = .Left
            .toolTip   = s.ui_MenuForward
            .enable(false)
            .sigPressed += func|view = result|(button)
            {
                discard button
                discard view.navigateHistory(1)
            }
        }

        // The whole report is read in the fixed-width font: every second lane is a number, and a
        // column of hexadecimal that does not line up is a column that has to be read twice.
        with result.list = ListCtrl.createMultiColumns(result)
        {
            .dockStyle = .Center
            .style.setFont(result.theme().createDefaultFontfamilyFS(result.themeMetrics().defaultFixedFontSize))
            .setSelectionMode(.Single)
            .setFirstColumnIconMargin(false)
            .updateFlags(.HotTrack | .AlternateLines)
            .addColumn(s.ui_ColField, 320)
            .addColumn(s.ui_ColValue, 200)
            .addColumn(s.ui_ColOffset, BinaryOffsetWidth)
            .addColumn(s.ui_ColDetail, 320)
            .sigRightClicked += func|view = result|(list, position)
            {
                discard list
                view.showContextMenu(view.list.listView.localToSurface(position))
            }
            .sigSelectionChanged += func|view = result|(list)
            {
                view.recordHistory(view.reportIndexOf(list.selectedLine()))
            }
        }

        result.applyLayout()
        result.layoutColumns()
        result.setInitialFocus(result.list)
        result.loadFileName = host.fileName()
        defer #fail
        {
            result.destroy()
        }

        try result.startLoad(notify: false)
        return result
    }
}

// Reads and analyzes the bounded binary image without occupying the GUI event loop.
private func runBinaryViewerLoad(thread: Threading.Thread)
{
    let view    = cast(*BinaryViewer) thread.userParam!
    let context = Swag.getContext()
    context.allocator = context.defaultAllocator!
    setBinaryStringsOverride(&view.loadStrings)
    let opened = view.pendingDoc.open(view.loadFileName.toString())
    setBinaryStringsOverride(null)
    Atomic.exchange(&view.loadState, opened ? 1 : 2)
}

// Creates the integrated binary format view.
func createBinaryViewer(host: Viewer.Host)
{
    let view = catch BinaryViewer.create(host) as createError
    if createError != null
    {
        host.reject(Errors.message(createError))
        return
    }

    host.attachView(view!)
    host.setDetails(view!.details.toString())
    host.setSearch({
        describe: func(wnd, presentation)
    {
        discard wnd
        presentation.canFilter         = true
        presentation.filterPlaceholder = binStrings().ui_Filter
        presentation.filterToolTip     = binStrings().ui_FilterTip
    },
        filter: func(wnd, text, options) { (cast(*BinaryViewer) wnd).applyFilter(text, options) },
        collectMatches: func(wnd, text, options, progress, matches)->bool
    {
        discard progress
        (cast(*BinaryViewer) wnd).collectMatches(text, options, matches)
        return true
    },
        revealMatch: func(wnd, match, text)->bool
    {
        discard text
        return (cast(*BinaryViewer) wnd).revealMatch(match)
    },
        matchBounds: func(wnd, match, bounds)->bool
    {
        discard match
        return (cast(*BinaryViewer) wnd).searchBounds(bounds)
    },
        clear: func(wnd) { (cast(*BinaryViewer) wnd).clearSearch() }})
    host.setLifecycle({
        isLoading: func(wnd)->bool { return (cast(*BinaryViewer) wnd).loadTimer != null },
        retire: func(wnd)->bool { return (cast(*BinaryViewer) wnd).retire() }})
}
