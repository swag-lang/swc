#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
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
    ComboHeadlessLastIdx = idx
}

// Selecting an item emits sigChanged + a command carrying the item id.
#test
{
    var host: GuiHeadlessHost
    host.setup(240, 80)
    host.recordCommands()
    ComboHeadlessChangedCount = 0
    ComboHeadlessLastIdx = 0

    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.sigChanged += &comboHeadlessChanged
    combo.addItem("One", ComboHeadless_Item1)
    combo.addItem("Two", ComboHeadless_Item2)
    combo.addItem("Three", ComboHeadless_Item3)

    @assert(combo.items.count == 3)
    @assert(combo.selectedIdx == Swag.U32.Max)

    combo.selectItem(1)
    host.pump()
    @assert(combo.selectedIdx == 1)
    @assert(ComboHeadlessChangedCount == 1)
    @assert(ComboHeadlessLastIdx == 1)
    @assert(combo.getSelectedItem().name.raw == "Two")
    @assert(host.commandCount == 1)
    @assert(host.lastCommand == ComboHeadless_Item2)

    // Selecting the same index again is a no-op.
    combo.selectItem(1)
    host.pump()
    @assert(ComboHeadlessChangedCount == 1)
    @assert(host.commandCount == 1)

    // Out-of-range index deselects (signal with U32.Max, no command).
    combo.selectItem(99)
    host.pump()
    @assert(combo.selectedIdx == Swag.U32.Max)
    @assert(ComboHeadlessChangedCount == 2)
    @assert(ComboHeadlessLastIdx == Swag.U32.Max)
    @assert(host.commandCount == 1)

    host.shutdown()
}

// clear() empties the item list.
#test
{
    var host: GuiHeadlessHost
    host.setup(240, 80)

    let combo = ComboBox.create(&host.root, {20, 20, 160, 26})
    combo.addItem("One")
    combo.addItem("Two")
    @assert(combo.items.count == 2)

    combo.clear()
    @assert(combo.items.count == 0)

    host.shutdown()
}

// An edit combo embeds an editbox that mirrors the selected item text.
#test
{
    var host: GuiHeadlessHost
    host.setup(240, 80)

    let combo = ComboBox.create(&host.root, {20, 20, 160, 26}, null, ComboBoxKind.Edit)
    @assert(combo.editBox != null)
    combo.addItem("Alpha")
    combo.addItem("Beta")

    combo.selectItem(1)
    host.pump()
    @assert(combo.editBox.getText() == "Beta")

    host.shutdown()
}
