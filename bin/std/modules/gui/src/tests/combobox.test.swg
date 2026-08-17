#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const ComboHeadless_Item1 = "ComboHeadless.Item1"
const ComboHeadless_Item2 = "ComboHeadless.Item2"
const ComboHeadless_Item3 = "ComboHeadless.Item3"

var ComboHeadlessChangedCount: u32
var ComboHeadlessLastIdx:      u32

func comboHeadlessChanged(combo: *ComboBox, idx: u32)
{
    discard combo
    ComboHeadlessChangedCount += 1
    ComboHeadlessLastIdx      = idx
}

// A live palette switch resolves every painted combo part immediately. Interaction inside one
// palette may animate, but the old palette must never remain visible while the surface changes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    defer host.shutdown()
    host.setReducedMotion(false)

    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.addItem("One")
    combo.setSelectedIndex(0, notify: false)

    host.theme.setSwagDark()
    host.app.notifyThemeChanged()
    host.notify(.ThemeChanged)
    combo.invalidate()
    var dark = host.render(&host.root)
    discard dark

    host.theme.setSwagLight()
    host.app.notifyThemeChanged()
    host.notify(.ThemeChanged)
    combo.invalidate()
    var light = host.render(&host.root)
    discard light

    @assert(combo.aniBk.cur() == Color.fromVector4(combo.aniBk.destVec4))
    @assert(combo.aniBorder.cur() == Color.fromVector4(combo.aniBorder.destVec4))
    @assert(combo.aniText.cur() == Color.fromVector4(combo.aniText.destVec4))
    @assert(host.app.animator.activeCount() == 0)
}

// Removing items preserves order, adjusts later selections, and clears a removed selection.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    defer host.shutdown()
    let combo = ComboBox.create(&host.root, {20, 20, 160, 26}, mode: .Editable)
    combo.addItem("One")
    combo.addItem("Two")
    combo.addItem("Three")
    combo.setSelectedIndex(2, notify: false)

    combo.removeItemAt(0)
    @assert(combo.items.count == 2 and combo.selectedIndex == 1)
    @assert(combo.selectedItem()!.name.raw == "Three")
    @assert(combo.editBox != null)
    @assert(combo.editBox.text() == "Three")

    combo.removeItemAt(1)
    @assert(combo.items.count == 1 and combo.selectedIndex == Swag.U32.Max)
    @assert(combo.selectedItem() == null and @countof(combo.editBox.text()) == 0)
}

// Selecting an item emits sigChanged + a command carrying the item id.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    defer host.shutdown()
    host.recordCommands()
    ComboHeadlessChangedCount = 0
    ComboHeadlessLastIdx      = 0

    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.sigChanged += &comboHeadlessChanged
    combo.addItem("One", ComboHeadless_Item1)
    combo.addItem("Two", ComboHeadless_Item2)
    combo.addItem("Three", ComboHeadless_Item3)

    @assert(combo.items.count == 3)
    @assert(combo.selectedIndex == Swag.U32.Max)

    combo.setSelectedIndex(1)
    host.pump()
    @assert(combo.selectedIndex == 1)
    @assert(ComboHeadlessChangedCount == 1)
    @assert(ComboHeadlessLastIdx == 1)
    @assert(combo.selectedItem()!.name.raw == "Two")
    @assert(host.commandCount == 1)
    @assert(host.lastCommand == ComboHeadless_Item2)

    // Selecting the same index again is a no-op.
    combo.setSelectedIndex(1)
    host.pump()
    @assert(ComboHeadlessChangedCount == 1)
    @assert(host.commandCount == 1)

    // Clearing the selection emits U32.Max without posting an item command.
    combo.clearSelection()
    host.pump()
    @assert(combo.selectedIndex == Swag.U32.Max)
    @assert(ComboHeadlessChangedCount == 2)
    @assert(ComboHeadlessLastIdx == Swag.U32.Max)
    @assert(host.commandCount == 1)
}

// clear() empties the item list and resets all selection state silently.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    defer host.shutdown()
    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.addItem("One")
    combo.addItem("Two")
    combo.setSelectedIndex(1)
    @assert(combo.items.count == 2)

    combo.clear()
    @assert(combo.items.count == 0)
    @assert(combo.selectedIndex == Swag.U32.Max)
    @assert(combo.selectedItem() == null)
}

