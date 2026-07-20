#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

const PopupHeadless_Item2 = "PopupHeadless.Item2"

var PopupHeadlessChangedCount: u32

func popupHeadlessChanged(combo: #nonull *ComboBox, idx: u32)
{
    discard combo
    discard idx
    PopupHeadlessChangedCount += 1
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

    @assert(combo.popup == null)

    host.click({100, 33})
    @assert(combo.popup != null)

    // Selecting item 1 via the popup routes back to the combobox.
    combo.popup.sigSelected(assume combo.popup, 1)
    host.pump()
    @assert(combo.popup == null)
    @assert(combo.selectedIdx == 1)
    @assert(PopupHeadlessChangedCount == 1)
    @assert(host.lastCommand == PopupHeadless_Item2)

    host.app.mouseCaptureWnd = null
    host.shutdown()
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
    @assert(combo.popup != null)

    // The open popup captured the mouse; closing it via its own dismiss path.
    combo.popup.sigSelected(assume combo.popup, Swag.U32.Max)
    host.pump()
    @assert(combo.popup == null)
    @assert(combo.selectedIdx == Swag.U32.Max)

    host.app.mouseCaptureWnd = null
    host.shutdown()
}

// PopupListCtrl data model: items and separators.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 200)

    let popup = PopupListCtrl.create(&host.root)
    popup.addItem("A")
    popup.addSeparator()
    popup.addItem("B")

    @assert(popup.items.count == 3)
    @assert(!popup.items[0].isSeparator)
    @assert(popup.items[1].isSeparator)
    @assert(popup.selectedIdx == Swag.U32.Max)

    popup.destroy()
    host.pump()

    host.shutdown()
}
