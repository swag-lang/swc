#global public

using Core, Pixel, Gui, FileScopePluginApi

private const BinaryGlyphSize = 18.0
private const BinaryCommandWidth = 36.0
private const BinaryOffsetWidth = 116.0
private const BinaryDetailMinWidth = 200.0

// Commands shared by the context menu, keyboard, and command bar.
internal struct ActionBinary {}

internal impl ActionBinary
{
    newCmdId("CopyAll")
    newCmdId("CopyLine")
    newCmdId("ExpandAll")
    newCmdId("CollapseAll")
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
internal struct BinaryPluginView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:     *Wnd
        copyButton:   *IconButton
        list:         *ListCtrl
    }

    doc:      BinaryDocument
    rowLines: Array'(#null *ListLine)     // Line created for each report row, in row order.
    details:  String
}

internal impl BinaryPluginView
{
    // Rebuilds the tree from the report, parents before the rows they own.
    mtd fillList()
    {
        .list.clear()
        .rowLines.clear()
        .rowLines.resize(.doc.report.rows.count)

        let faint = .themeColors().label_TextFaint

        // One entry per depth, holding the row every deeper row currently hangs from.
        var parents: Array'(#null *ListLine)

        for row, index in .doc.report.rows
        {
            let depth = cast(u64) row.level
            var parent: #null *ListLine = null
            if depth and depth <= parents.count do
                parent = parents[depth - 1]

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

            // A note is not a field of the file; it says what the file did not let the reader see,
            // so it is written in the same faint ink every secondary reading uses.
            if row.kind == .Note do
                line.colorFg = faint

            parents.resize(depth + 1)
            parents[depth]   = line
            .rowLines[index] = line
        }

        .applyInitialExpansion()
        .list.computeLayout()
    }

    // Opens the groups the report asked to start open.
    //
    // A row the list has not made visible cannot be expanded through the list, so the deeper groups
    // are only marked; expanding a root then inserts its whole marked subtree in one pass.
    private mtd applyInitialExpansion()
    {
        for row, index in .doc.report.rows where row.open and row.level and .rowLines[index] do
            .rowLines[index]!.expanded = true
        for row, index in .doc.report.rows where row.open and !row.level and .rowLines[index] do
            .list.expand(.rowLines[index]!)
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
        if index == Swag.U64.Max or index >= .rowLines.count do
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
        return true
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
            text += item.name.raw.toString()
        }

        Clipboard.addString(text.toString())
    }

    mtd showContextMenu(surfacePos: Math.Point)
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(ActionBinary.CopyAll)
        menu.addItem(ActionBinary.CopyLine)
        menu.addSeparator()
        menu.addItem(ActionBinary.ExpandAll)
        menu.addItem(ActionBinary.CollapseAll)
        discard menu.doModal(surfacePos, .TopLeft, autoDestroy: true)
    }

    // Divides the visible width into the four lanes a row is read across.
    //
    // The meaning lane takes what the other three leave, because it is the only one whose content
    // has no natural width: a flag list is as long as the flags that are set.
    mtd layoutColumns()
    {
        if !@isset(.list) do
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
}

internal impl IActionUI for ActionBinary
{
    mtd impl accept(cxt: ActionContext)->bool
    {
        switch cxt.id
        {
        case ActionBinary.CopyAll, ActionBinary.CopyLine, ActionBinary.ExpandAll, ActionBinary.CollapseAll: return true
        }

        return false
    }

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let view  = cast(*BinaryPluginView) cxt.wnd!
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
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let view = cast(*BinaryPluginView) cxt.wnd!
        switch cxt.id
        {
        case ActionBinary.CopyAll:     view.copyReport()
        case ActionBinary.CopyLine:    view.copySelectedLine()
        case ActionBinary.ExpandAll:   view.setExpandedAll(true)
        case ActionBinary.CollapseAll: view.setExpandedAll(false)
        }

        return true
    }
}

internal impl IWnd for BinaryPluginView
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
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
        else do
            evt.accepted = false
    }
}

internal impl BinaryPluginView
{
    func create(contentParent, commandParent: *Wnd, fileName: string)->*BinaryPluginView
    {
        registerBinaryStrings(contentParent.app())
        let s = binStrings()

        let result = Wnd.create'BinaryPluginView(contentParent, "sFileScope.binary")
        result.backgroundStyle = .View
        result.registerAction'ActionBinary()

        result.commands                 = Wnd.create'Wnd(commandParent, {0, 0, BinaryCommandWidth, 36})
        result.commands.backgroundStyle = .Window

        with result.copyButton = IconButton.create(result.commands, result.theme().icon(.Copy, BinaryGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = s.ui_MenuCopyAll
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.sendCommandEvent(ActionBinary.CopyAll)
            }
        }

        // The whole report is read in the fixed-width font: every second lane is a number, and a
        // column of hexadecimal that does not line up is a column that has to be read twice.
        with result.list = ListCtrl.createMultiColumns(result)
        {
            .dockStyle = .Center
            .style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
            .setSelectionMode(.Single)
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
        }

        if !result.doc.open(fileName)
        {
            result.list.hide()
            with let label = Label.create(result, s.ui_Unreadable, {}, null, .WordWrap | .SecondaryText)
            {
                .dockStyle = .Center
                .setTextAlignment(.Center, .Center)
            }

            result.details = s.ui_Unreadable
            result.applyLayout()
            return result
        }

        result.fillList()
        result.details = result.doc.report.summary
        result.applyLayout()
        result.layoutColumns()
        result.setInitialFocus(result.list)
        return result
    }
}

// Creates the binary format view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd, details: *String, revealMatch: *#null ViewerRevealMatch)->#null *Wnd
{
    if apiVersion != ViewerPluginApiVersion do
        return null
    let view = BinaryPluginView.create(contentParent, commandParent, fileName)
    revealMatch[] = func(wnd, offset, text)->bool { return (cast(*BinaryPluginView) wnd).revealOffset(offset, text) }
    commands[]    = view.commands
    details[]     = view.details
    return view
}
