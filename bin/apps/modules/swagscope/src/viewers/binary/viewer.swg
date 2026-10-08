#global internal
#global namespace Viewers.Binary

using Core, Pixel, Gui

// Describes the executable and archive inspector to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "binary"
        .staticName   = "Binary"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Binary)
        .create       = &createViewer
        .smokeFixture = "appicon.ico"
        .addSelectors(".exe;.dll;.sys;.ocx;.cpl;.scr;.efi;.drv;.mui;.mun;.winmd;.node;.pyd;.obj;.o;.lib;.a;.so;.elf;.ko;.axf;.dylib;.bundle;.wasm;.scc;.zip;.jar;.war;.apk;.aar;.epub;.whl;.nupkg;.vsix;.crx;.xpi;.docx;.xlsx;.pptx;.odt;.ods;.odp;.otf;.woff;.woff2;.ico;.cur;.gz;.tgz;.bz2;.tbz2;.xz;.txz;.zst;.tzst;.7z;.rar;.cab;.msi;.doc;.xls;.ppt;.ps;.eps;.class;.dex;.sqlite;.db;.pdb;.mid;.midi;.wav;.avi;.webp;.mp3;.flac;.ogg;.oga;.ogv;.mp4;.m4a;.m4v;.mov;.3gp;.3g2;.mkv;.webm;*")
    }

    return result
}

private
{
    const OffsetWidth    = 116.0
    const DetailMinWidth = 200.0
    const FillRows       = 128'u64
    const CommandWidth   = 80.0
}

// Commands shared by the context menu, keyboard, and command bar.
struct Action {}

impl Action
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
enum Column
{
    Field      // Structure or field name, and the tree indentation.
    Value      // The value itself, in the spelling its type is read in.
    Offset     // Where in the file the value was read.
    Detail     // What the value means.
}

// Structured view of a binary file.
//
// Every format reader produces the same thing — a flat, levelled list of rows — so this view knows
// nothing about executables, libraries or containers. It turns rows into a tree, maps a file offset
// back onto the row that covers it, and copies the whole report as text.
struct Panel
{
    using wnd: Wnd

    late
    {
        commands:      *Wnd
        backButton:    *IconButton
        forwardButton: *IconButton
        list:          *ListCtrl
    }

    previewBand:             *StackLayoutCtrl?
    doc:                     Document
    pendingDoc:              Document
    rowLines:                Array'(*ListLine?)     // Line created for each report row, in row order.
    fillParents:             Array'(*ListLine?)
    fillIndex:               u64
    details:                 String
    failureReason:           String
    loadFileName:            String
    loadTexts:               Texts
    loadThread:              Threading.Thread
    loadTimer:               *Timer?
    filterTimer:             *Timer?
    loadState:               u32
    loadPublished:           bool
    services:                Viewer.HostServices
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

// Returns the hexadecimal file offset `text` names, or `Swag.U64.Max` when it names none.
//
// A leading `+` or `-` makes the offset relative to `current`, and the result is clamped to the last
// byte of a file of `fileSize` bytes.
private func parseOffset(text: string, current, fileSize: u64)->u64
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
        if c >= '0'u8 and c <= '9'u8
        {
            nibble = c - '0'u8
        }
        elif c >= 'a'u8 and c <= 'f'u8
        {
            nibble = c - 'a'u8 + 10
        }
        elif c >= 'A'u8 and c <= 'F'u8
        {
            nibble = c - 'A'u8 + 10
        }
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

    if not digits or not fileSize do
        return Swag.U64.Max
    var target = value
    if relative > 0 do
        target = current + Math.min(value, Swag.U64.Max - current)
    elif relative < 0 do
        target = value >= current ? 0 : current - value
    return Math.min(target, fileSize - 1)
}

impl Panel
{
    // Returns the exact text displayed in one logical report cell.
    private mtd cellText(rowIndex, column: u64)->String
    {
        let row = &.doc.report.rows[rowIndex]
        switch #complete cast(Column, column)
        {
        case .Field:  return row.label
        case .Value:  return row.value
        case .Offset: return row.offset == Swag.U64.Max ? String.from("") : hexText(row.offset, 8)
        case .Detail: return row.detail
        }
    }