// An edit combo embeds an editbox that mirrors the selected item text.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    defer host.shutdown()
    let combo = ComboBox.create(&host.root, {20, 20, 160, 26}, null, ComboBoxMode.Editable)
    @assert(combo.editBox != null)
    combo.addItem("Alpha")
    combo.addItem("Beta")

    combo.setSelectedIndex(1)
    host.pump()
    @assert(combo.editBox!.text() == "Beta")
}

// Keyboard control: arrows move the selection (clamped at the ends, skipping
// separators); Home/End jump to the first/last item.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)
    defer host.shutdown()
    ComboHeadlessChangedCount = 0

    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.addItem("One")
    combo.addItem("Two")
    combo.addSeparator()
    combo.addItem("Four")
    host.focus(combo)

    // First Down selects the first item.
    host.keyPress(Input.Key.Down)
    @assert(combo.selectedIndex == 0)

    host.keyPress(Input.Key.Down)
    @assert(combo.selectedIndex == 1)

    // Down skips the separator at index 2 and lands on index 3.
    host.keyPress(Input.Key.Down)
    @assert(combo.selectedIndex == 3)

    // No wrap-around at the end.
    host.keyPress(Input.Key.Down)
    @assert(combo.selectedIndex == 3)

    // Up skips the separator back to index 1.
    host.keyPress(Input.Key.Up)
    @assert(combo.selectedIndex == 1)

    host.keyPress(Input.Key.Home)
    @assert(combo.selectedIndex == 0)
    host.keyPress(Input.Key.End)
    @assert(combo.selectedIndex == 3)
}

// Enter opens the drop-down popup, Escape closes it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 200)
    defer host.shutdown()
    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.addItem("One")
    combo.addItem("Two")
    host.focus(combo)

    @assert(combo.popup == null)
    host.keyPress(Input.Key.Return)
    @assert(combo.popup != null)

    host.keyPress(Input.Key.Escape)
    host.pump()
    @assert(combo.popup == null)
    host.app.setMouseCaptureRaw(null)
}

// A combo opened with the pointer returns keyboard focus to the control that owned it once the
// popup closes, so an invisible pointer focus cannot trap subsequent navigation keys.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 180)
    defer host.shutdown()

    let document = RichEditCtrl.create(&host.root, {20, 20, 180, 100})
    let combo    = ComboBox.create(&host.root, {220, 20, 120, 26})
    document.setText("Document")
    combo.addItem("One")
    combo.addItem("Two")

    host.clickWnd(document)
    @assert(document.hasFocus())
    var comboPoint = combo.surfaceRect().center()
    combo.surface!.surfaceToScreen(&comboPoint)
    host.mouseDown(comboPoint)
    @assert(combo.hasFocus() and !combo.hasVisibleFocus())
    @assert(combo.popup != null)

    host.keyPress(Input.Key.Escape)
    @assert(combo.popup == null)
    @assert(document.hasFocus())
    host.mouseUp(comboPoint)

    host.mouseDown(comboPoint)
    @assert(combo.popup != null)
    combo.popup!.highlightLast()
    combo.popup!.commitHighlighted()
    @assert(combo.selectedIndex == 1)
    @assert(document.hasFocus())
    host.mouseUp(comboPoint)
    host.app.setMouseCaptureRaw(null)
}

// A combo reached from keyboard traversal keeps its visible focus after keyboard interaction,
// preserving normal accessible combo-box navigation without creating an invisible focus owner.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 180)
    defer host.shutdown()

    let document = EditBox.create(&host.root, "Document", {20, 20, 180, 26})
    let combo    = ComboBox.create(&host.root, {220, 20, 120, 26})
    combo.addItem("One")
    combo.addItem("Two")

    host.clickWnd(document)
    host.keyPress(Input.Key.Tab)
    @assert(combo.hasFocus() and combo.hasVisibleFocus())
    host.keyPress(Input.Key.Return)
    host.keyPress(Input.Key.Escape)
    @assert(combo.hasFocus() and combo.hasVisibleFocus())
    host.app.setMouseCaptureRaw(null)
}
