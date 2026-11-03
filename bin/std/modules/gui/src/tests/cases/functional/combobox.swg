#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const ComboHeadless_Item1 = "ComboHeadless.Item1"
const ComboHeadless_Item2 = "ComboHeadless.Item2"
const ComboHeadless_Item3 = "ComboHeadless.Item3"

var ComboHeadlessChangedCount: u32
var ComboHeadlessLastIdx:      u32

func comboHeadlessChanged(_: *ComboBox, idx: u32)
{
    ComboHeadlessChangedCount += 1
    ComboHeadlessLastIdx      = idx
}

// A live palette switch resolves every painted combo part immediately. Interaction inside one
// palette may animate, but the old palette must never remain visible while the surface changes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    host.setReducedMotion(false)

    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.addItem("One")
    combo.setSelectedIndex(0, notify: false)

    host.theme.setDark()
    host.app.notifyThemeChanged()
    host.notify(.ThemeChanged)
    combo.invalidate()
    discard host.render(&host.root)

    host.theme.setLight()
    host.app.notifyThemeChanged()
    host.notify(.ThemeChanged)
    combo.invalidate()
    discard host.render(&host.root)

    Swag.require(combo.aniBk.cur() == Color.fromVector4(combo.aniBk.destVec4))
    Swag.require(combo.aniBorder.cur() == Color.fromVector4(combo.aniBorder.destVec4))
    Swag.require(combo.aniText.cur() == Color.fromVector4(combo.aniText.destVec4))
    Swag.require(host.app.animator.activeCount() == 0)
}

// Removing items preserves order, adjusts later selections, and clears a removed selection.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    let combo = ComboBox.create(&host.root, {20, 20, 160, 26}, mode: .Editable)
    combo.addItem("One")
    combo.addItem("Two")
    combo.addItem("Three")
    combo.setSelectedIndex(2, notify: false)

    combo.removeItemAt(0)
    Swag.require(combo.items.count == 2 and combo.selectedIndex == 1)
    Swag.require(combo.selectedItem()!.name.raw == "Three")
    Swag.require(combo.editBox != null)
    Swag.require(combo.editBox.text() == "Three")

    combo.removeItemAt(1)
    Swag.require(combo.items.count == 1 and combo.selectedIndex == Swag.U32.Max)
    Swag.require(combo.selectedItem() == null and (combo.editBox.text()).count == 0)
}

// Selecting an item emits sigChanged + a command carrying the item id.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    host.recordCommands()
    ComboHeadlessChangedCount = 0
    ComboHeadlessLastIdx      = 0

    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.sigChanged += &comboHeadlessChanged
    combo.addItem("One", ComboHeadless_Item1)
    combo.addItem("Two", ComboHeadless_Item2)
    combo.addItem("Three", ComboHeadless_Item3)

    Swag.require(combo.items.count == 3)
    Swag.require(combo.selectedIndex == Swag.U32.Max)

    combo.setSelectedIndex(1)
    host.pump()
    Swag.require(combo.selectedIndex == 1)
    Swag.require(ComboHeadlessChangedCount == 1)
    Swag.require(ComboHeadlessLastIdx == 1)
    Swag.require(combo.selectedItem()!.name.raw == "Two")
    Swag.require(host.commandCount == 1)
    Swag.require(host.lastCommand == ComboHeadless_Item2)

    // Selecting the same index again is a no-op.
    combo.setSelectedIndex(1)
    host.pump()
    Swag.require(ComboHeadlessChangedCount == 1)
    Swag.require(host.commandCount == 1)

    // Clearing the selection emits U32.Max without posting an item command.
    combo.clearSelection()
    host.pump()
    Swag.require(combo.selectedIndex == Swag.U32.Max)
    Swag.require(ComboHeadlessChangedCount == 2)
    Swag.require(ComboHeadlessLastIdx == Swag.U32.Max)
    Swag.require(host.commandCount == 1)
}

// clear() empties the item list and resets all selection state silently.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.addItem("One")
    combo.addItem("Two")
    combo.setSelectedIndex(1)
    Swag.require(combo.items.count == 2)

    combo.clear()
    Swag.require(combo.items.isEmpty())
    Swag.require(combo.selectedIndex == Swag.U32.Max)
    Swag.require(combo.selectedItem() == null)
}

// An edit combo embeds an editbox that mirrors the selected item text.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    let combo = ComboBox.create(&host.root, {20, 20, 160, 26}, null, ComboBoxMode.Editable)
    Swag.require(combo.editBox != null)
    combo.addItem("Alpha")
    combo.addItem("Beta")

    combo.setSelectedIndex(1)
    host.pump()
    Swag.require(combo.editBox.text() == "Beta")
}

