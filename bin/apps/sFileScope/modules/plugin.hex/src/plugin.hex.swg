#global public

using Core, Pixel, Gui, FileScopePluginApi

private const HexGlyphSize = 18.0
private const HexCommandWidth = 388.0
private const HexOffsetWidth = 120.0

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
        menuButton:      *IconButton
        inspectorButton: *IconButton
        groupingCombo:   *ComboBox
        offsetButton:    *PushButton
        grid:            *HexGridView
        inspector:       *HexInspectorView
    }

    details: String
}

internal impl HexPluginView
{
    // Refreshes the caret readout and, when it is showing, the value panel.
    mtd caretMoved()
    {
        var offsetText: Array'u8
        offsetText.add('0'u8)
        offsetText.add('x'u8)
        appendHexDigits(&offsetText, .grid.caret, .grid.offsetDigits)
        .offsetButton.setText(@mkstring(offsetText.buffer!, offsetText.count))

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

        with result.menuButton = IconButton.create(result.commands, result.theme().icon(.More, HexGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = "Copy, row width, and navigation"
            .sigPressed += func|view = result|(button)
            {
                var position = button.surfaceRect()
                view.grid.showContextMenu({position.x, position.bottom()})
            }
        }

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

        with result.groupingCombo = ComboBox.create(result.commands, {0, 0, 164, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = "Value grouping"
            .addItem("Bytes (8-bit)")
            .addItem("Unsigned 16-bit")
            .addItem("Unsigned 32-bit")
            .addItem("Unsigned 64-bit")
            .addItem("Signed 16-bit")
            .addItem("Signed 32-bit")
            .addItem("Signed 64-bit")
            .addItem("Float 32-bit")
            .addItem("Float 64-bit")
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = result|(combo, index)
            {
                discard combo
                view.grid.setGrouping(cast(HexGrouping) index)
            }
        }

        with result.offsetButton = PushButton.create(result.commands, "0x00000000", {0, 0, HexOffsetWidth, 36})
        {
            .dockStyle = .Right
            .toolTip   = "Go to offset (Ctrl+G)"
            .style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.grid.promptGoToOffset()
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
