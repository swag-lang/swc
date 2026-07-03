#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core
using Pixel

var ColorPickerHeadlessChangedCount: u32

func colorPickerHeadlessChanged(c: *ColorPicker)
{
    discard c
    ColorPickerHeadlessChangedCount += 1
}

// setColor decomposes the color into its components and emits sigChanged.
#test
{
    var host: GuiHeadlessHost
    host.setup(200, 200)
    ColorPickerHeadlessChangedCount = 0

    let picker = ColorPicker.create(&host.root, {20, 20, 160, 160})
    picker.sigChanged += &colorPickerHeadlessChanged

    picker.setColor(Argb.Red)
    @assert(Math.abs(picker.r - 1) < 0.01)
    @assert(Math.abs(picker.g - 0) < 0.01)
    @assert(Math.abs(picker.b - 0) < 0.01)
    @assert(Math.abs(picker.a - 1) < 0.01)
    @assert(ColorPickerHeadlessChangedCount == 1)

    picker.setColor(Argb.Blue)
    @assert(Math.abs(picker.b - 1) < 0.01)
    @assert(Math.abs(picker.r - 0) < 0.01)
    @assert(ColorPickerHeadlessChangedCount == 2)

    host.shutdown()
}

// change() updates the targeted HSL component and notifies once.
#test
{
    var host: GuiHeadlessHost
    host.setup(200, 200)
    ColorPickerHeadlessChangedCount = 0

    let picker = ColorPicker.create(&host.root, {20, 20, 160, 160})
    picker.setColor(Argb.Red)
    picker.sigChanged += &colorPickerHeadlessChanged

    picker.change(0.5)
    @assert(Math.abs(picker.hue - 0.5) < 0.01)
    @assert(ColorPickerHeadlessChangedCount == 1)

    // Same hue again: no change, no signal.
    picker.change(0.5)
    @assert(ColorPickerHeadlessChangedCount == 1)

    host.shutdown()
}
