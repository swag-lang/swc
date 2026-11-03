#global if #command == Swag.CompilerCommand.Test
#global private

using Pixel
using Swag, Core

var ColorPickerHeadlessChangedCount: u32

func colorPickerHeadlessChanged(_: *ColorPicker)
{
    ColorPickerHeadlessChangedCount += 1
}

// setColor decomposes a changed color and emits exactly one notification.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    ColorPickerHeadlessChangedCount = 0

    let picker = ColorPicker.create(&host.root, {20, 20, 160, 160})
    picker.sigColorChanged += &colorPickerHeadlessChanged

    picker.setColor(Argb.Red)
    Swag.require(Math.abs(picker.red - 1) < 0.01)
    Swag.require(Math.abs(picker.green - 0) < 0.01)
    Swag.require(Math.abs(picker.blue - 0) < 0.01)
    Swag.require(Math.abs(picker.alpha - 1) < 0.01)
    Swag.require(ColorPickerHeadlessChangedCount == 0)

    picker.setColor(Argb.Blue)
    Swag.require(Math.abs(picker.blue - 1) < 0.01)
    Swag.require(Math.abs(picker.red - 0) < 0.01)
    Swag.require(ColorPickerHeadlessChangedCount == 1)

    picker.setColor(Argb.Red, notify: false)
    Swag.require(picker.color() == Argb.Red)
    Swag.require(ColorPickerHeadlessChangedCount == 1)
}

// setHsl updates the HSL components and notifies once.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    ColorPickerHeadlessChangedCount = 0

    let picker = ColorPicker.create(&host.root, {20, 20, 160, 160})
    picker.setColor(Argb.Red)
    picker.sigColorChanged += &colorPickerHeadlessChanged

    picker.setHsl(0.5, picker.saturation, picker.lightness)
    Swag.require(Math.abs(picker.hue - 0.5) < 0.01)
    Swag.require(ColorPickerHeadlessChangedCount == 1)

    // Same hue again: no change, no signal.
    picker.setHsl(0.5, picker.saturation, picker.lightness)
    Swag.require(ColorPickerHeadlessChangedCount == 1)
}