// Keyboard control: arrows move the selection (clamped at the ends, skipping
// separators); Home/End jump to the first/last item.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    ComboHeadlessChangedCount = 0

    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.addItem("One")
    combo.addItem("Two")
    combo.addSeparator()
    combo.addItem("Four")
    host.focus(combo)

    // First Down selects the first item.
    host.keyPress(Input.Key.Down)
    Swag.require(combo.selectedIndex == 0)

    host.keyPress(Input.Key.Down)
    Swag.require(combo.selectedIndex == 1)

    // Down skips the separator at index 2 and lands on index 3.
    host.keyPress(Input.Key.Down)
    Swag.require(combo.selectedIndex == 3)

    // No wrap-around at the end.
    host.keyPress(Input.Key.Down)
    Swag.require(combo.selectedIndex == 3)

    // Up skips the separator back to index 1.
    host.keyPress(Input.Key.Up)
    Swag.require(combo.selectedIndex == 1)

    host.keyPress(Input.Key.Home)
    Swag.require(combo.selectedIndex == 0)
    host.keyPress(Input.Key.End)
    Swag.require(combo.selectedIndex == 3)
}

// Enter opens the drop-down popup, Escape closes it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 200)
    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.addItem("One")
    combo.addItem("Two")
    host.focus(combo)

    Swag.require(combo.popup == null)
    host.keyPress(Input.Key.Return)
    Swag.require(combo.popup != null)

    host.keyPress(Input.Key.Escape)
    host.pump()
    Swag.require(combo.popup == null)
    host.app.setMouseCaptureRaw(null)
}

// A combo opened with the pointer returns keyboard focus to the control that owned it once the
// popup closes, so an invisible pointer focus cannot trap subsequent navigation keys.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 180)

    let document = RichEditCtrl.create(&host.root, {20, 20, 180, 100})
    let combo    = ComboBox.create(&host.root, {220, 20, 120, 26})
    document.setText("Document")
    combo.addItem("One")
    combo.addItem("Two")

    host.clickWnd(document)
    Swag.require(document.hasFocus())
    var comboPoint = combo.surfaceRect().center()
    combo.surface!.surfaceToScreen(&comboPoint)
    host.mouseDown(comboPoint)
    Swag.require(combo.hasFocus() and not combo.hasVisibleFocus())
    Swag.require(combo.popup != null)

    host.keyPress(Input.Key.Escape)
    Swag.require(combo.popup == null)
    Swag.require(document.hasFocus())
    host.mouseUp(comboPoint)

    host.mouseDown(comboPoint)
    Swag.require(combo.popup != null)
    combo.popup.highlightLast()
    combo.popup.commitHighlighted()
    Swag.require(combo.selectedIndex == 1)
    Swag.require(document.hasFocus())
    host.mouseUp(comboPoint)
    host.app.setMouseCaptureRaw(null)
}

// A combo reached from keyboard traversal keeps its visible focus after keyboard interaction,
// preserving normal accessible combo-box navigation without creating an invisible focus owner.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 180)

    let document = EditBox.create(&host.root, "Document", {20, 20, 180, 26})
    let combo    = ComboBox.create(&host.root, {220, 20, 120, 26})
    combo.addItem("One")
    combo.addItem("Two")

    host.clickWnd(document)
    host.keyPress(Input.Key.Tab)
    Swag.require(combo.hasFocus() and combo.hasVisibleFocus())
    host.keyPress(Input.Key.Return)
    host.keyPress(Input.Key.Escape)
    Swag.require(combo.hasFocus() and combo.hasVisibleFocus())
    host.app.setMouseCaptureRaw(null)
}

// A segmented combo shows its entries side by side: a click on one chooses it and opens nothing,
// and the arrows move the choice.
#test
{
    var host: Gui.Testing.HeadlessHost
    host.setup(480, 120)
    defer host.shutdown()

    with let combo = Gui.ComboBox.create(&host.root, {20, 20, 300, 32}, flags: .Segmented)
    {
        discard .addItem("Straight")
        discard .addItem("Curve")
        .setSelectedIndex(0, notify: false)
    }

    var changes = 0
    combo.sigChanged += func|changes = &changes|(_, _) { changes[] += 1 }

    // The second half of the frame is the second segment.
    var pt = combo.localToSurface(Math.Point{225, 16})
    combo.surface!.surfaceToScreen(&pt)
    host.click(pt)
    Swag.require(combo.selectedIndex == 1 and changes == 1)

    host.focus(combo)
    host.keyPress(.Left)
    Swag.require(combo.selectedIndex == 0 and changes == 2)

    var image = host.render(&host.root)
    Swag.require(image.isValid())
}