    // Gives every lane a stable semantic ink derived from the current theme.
    private mtd styleLine(rowIndex: u64, line: *ListLine)
    {
        let row    = &.doc.report.rows[rowIndex]
        let colors = .themeColors()
        let theme  = .theme()

        line.colorFg = row.kind == .Note ? theme.palette.caution.mark : {}
        line.itemAt(cast(u32, Column.Value)).colorFg  = theme.palette.alternate.mark
        line.itemAt(cast(u32, Column.Offset)).colorFg = colors.label_TextFaint
        line.itemAt(cast(u32, Column.Detail)).colorFg = colors.label_TextLight

        if row.kind == .Group
        {
            let marked = Format.toString("<b>%</b>", row.label)
            line.itemAt(cast(u32, Column.Field)).name = marked.toString()
        }
    }

    // Empties the tree so that [[Panel.fillListStep]] rebuilds it from the first report row.
    mtd beginFillList()
    {
        .list.clear()
        .rowLines.clear()
        .rowLines.resize(.doc.report.rows.count)
        .fillParents.clear()
        .fillIndex = 0
    }

    // Adds the next bounded batch of report rows to the tree, and returns whether the whole report is in.
    //
    // Rows arrive in report order, so a parent line always exists before the rows it owns, and a
    // bounded batch per GUI turn keeps a large report from freezing the window.
    mtd fillListStep()->bool
    {
        let end = Math.min(.fillIndex + FillRows, .doc.report.rows.count)

        for index in .fillIndex until end
        {
            if not .filterIncluded.isEmpty() and not .filterIncluded[index] do
                continue

            let row   = &.doc.report.rows[index]
            let depth = cast(u64, row.level)
            var parent: *ListLine? = null
            if depth and depth <= .fillParents.count do
                parent = .fillParents[depth - 1]

            with let line = .list.createLine(parent)
            {
                .setItem(cast(u32, Column.Field), row.label)
                .setItem(cast(u32, Column.Value), row.value)
                .setItem(cast(u32, Column.Detail), row.detail)
            }

            if row.offset != Swag.U64.Max
            {
                let position = hexText(row.offset, 8)
                line.setItem(cast(u32, Column.Offset), position)
            }
            else
            {
                line.setItem(cast(u32, Column.Offset), "")
            }

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
        if not .filterQuery.isEmpty()
        {
            .expandEveryGroup()
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
            if open and not row.level and .rowLines[index] do
                .list.expand(.rowLines[index]!)
        }

        .restoreExpanded.clear()
    }

    // Opens every group of the tree.
    //
    // Deeper groups are only marked; expanding each root then inserts its marked subtree in one pass.
    private mtd expandEveryGroup()
    {
        for row, index in .doc.report.rows where row.level and .rowLines[index] do
            .rowLines[index]!.expanded = true
        for row, index in .doc.report.rows where not row.level and .rowLines[index] do
            .list.expand(.rowLines[index]!)
    }

    // Selects again the row that was selected before the tree was rebuilt.
    private mtd restoreSelection()
    {
        if .restoreSelected >= .rowLines.count or not .rowLines[.restoreSelected]
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
        if expand do
            .expandEveryGroup()

        .list.computeLayout()
        .invalidate()
    }

    // Selects the innermost report row whose bytes contain `offset`, and returns whether one does.
    //
    // This is what turns a file offset into a place in the file's layout. Group rows carry the range
    // they cover, so an offset deep inside a section's payload still lands on that section.
    mtd revealOffset(offset: u64)->bool
    {
        let index = .doc.report.rowAt(offset)
        if index == Swag.U64.Max do
            return false
        return .selectReportRow(index)
    }

    // Selects report row `index` after opening its ancestors, and returns whether it could be selected.
    private mtd selectReportRow(index: u64, recordHistory = true)->bool
    {
        if index >= .rowLines.count do
            return false
        let line = .rowLines[index]
        if not line do
            return false

        .expandTo(line)
        let visible = .visibleIndexOf(line)
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

    private mtd reportIndexOf(line: *ListLine?)->u64
    {
        if not line do
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

    // Moves `direction` steps through the rows selected so far, and returns whether a row was selected.
    mtd navigateHistory(direction: s32)->bool
    {
        if .historyIndex == Swag.U64.Max do
            return false
        let next = cast(s64, .historyIndex) + direction
        if next < 0 or next >= cast(s64, .history.count) do
            return false

        .historyNavigating = true
        defer .historyNavigating = false
        if not .selectReportRow(.history[cast(u64, next)], recordHistory: false) do
            return false
        .historyIndex = cast(u64, next)
        .refreshHistoryCommands()
        return true
    }

    // Collects every occurrence of `text` in the cells of the rows the filter keeps.
    //
    // The decoded report is searched rather than the raw bytes, so every match is text the reader can
    // see.
    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for row, rowIndex in .doc.report.rows
        {
            if not .filterIncluded.isEmpty() and not .filterIncluded[rowIndex] do
                continue
            Viewer.collectTextMatches(row.label, text, options, rowIndex, cast(u64, Column.Field), 0, result)
            Viewer.collectTextMatches(row.value, text, options, rowIndex, cast(u64, Column.Value), 0, result)
            if row.offset != Swag.U64.Max
            {
                let offset = hexText(row.offset, 8)
                Viewer.collectTextMatches(offset, text, options, rowIndex, cast(u64, Column.Offset), 0, result)
            }

            Viewer.collectTextMatches(row.detail, text, options, rowIndex, cast(u64, Column.Detail), 0, result)
        }
    }

    // Selects the row of `match` and outlines its text, and returns whether it could be revealed.
    mtd revealMatch(match: Viewer.SearchMatch, ?: string)->bool
    {
        if match.major >= .doc.report.rows.count or match.minor > cast(u64, Column.Detail) do
            return false
        .clearSearchHighlight()
        if not .selectReportRow(match.major) do
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

    // Writes the bounds of the outlined match to `result`, and returns whether one is visible.
    mtd searchBounds(result: *Math.Rectangle)->bool
    {
        if .searchVisibleIndex == Swag.U32.Max or .searchRow >= .rowLines.count or not .rowLines[.searchRow] do
            return false
        let source = .cellText(.searchRow, .searchColumn)
        return Viewer.listCellMatchBounds(.list, .searchVisibleIndex, cast(u32, .searchColumn), source, .searchOffset, .searchLength, result)
    }

    // Removes the outline and the selection a search left behind.
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
        Viewer.collectTextMatches(row.label, query, options, 0, 0, 0, &matches)
        Viewer.collectTextMatches(row.value, query, options, 0, 0, 0, &matches)
        Viewer.collectTextMatches(row.detail, query, options, 0, 0, 0, &matches)
        if row.offset != Swag.U64.Max
        {
            let offset = hexText(row.offset, 8)
            Viewer.collectTextMatches(offset, query, options, 0, 0, 0, &matches)
        }

        return not matches.isEmpty()
    }

    // Marks the rows the filter keeps: every direct match, and each ancestor needed to reach one.
    //
    // Filtering therefore never turns a nested field into an orphan row or leaves it behind a
    // collapsed parent.
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
            catch expression.compile(.filterQuery, ignoreCase: not options.matchCase) as expressionError
            if expressionError == null do
                options.expression = &expression
        }

        for index in .doc.report.rows.count do
            .filterIncluded[index] = .rowMatchesFilter(index, options)

        // Rows are stored in preorder, so walking backward from a direct match finds each parent
        // at the first preceding shallower level. Mark that chain without leaking a match into an
        // earlier sibling branch.
        for matched in .doc.report.rows.count where .filterIncluded[matched]
        {
            var depth  = cast(u64, .doc.report.rows[matched].level)
            var parent = matched
            while depth and parent
            {
                parent -= 1
                let candidateDepth = cast(u64, .doc.report.rows[parent].level)
                if candidateDepth >= depth do
                    continue
                .filterIncluded[parent] = true
                depth = candidateDepth
            }
        }
    }

