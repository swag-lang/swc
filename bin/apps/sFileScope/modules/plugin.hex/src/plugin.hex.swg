#global public

using Core, Pixel, Gui, FileScopePluginApi

private const HexGlyphSize = 18.0
private const HexCommandWidth = 256.0

// Hexadecimal view of any file, whatever its size.
//
// The view owns three things: the grid the bytes are read in, the panel that spells the bytes under
// the caret in every reading a binary format uses, and the compact command group the host hosts in
// its action bar. Everything below streams — no part of this view ever holds more than one window
// of the file.
internal struct HexPluginView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:        *Wnd
        inspectorButton: *IconButton
        widthCombo:      *ComboBox
        formatCombo:     *ComboBox
        grid:            *HexGridView
        inspector:       *HexInspectorView
    }

    details: String
}

internal impl HexPluginView
{
    mtd selectedGrouping()->HexGrouping
    {
        let width  = .widthCombo.selectedIndex
        let format = .formatCombo.selectedIndex
        switch width
        {
        case 0:
            return format == 1 ? .Unsigned8 : format == 2 ? .Signed8 : .Bytes
        case 1:
            return format == 1 ? .Unsigned16 : format == 2 ? .Signed16 : .Hex16
        case 2:
            return format == 1 ? .Unsigned32 : format == 2 ? .Signed32 : format == 3 ? .Float32 : .Hex32
        default:
            return format == 1 ? .Unsigned64 : format == 2 ? .Signed64 : format == 3 ? .Float64 : .Hex64
        }
    }

    mtd applyValueMode()
    {
        .grid.setGrouping(.selectedGrouping())
    }

    mtd rebuildFormats()
    {
        let previous = .formatCombo.selectedIndex
        .formatCombo.clear()
        .formatCombo.addItem("Hex")
        .formatCombo.addItem("Unsigned")
        .formatCombo.addItem("Signed")
        if .widthCombo.selectedIndex >= 2 do
            .formatCombo.addItem("Float")
        let next = previous < .formatCombo.items.count ? previous : 0
        .formatCombo.setSelectedIndex(cast(u32) next, notify: false)
        .applyValueMode()
    }

    // Refreshes the value panel when the caret changes. The offset lives beside the value it
    // qualifies in that panel; Ctrl+G and the context menu keep navigation out of the toolbar.
    mtd caretMoved()
    {
        if .inspector.isLocallyVisible() do
            .inspector.refresh()
    }

    mtd showInspector(visible: bool)
    {
        if visible do
            .inspector.show()
        else do
            .inspector.hide()
        .inspectorButton.setChecked(visible)
        .applyLayout()
        if visible do
            .inspector.refresh()
        .grid.refreshLayout()
        .invalidate()
    }

    mtd toggleInspector()
    {
        .showInspector(!.inspector.isLocallyVisible())
    }

    // Reveals the byte range the host's search matched.
    mtd revealOffset(offset: u64, text: string)->bool
    {
        if !.grid.revealRange(offset, @countof(text)) do
            return false
        .caretMoved()
        .grid.setFocus()
        return true
    }
}

internal impl IWnd for HexPluginView
{
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed and evt.key == .I and evt.modifiers.has(.Control) do
            .toggleInspector()
        else do
            evt.accepted = false
    }
}

internal impl HexPluginView
{
    func create(contentParent, commandParent: *Wnd, fileName: string)->*HexPluginView
    {
        let result = Wnd.create'HexPluginView(contentParent, "sFileScope.hex")
        result.backgroundStyle = .View

        result.commands                 = Wnd.create'Wnd(commandParent, {0, 0, HexCommandWidth, 36})
        result.commands.backgroundStyle = .Window

        with result.inspectorButton = IconButton.create(result.commands, result.theme().icon(.Information, HexGlyphSize), {0, 0, 36, 36}, flags: .Toggle)
        {
            .dockStyle         = .Left
            .margin.x          = 8
            .toolTip           = "Value inspector (Ctrl+I)"
            .sigCheckedChanged += func|view = result|(button)
            {
                view.showInspector(button.isChecked)
            }
        }

        with result.widthCombo = ComboBox.create(result.commands, {0, 0, 80, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = "Value width"
            .addItem("8-bit")
            .addItem("16-bit")
            .addItem("32-bit")
            .addItem("64-bit")
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = result|(combo, index)
            {
                discard combo
                discard index
                view.rebuildFormats()
            }
        }

        with result.formatCombo = ComboBox.create(result.commands, {0, 0, 116, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = "Value representation"
            .addItem("Hex")
            .addItem("Unsigned")
            .addItem("Signed")
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = result|(combo, index)
            {
                discard combo
                discard index
                view.applyValueMode()
            }
        }

        result.grid      = HexGridView.create(result, fileName)
        result.inspector = HexInspectorView.create(result, result.grid)
        result.inspectorButton.setChecked(true)
        result.grid.sigCaretChanged += func|view = result|(grid)
        {
            discard grid
            view.caretMoved()
        }

        result.details = "hex, text, and values · streamed"
        result.applyLayout()
        result.grid.refreshLayout()
        result.caretMoved()
        result.setInitialFocus(result.grid)
        return result
    }
}

// Creates the hexadecimal view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd, details: *String, revealMatch: *#null ViewerRevealMatch)->#null *Wnd
{
    if apiVersion != ViewerPluginApiVersion do
        return null
    let view = HexPluginView.create(contentParent, commandParent, fileName)
    revealMatch[] = func(wnd, offset, text)->bool { return (cast(*HexPluginView) wnd).revealOffset(offset, text) }
    commands[]    = view.commands
    details[]     = view.details
    return view
}
