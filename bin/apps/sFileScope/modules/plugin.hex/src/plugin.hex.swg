#global public

using Core, Pixel, Gui

private const HexCommandWidth = 376.0

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
        commands:    *Wnd
        widthCombo:  *ComboBox
        formatCombo: *ComboBox
        byteOrder:   *CheckButton
        grid:        *HexGridView
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
        case 0:  return format == 1 ? .Unsigned8 : format == 2 ? .Signed8 : .Bytes
        case 1:  return format == 1 ? .Unsigned16 : format == 2 ? .Signed16 : .Hex16
        case 2:  return format == 1 ? .Unsigned32 : format == 2 ? .Signed32 : format == 3 ? .Float32 : .Hex32
        default: return format == 1 ? .Unsigned64 : format == 2 ? .Signed64 : format == 3 ? .Float64 : .Hex64
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
        .formatCombo.addItem(hexStrings().ui_FormatHex)
        .formatCombo.addItem(hexStrings().ui_FormatUns)
        .formatCombo.addItem(hexStrings().ui_FormatSigned)
        if .widthCombo.selectedIndex >= 2 do
            .formatCombo.addItem(hexStrings().ui_FormatFloat)
        let next = previous < .formatCombo.items.count ? previous : 0
        .formatCombo.setSelectedIndex(cast(u32) next, notify: false)
        .applyValueMode()
    }

    // Reveals the byte range the host's search matched.
    mtd revealOffset(offset: u64, text: string)->bool
    {
        if !.grid.revealRange(offset, @countof(text)) do
            return false
        .grid.setFocus()
        return true
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

        with result.widthCombo = ComboBox.create(result.commands, {0, 0, 80, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = hexStrings().ui_TipWidth
            .addItem(hexStrings().ui_Width8)
            .addItem(hexStrings().ui_Width16)
            .addItem(hexStrings().ui_Width32)
            .addItem(hexStrings().ui_Width64)
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
            .toolTip   = hexStrings().ui_TipFormat
            .addItem(hexStrings().ui_FormatHex)
            .addItem(hexStrings().ui_FormatUns)
            .addItem(hexStrings().ui_FormatSigned)
            .setSelectedIndex(0, notify: false)
            .sigChanged += func|view = result|(combo, index)
            {
                discard combo
                discard index
                view.applyValueMode()
            }
        }

        with result.byteOrder = CheckButton.create(result.commands, hexStrings().ui_Endian, {0, 0, 132, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = hexStrings().ui_TipEndian
            .setState(.Checked)
            .sigChanged += func|view = result|(button)
            {
                view.grid.setBigEndian(!button.isChecked())
            }
        }

        result.grid = HexGridView.create(result, fileName)

        result.details = hexStrings().ui_Details
        result.applyLayout()
        result.grid.refreshLayout()
        result.setInitialFocus(result.grid)
        return result
    }
}

// Creates the hexadecimal view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(request: const *ViewerRequest, result: *ViewerResult)->bool
{
    if request.apiVersion != ViewerPluginApiVersion do
        return false

    registerHexStrings(request.contentParent.app())
    let view = HexPluginView.create(request.contentParent, request.commandParent, request.fileName)
    result.view        = view
    result.commands    = view.commands
    result.details     = view.details
    result.revealMatch = func(wnd, offset, text)->bool { return (cast(*HexPluginView) wnd).revealOffset(offset, text) }
    return true
}
