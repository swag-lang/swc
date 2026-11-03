#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const PopupHeadless_Item2 = "PopupHeadless.Item2"

var PopupHeadlessChangedCount:  u32
var PopupListContentPaintCount: u32
var PopupListContentPaintFlags: PaintItemFlags

func popupHeadlessChanged(_: *ComboBox, _: u32)
{
    PopupHeadlessChangedCount += 1
}

func popupListContentPainter(_: *PopupListCtrlItem, _: *PaintContext, _: Math.Rectangle, flags: PaintItemFlags)
{
    PopupListContentPaintCount += 1
    PopupListContentPaintFlags = flags
}

// Clicking a (select) combobox opens its popup; selecting an item closes it
// and updates the selection.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 200)
    host.recordCommands()
    PopupHeadlessChangedCount = 0

    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.sigChanged += &popupHeadlessChanged
    combo.addItem("One")
    combo.addItem("Two", PopupHeadless_Item2)
    combo.addItem("Three")

    Swag.require(combo.popup == null)

    host.click({100, 33})
    Swag.require(combo.popup != null)

    // Selecting item 1 via the popup routes back to the combobox.
    let popup = combo.popup
    popup.sigClosed!(popup, 1)
    host.pump()
    Swag.require(combo.popup == null)
    Swag.require(combo.selectedIndex == 1)
    Swag.require(PopupHeadlessChangedCount == 1)
    Swag.require(host.lastCommand == PopupHeadless_Item2)

    host.app.setMouseCaptureRaw(null)
}

// Clicking an open combobox again hides the popup.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 200)
    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.addItem("One")
    combo.addItem("Two")

    host.click({100, 33})
    Swag.require(combo.popup != null)

    // The open popup captured the mouse; closing it via its own dismiss path.
    let popup = combo.popup
    popup.sigClosed!(popup, Swag.U32.Max)
    host.pump()
    Swag.require(combo.popup == null)
    Swag.require(combo.selectedIndex == Swag.U32.Max)

    host.app.setMouseCaptureRaw(null)
}

// PopupListCtrl data model: items and separators.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 200)
    let popup = PopupListCtrl.create(&host.root)
    Swag.require(popup.itemHeight == 24)
    Swag.require(popup.iconSize == 16)
    popup.addItem("A")
    popup.addSeparator()
    popup.addItem("B")

    Swag.require(popup.items.count == 3)
    Swag.require(not popup.items[0]!.isSeparator)
    Swag.require(popup.items[1]!.isSeparator)
    Swag.require(popup.selectedIndex == Swag.U32.Max)

    popup.itemHeight      = 30
    popup.separatorHeight = 8
    popup.show(20, 20, 100)
    Swag.require(popup.scrollWnd.scrollSize.y == 68)
    host.app.setMouseCaptureRaw(null)

    popup.destroy()
    host.pump()
}

// A list whose entries are painted samples opens with nothing highlighted.
//
// Its check mark already says which entry is current, and the opening highlight would put the
// accent ground behind that entry's sample as well: a sample of a stroke then reads as a bar of
// colour rather than as the stroke it draws.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 200)

    let popup = PopupListCtrl.create(&host.root)
    popup.addItem("A")
    popup.addItem("B")
    popup.setSelectedIndex(1)
    popup.show(20, 20, 100)

    let view = assume cast (*PopupListView, popup.scrollWnd.view)
    Swag.require(view.hotIdx == 1)
    host.app.setMouseCaptureRaw(null)
    popup.destroy()
    host.pump()

    let marked = PopupListCtrl.create(&host.root)
    marked.markSelectionOnly = true
    marked.addItem("A")
    marked.addItem("B")
    marked.setSelectedIndex(1)
    marked.show(20, 20, 100)

    let markedView = assume cast (*PopupListView, marked.scrollWnd.view)
    Swag.require(markedView.hotIdx == Swag.U32.Max)

    // The keyboard still starts from the selection, so the first step up lands before it.
    marked.moveHighlight(-1)
    Swag.require(markedView.hotIdx == 0)

    host.app.setMouseCaptureRaw(null)
    marked.destroy()
    host.pump()
}

// A visual preset remains a popup-list row: it gets the list's checked and hot state instead of
// borrowing an icon-button rail for a piece of custom content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 200)
    PopupListContentPaintCount = 0
    PopupListContentPaintFlags = .None

    let popup = PopupListCtrl.create(&host.root)
    let item  = popup.addItem("")
    item.contentPainter = &popupListContentPainter
    popup.setSelectedIndex(0)
    popup.show(20, 20, 100)
    discard host.render()

    Swag.require(PopupListContentPaintCount == 1)
    Swag.require(PopupListContentPaintFlags.has(.Checked))

    host.app.setMouseCaptureRaw(null)
    popup.destroy()
    host.pump()
}