    // Shows only the rows matching `query` and their ancestors, or every row when `query` is empty.
    mtd applyFilter(query: string, options: Viewer.SearchOptions)
    {
        let enteringFilter = .filterQuery.isEmpty() and query.count
        if enteringFilter and .loadPublished do
            .captureViewState()
        .filterQuery   = query
        .filterOptions = options
        .filterOptions.expression = null
        if not .loadPublished do
            return

        .rebuildFilterIndex()
        .stopTimer(&.filterTimer)

        .beginFillList()
        if .fillListStep()
        {
            .layoutColumns()
            .invalidate()
        }
        elif not .loadTimer
        {
            .filterTimer = .addTimer(1'ms)
        }
    }

    // Opens every group between the root and `line`, outermost first.
    private mtd expandTo(line: *ListLine)
    {
        var chain: Array'(*ListLine)
        var walk = line.parent
        while walk
        {
            chain.add(walk)
            walk = walk.parent
        }

        for ancestor in chain.reversed() do
            .list.expand(ancestor)
    }

    // Returns where `line` currently sits among the visible rows, or `Swag.U32.Max`.
    private mtd visibleIndexOf(line: *ListLine)->u32
    {
        for index in .list.lineCount() where .list.lineAt(index) == line do
            return index
        return Swag.U32.Max
    }

    // Puts the whole report on the clipboard, as indented text.
    mtd copyReport()
    {
        let text = .doc.report.toText()
        Clipboard.addString(text)
    }

    // Puts the visible cells of the selected row on the clipboard.
    mtd copySelectedLine()
    {
        let line = .list.selectedLine()
        if not line do
            return

        var text: String
        for column in 4
        {
            let item = line.itemAt(cast(u32, column))
            if item.name.raw.isEmpty() do
                continue
            if not text.isEmpty() do
                text += "  "
            text += RichString.plainText(item.name.raw)
        }

        Clipboard.addString(text)
    }

    // Returns the file offset of the selected row, or zero when no selected row has one.
    private mtd selectedOffset()->u64
    {
        let selected = .selectedReportIndex()
        if selected < .doc.report.rows.count and .doc.report.rows[selected].offset != Swag.U64.Max do
            return .doc.report.rows[selected].offset
        return 0
    }

    // Selects the row covering the offset `text` names, and returns whether there is one.
    //
    // A signed offset is taken relative to the selected row.
    mtd goToTypedOffset(text: string)->bool
    {
        let target = parseOffset(text, .selectedOffset(), .doc.image.fileSize)
        if target == Swag.U64.Max do
            return false
        return .revealOffset(target)
    }

    // Asks for a file offset and selects the row that covers it.
    mtd promptGoToOffset()
    {
        let surface = .surface
        if not surface or not .doc.image.fileSize do
            return

        let currentText = hexText(.selectedOffset(), 8)

        with var options: EditDlgOptions
        {
            .title   = texts().ui_MenuGoTo
            .message = texts().ui_GoToMessage
            .text    = currentText.toString()
        }

        let dialog = EditDlg.createSingleLine(surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return
        let typed = dialog.text()
        discard .goToTypedOffset(typed)
    }

    // Creates the popup menu that offers every command of the viewer.
    mtd createCommandMenu()->*MenuCtrl
    {
        with let menu = MenuCtrl.createPopup(me, owner: me)
        {
            .addItem(Action.CopyAll)
            .addItem(Action.CopyLine)
            .addSeparator()
            .addItem(Action.ExpandAll)
            .addItem(Action.CollapseAll)
            .addSeparator()
            .addItem(Action.GoTo)
            .addItem(Action.Back)
            .addItem(Action.Forward)
        }

        return menu
    }

    // Shows the command menu at `surfacePos`, in surface coordinates.
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
        if .list == null do
            return

        let room  = Math.max(.list.listView.paddedClientRect().width, 480.0)
        let field = Math.max(room * 0.28, 180.0)
        let value = Math.max(room * 0.20, 130.0)
        let lanes = field + value + OffsetWidth + DetailMinWidth

        .list.setColumnWidth(cast(u32, Column.Field), field)
        .list.setColumnWidth(cast(u32, Column.Value), value)
        .list.setColumnWidth(cast(u32, Column.Offset), OffsetWidth)
        .list.setColumnWidth(cast(u32, Column.Detail), DetailMinWidth)

        // The separators and the leading padding belong to the header's width but to no lane, so
        // what they take is measured rather than guessed: a lane sized past it puts a horizontal
        // scrollbar under a table that had room for its content.
        let chrome = .list.header.contentWidth() - lanes
        let detail = Math.max(room - chrome - field - value - OffsetWidth, DetailMinWidth)
        .list.setColumnWidth(cast(u32, Column.Detail), detail)
        .list.computeLayout()
    }

    // Shows a card above the report for every image the document extracted.
    mtd fillPreviews()
    {
        if .doc.previews.isEmpty() do
            return

        with let band = StackLayoutCtrl.create(me, .HorizontalCenter, {0, 0, 0, 152})
        {
            .dockStyle       = .Top
            .backgroundStyle = .View
            .padding         = {12, 10, 12, 8}
            .spacing         = 8
        }

        .previewBand = band

        for preview in .doc.previews
        {
            let tile = StackLayoutCtrl.create(band, .Top, {0, 0, 160, 132})
            tile.spacing = 4
            with let image = ImageView.create(tile, {0, 0, 160, 104})
            {
                .backgroundStyle = .View
                .setImage(preview.image)
            }

            with let label = Label.create(tile, preview.label, {0, 0, 160, 24}, null, .SecondaryText | .Ellipsis)
            {
                .setTextAlignment(.Center, .Center)
            }
        }
    }

    // Fits every preview card into one restrained row.
    //
    // Large icon families get smaller cards instead of forcing a second permanent toolbar-sized band
    // into the document.
    mtd layoutPreviews()
    {
        if not .previewBand do
            return
        let band  = .previewBand
        let count = band.children.count
        if not count do
            return
        let room = Math.max(band.paddedClientRect().width - cast(f32, count - 1) * band.spacing, 1)

        // Leave one logical pixel per card for device-pixel rounding at fractional DPI scales.
        let width = Math.min(160.0, (room - cast(f32, count)) / cast(f32, count))
        for child in band.children
        {
            child.resize(width, 132)
            for item in child.children do
                item.resize(width, item.position.height)
        }

        band.computeLayout()
    }
}

impl IActionUI for Action
{
    mtd impl accept(cxt: ActionContext)->bool
    {
        switch cxt.id
        {
        case Action.CopyAll, Action.CopyLine, Action.ExpandAll, Action.CollapseAll, Action.GoTo, Action.Back, Action.Forward: return true
        }

        return false
    }

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let view  = assume cast(*Panel, cxt.wnd)
        let texts = texts()
        let theme = view.theme()

