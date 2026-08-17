#global if #command == Swag.CompilerCommand.Test
#global private

using Pixel
using Swag, Core

var ColorPickerHeadlessChangedCount: u32

func colorPickerHeadlessChanged(c: *ColorPicker)
{
    discard c
    ColorPickerHeadlessChangedCount += 1
}

// setColor decomposes a changed color and emits exactly one notification.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()
    ColorPickerHeadlessChangedCount = 0

    let picker = ColorPicker.create(&host.root, {20, 20, 160, 160})
    picker.sigColorChanged += &colorPickerHeadlessChanged

    picker.setColor(Argb.Red)
    @assert(Math.abs(picker.red - 1) < 0.01)
    @assert(Math.abs(picker.green - 0) < 0.01)
    @assert(Math.abs(picker.blue - 0) < 0.01)
    @assert(Math.abs(picker.alpha - 1) < 0.01)
    @assert(ColorPickerHeadlessChangedCount == 0)

    picker.setColor(Argb.Blue)
    @assert(Math.abs(picker.blue - 1) < 0.01)
    @assert(Math.abs(picker.red - 0) < 0.01)
    @assert(ColorPickerHeadlessChangedCount == 1)

    picker.setColor(Argb.Red, notify: false)
    @assert(picker.color() == Argb.Red)
    @assert(ColorPickerHeadlessChangedCount == 1)
}

// setHsl updates the HSL components and notifies once.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 200)
    defer host.shutdown()
    ColorPickerHeadlessChangedCount = 0

    let picker = ColorPicker.create(&host.root, {20, 20, 160, 160})
    picker.setColor(Argb.Red)
    picker.sigColorChanged += &colorPickerHeadlessChanged

    picker.setHsl(0.5, picker.saturation, picker.lightness)
    @assert(Math.abs(picker.hue - 0.5) < 0.01)
    @assert(ColorPickerHeadlessChangedCount == 1)

    // Same hue again: no change, no signal.
    picker.setHsl(0.5, picker.saturation, picker.lightness)
    @assert(ColorPickerHeadlessChangedCount == 1)
}
