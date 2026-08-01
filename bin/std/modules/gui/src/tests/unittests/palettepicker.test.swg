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

    let picker = PalettePicker.create(&host.root, {10, 10, 220, 100})
    @assert(picker.colors.count == 0)
    @assert(picker.selectedIndex == Swag.S32.Max)

    picker.addColor(Argb.Red)
    picker.addColor(Argb.Blue)
    @assert(picker.colors.count == 2)
    @assert(picker.colors[0] == Argb.Red)

    picker.addHueRamp(8, 1, 0.5)
    @assert(picker.colors.count == 10)

    host.shutdown()
}

// Mouse and keyboard selection share one index, color, and notification contract.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    PalettePickerHeadlessChangedCount = 0

    let picker = PalettePicker.create(&host.root, {10, 10, 220, 100})
    picker.setItemMetrics(24, 3)
    picker.addColor(Argb.Red)
    picker.addColor(Argb.Green)
    picker.addColor(Argb.Blue)
    picker.sigSelectionChanged += &palettePickerHeadlessChanged

    // Hit testing is valid before the first paint.
    host.click({22, 22})
    @assert(picker.selectedIndex == 0)
    @assert(picker.selectedColor == Argb.Red)
    @assert(PalettePickerHeadlessChangedCount == 1)

    host.focus(picker)
    host.keyPress(Input.Key.Right)
    @assert(picker.selectedIndex == 1)
    @assert(picker.selectedColor == Argb.Green)
    host.keyPress(Input.Key.End)
    @assert(picker.selectedIndex == 2)
    @assert(PalettePickerHeadlessChangedCount == 3)

    picker.clearSelection(notify: false)
    @assert(picker.selectedIndex == Swag.S32.Max)
    @assert(PalettePickerHeadlessChangedCount == 3)

    host.shutdown()
}