        switch cxt.id
        {
        case Action.CopyAll:
            evt.updatedFields |= .Name | .Icon | .Shortcut
            evt.name          = texts.ui_MenuCopyAll
            evt.icon          = theme.icon(.Copy)
            evt.shortcut      = "Ctrl+C"

        case Action.CopyLine:
            evt.updatedFields |= .Name | .Icon | .Disabled
            evt.name          = texts.ui_MenuCopyLine
            evt.icon          = theme.icon(.Copy)
            evt.disabled      = view.list.selectedLine() == null

        case Action.ExpandAll:
            evt.updatedFields |= .Name | .Icon | .Shortcut
            evt.name          = texts.ui_MenuExpand
            evt.icon          = theme.icon(.ChevronRight)
            evt.shortcut      = "Ctrl+E"

        case Action.CollapseAll:
            evt.updatedFields |= .Name | .Icon | .Shortcut
            evt.name          = texts.ui_MenuCollapse
            evt.icon          = theme.icon(.ChevronDown)
            evt.shortcut      = "Ctrl+Shift+E"

        case Action.GoTo:
            evt.updatedFields |= .Name | .Shortcut | .Disabled
            evt.name          = texts.ui_MenuGoTo
            evt.shortcut      = "Ctrl+G"
            evt.disabled      = not view.doc.image.fileSize

        case Action.Back:
            evt.updatedFields |= .Name | .Icon | .Shortcut | .Disabled
            evt.name          = texts.ui_MenuBack
            evt.icon          = theme.icon(.ChevronLeft)
            evt.shortcut      = "Alt+Left"
            evt.disabled      = view.historyIndex == Swag.U64.Max or not view.historyIndex

        case Action.Forward:
            evt.updatedFields |= .Name | .Icon | .Shortcut | .Disabled
            evt.name          = texts.ui_MenuForward
            evt.icon          = theme.icon(.ChevronRight)
            evt.shortcut      = "Alt+Right"
            evt.disabled      = view.historyIndex == Swag.U64.Max or view.historyIndex + 1 >= view.history.count
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let view = assume cast(*Panel, cxt.wnd)
        switch cxt.id
        {
        case Action.CopyAll:     view.copyReport()
        case Action.CopyLine:    view.copySelectedLine()
        case Action.ExpandAll:   view.setExpandedAll(true)
        case Action.CollapseAll: view.setExpandedAll(false)
        case Action.GoTo:        view.promptGoToOffset()
        case Action.Back:        discard view.navigateHistory(-1)
        case Action.Forward:     discard view.navigateHistory(1)
        }

        return true
    }
}

impl IWnd for Panel
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
                .styleLine(index, line)
            .list.invalidate()
        }
        else
        {
            evt.accepted = false
        }
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .filterTimer
        {
            if not .fillListStep() do
                return
            .stopTimer(&.filterTimer)
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
        if not state do
            return
        if not .loadPublished
        {
            if .loadThread.isValid() do
                .loadThread.wait()
            if .reloadLanguageRequested
            {
                .reloadLanguageRequested = false
                .pendingDoc = {}
                catch .startLoad() as reloadError
                if reloadError != null do
                    .publishLoadFailure(Errors.message(reloadError))
                return
            }

            if state == 2
            {
                .finishLoadTimer()
                .failureReason = #move .pendingDoc.image.failureReason
                .services.failed(me, .failureReason)
                return
            }

            if .previewBand
            {
                .previewBand.destroy()
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
            .services.showDetails(me, .details)
        }

        if not .fillListStep() do
            return
        .fillPreviews()
        .applyLayout()
        .layoutPreviews()
        .layoutColumns()
        .finishLoadTimer()
    }

    mtd impl onResizeEvent(?: *ResizeEvent)
    {
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
            .sendCommandEvent(Action.CollapseAll)
        elif evt.key == .E and evt.modifiers.has(.Control) do
            .sendCommandEvent(Action.ExpandAll)
        elif evt.key == .C and evt.modifiers.has(.Control) do
            .sendCommandEvent(Action.CopyAll)
        elif evt.key == .G and evt.modifiers.has(.Control) do
            .sendCommandEvent(Action.GoTo)
        elif evt.key == .Left and evt.modifiers.has(.Alt) do
            .sendCommandEvent(Action.Back)
        elif evt.key == .Right and evt.modifiers.has(.Alt) do
            .sendCommandEvent(Action.Forward)
        else do
            evt.accepted = false
    }

    mtd impl onDestroyEvent(?: *DestroyEvent)
    {
        .retireBlocking()
    }
}

