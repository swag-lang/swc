#global if #command == Swag.CompilerCommand.Test
#global private

using Pixel
using Swag, Core

var PalettePickerHeadlessChangedCount: u32

func palettePickerHeadlessChanged(picker: *PalettePicker)
{
    discard picker
    PalettePickerHeadlessChangedCount += 1
}

// Colors can be added individually and in generated ranges.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    let picker = PalettePicker.create(&host.root, {10, 10, 220, 100})
    Swag.assert(picker.colors.count == 0)
    Swag.assert(picker.selectedIndex == Swag.S32.Max)

    picker.addColor(Argb.Red)
    picker.addColor(Argb.Blue)
    Swag.assert(picker.colors.count == 2)
    Swag.assert(picker.colors[0] == Argb.Red)

    picker.addHueRamp(8, 1, 0.5)
    Swag.assert(picker.colors.count == 10)
}

// Mouse and keyboard selection share one index, color, and notification contract.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    PalettePickerHeadlessChangedCount = 0

    let picker = PalettePicker.create(&host.root, {10, 10, 220, 100})
    picker.setItemMetrics(24, 3)
    picker.addColor(Argb.Red)
    picker.addColor(Argb.Green)
    picker.addColor(Argb.Blue)
    picker.sigSelectionChanged += &palettePickerHeadlessChanged

    // Hit testing is valid before the first paint.
    host.click({22, 22})
    Swag.assert(picker.selectedIndex == 0)
    Swag.assert(picker.selectedColor == Argb.Red)
    Swag.assert(PalettePickerHeadlessChangedCount == 1)

    host.focus(picker)
    host.keyPress(Input.Key.Right)
    Swag.assert(picker.selectedIndex == 1)
    Swag.assert(picker.selectedColor == Argb.Green)
    host.keyPress(Input.Key.End)
    Swag.assert(picker.selectedIndex == 2)
    Swag.assert(PalettePickerHeadlessChangedCount == 3)

    picker.clearSelection(notify: false)
    Swag.assert(picker.selectedIndex == Swag.S32.Max)
    Swag.assert(PalettePickerHeadlessChangedCount == 3)
}
