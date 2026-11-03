#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core

const ComboHeadless_Item1 = "ComboHeadless.Item1"
const ComboHeadless_Item2 = "ComboHeadless.Item2"
const ComboHeadless_Item3 = "ComboHeadless.Item3"

var ComboHeadlessChangedCount: u32
var ComboHeadlessLastIdx:      u32

// Selection alignment moves only the text inside the field, leaving the arrow in place.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(440, 60)
    host.theme.colors.setLight()

    for alignment, index in [StringHorzAlignment.Left, .Center, .Right]
    {
        let combo = ComboBox.create(&host.root, Math.Rectangle{10 + cast(f32, index) * 145, 14, 130, 32})
        Swag.assert(combo.textHorizontalAlignment == .Left)
        combo.addItem("MiB")
        combo.setSelectedIndex(0, notify: false)
        combo.setTextAlignment(alignment)
    }

    var image = host.renderSettled()
    Pixel.Testing.assertImageGolden(&image, "combobox.alignment")
}

func comboHeadlessChanged(_: *ComboBox, idx: u32)
{
    ComboHeadlessChangedCount += 1
    ComboHeadlessLastIdx      = idx
}

// A live palette switch resolves every painted combo part immediately. Interaction inside one
// palette may animate, but the old palette must never remain visible while the surface changes.

// Removing items preserves order, adjusts later selections, and clears a removed selection.

// Selecting an item emits sigChanged + a command carrying the item id.

// clear() empties the item list and resets all selection state silently.

// An edit combo embeds an editbox that mirrors the selected item text.

// Keyboard control: arrows move the selection (clamped at the ends, skipping
// separators); Home/End jump to the first/last item.

// Enter opens the drop-down popup, Escape closes it.

// A combo opened with the pointer returns keyboard focus to the control that owned it once the
// popup closes, so an invisible pointer focus cannot trap subsequent navigation keys.

// A combo reached from keyboard traversal keeps its visible focus after keyboard interaction,
// preserving normal accessible combo-box navigation without creating an invisible focus owner.

// A segmented combo shows its entries side by side: a click on one chooses it and opens nothing,
// and the arrows move the choice.