impl Panel
{
    // Writes the column headers again in the active language.
    mtd retranslate()
    {
        let texts = texts()
        .list.header.itemAt(cast(u32, Column.Field)).name  = texts.ui_ColField
        .list.header.itemAt(cast(u32, Column.Value)).name  = texts.ui_ColValue
        .list.header.itemAt(cast(u32, Column.Offset)).name = texts.ui_ColOffset
        .list.header.itemAt(cast(u32, Column.Detail)).name = texts.ui_ColDetail
        .list.header.invalidate()
    }

    private mtd captureViewState()
    {
        .restoreExpanded.clear()
        .restoreExpanded.resize(.rowLines.count)
        for line, index in .rowLines where line do
            .restoreExpanded[index] = line.expanded
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
        .loadTexts     = texts()[]
        .loadState     = 0
        .loadPublished = false
        try .loadThread.init(&runViewerLoad, me, priority: .BelowNormal)
        try .loadThread.start()
        if not .loadTimer do
            .loadTimer = .addTimer(1'ms)
        if notify do
            .services.loadingChanged(me)
    }

    private mtd publishLoadFailure(reason: string)
    {
        .failureReason = reason
        .finishLoadTimer()
        .services.failed(me, .failureReason)
    }

    private mtd finishLoadTimer()
    {
        .stopTimer(&.loadTimer)

        .stopTimer(&.filterTimer)

        .services.loadingChanged(me)
    }

    // Asks the background read to stop, and returns whether it has ended so the viewer can be released.
    mtd retire()->bool
    {
        if .retired do
            return true
        if not .retireRequested
        {
            .retireRequested = true
            .stopTimer(&.loadTimer)

            if .loadThread.isValid() do
                .loadThread.safeForceEnd()
        }

        if .loadThread.isValid() and not .loadThread.isDone() do
            return false
        if .loadThread.isValid() do
            .loadThread.wait()
        .retired = true
        return true
    }

    // Stops the background read and waits for it to end, so the viewer can be released at once.
    mtd retireBlocking()
    {
        discard .retire()
        if .loadThread.isValid() do
            .loadThread.wait()
        .retired = true
    }

    // Creates the command group `host` registers for this viewer, and the history buttons in it.
    private mtd createCommandBar(host: Viewer.Host)
    {
        .commands = host.createCommandGroup(CommandWidth)

        let texts = texts()
        with .backButton = Viewer.createActionButton(.commands, .ChevronLeft)
        {
            .dockStyle = .Left
            .toolTip   = texts.ui_MenuBack
            .enable(false)
            .sigPressed += func|view = me|(?) { discard view.navigateHistory(-1) }
        }

        with .forwardButton = Viewer.createActionButton(.commands, .ChevronRight)
        {
            .dockStyle = .Left
            .toolTip   = texts.ui_MenuForward
            .enable(false)
            .sigPressed += func|view = me|(?) { discard view.navigateHistory(1) }
        }
    }

    // Creates the tree the report is read in.
    //
    // The whole report is read in the fixed-width font: every second lane is a number, and a column
    // of hexadecimal that does not line up is a column that has to be read twice.
    private mtd createReportList()
    {
        let texts = texts()
        with .list = ListCtrl.createMultiColumns(me)
        {
            .dockStyle = .Center
            .style.setFont(me.theme().createDefaultFontFamilyFs(me.themeMetrics().defaultFixedFontSize))
            .setSelectionMode(.Single)
            .setFirstColumnIconMargin(false)
            .updateFlags(.HotTrack | .AlternateLines)
            .addColumn(texts.ui_ColField, 320)
            .addColumn(texts.ui_ColValue, 200)
            .addColumn(texts.ui_ColOffset, OffsetWidth)
            .addColumn(texts.ui_ColDetail, 320)
            .sigRightClicked     += func|view = me|(?, position) { view.showContextMenu(view.list.listView.localToSurface(position)) }
            .sigSelectionChanged += func|view = me|(list) { view.recordHistory(view.reportIndexOf(list.selectedLine())) }
        }
    }

    // Creates the viewer of the file `host` opens, and starts reading that file in the background.
    func create(host: Viewer.Host)->*Panel fail
    {
        let services = host.services()

        with let result = Wnd.create'Panel(host.contentParent(), "scope.binary")
        {
            .backgroundStyle = .View
            .registerAction'Action()
            .services = services
        }

        result.createCommandBar(host)
        result.createReportList()

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
private func runViewerLoad(thread: Threading.Thread)
{
    let view    = cast(*Panel, thread.userParam!)
    let context = Swag.getContext()
    context.allocator = context.defaultAllocator!
    setTextsOverride(&view.loadTexts)
    let opened = view.pendingDoc.open(view.loadFileName)
    setTextsOverride(null)
    Atomic.exchange(&view.loadState, opened ? 1 : 2)
}

// Creates the integrated binary format view.
func createViewer(host: Viewer.Host)
{
    catch
    {
        let view = try Panel.create(host)
        host.attachView(view)
        host.setDetails(view.details)

        with var search = Viewer.searchApi(view)
        {
            .describe = func(presentation)
            {
                presentation.canFilter         = true
                presentation.filterPlaceholder = texts().ui_Filter
                presentation.filterToolTip     = texts().ui_FilterTip
            }

            .filter = func|view|(text, options) => view.applyFilter(text, options)
        }

        host.setSearch(search)

        with var lifecycle: Viewer.LifecycleApi
        {
            .isLoading = func|view|()->bool => view.loadTimer != null
            .retire    = func|view|()->bool => view.retire()
        }

        host.setLifecycle(lifecycle)
    } as createError
    if createError != null do
        host.reject(Errors.message(createError))
}
