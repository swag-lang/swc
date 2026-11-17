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

// Tab reaches the picker, and arrows adjust the active components in a two-dimensional mode.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    ColorPickerHeadlessChangedCount = 0

    let before = PushButton.create(&host.root, "Before", {10, 10, 90, 30})
    let picker = ColorPicker.create(&host.root, {110, 10, 110, 100})
    picker.setHsla(0.25, 0.5, 0.5, 0.75, false)
    picker.setMode(.HueSaturation)
    picker.sigColorChanged += &colorPickerHeadlessChanged

    host.focus(before)
    host.keyPress(.Tab)
    Swag.require(picker.hasFocus() and picker.hasVisibleFocus())
    Swag.require(picker.wndFlags.has(.FocusRing))

    let step = 1.0 / 255
    host.keyPress(.Right)
    Swag.require(Math.abs(picker.hue - (0.25 + step)) < 0.0001)
    Swag.require(Math.abs(picker.saturation - 0.5) < 0.0001)
    Swag.require(Math.abs(picker.lightness - 0.5) < 0.0001)
    Swag.require(Math.abs(picker.alpha - 0.75) < 0.0001)
    Swag.require(ColorPickerHeadlessChangedCount == 1)

    // Saturation rises toward the top of this plane, so Up increases it.
    host.keyPress(.Up)
    Swag.require(Math.abs(picker.hue - (0.25 + step)) < 0.0001)
    Swag.require(Math.abs(picker.saturation - (0.5 + step)) < 0.0001)
    Swag.require(ColorPickerHeadlessChangedCount == 2)
}

// The horizontal saturation-lightness axis keeps the rendered color in sync with saturation.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    ColorPickerHeadlessChangedCount = 0

    let picker = ColorPicker.create(&host.root, {10, 10, 180, 100})
    picker.setHsla(0.25, 0.5, 0.5, 1, false)
    picker.setMode(.SaturationLightness)
    picker.sigColorChanged += &colorPickerHeadlessChanged
    host.focus(picker)

    let oldColor = picker.color()
    host.keyPress(.Right)

    Swag.require(Math.abs(picker.saturation - (0.5 + (1.0 / 255))) < 0.0001)
    Swag.require(Math.abs(picker.lightness - 0.5) < 0.0001)
    Swag.require(picker.color() != oldColor)
    Swag.require(ColorPickerHeadlessChangedCount == 1)
}

// Single-channel gradients accept only the arrow pair that follows their axis.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    ColorPickerHeadlessChangedCount = 0

    let picker = ColorPicker.create(&host.root, {10, 10, 180, 100})
    picker.setHsla(0.5, 0.5, 0.5, 0.5, false)
    picker.setMode(.HueVertical)
    picker.sigColorChanged += &colorPickerHeadlessChanged
    host.focus(picker)

    Swag.require(not picker.sendKeyPress(.Right))
    Swag.require(not picker.sendKeyPress(.A))
    Swag.require(not picker.sendKeyPress(.Up, .Shift))
    Swag.require(Math.abs(picker.hue - 0.5) < 0.0001)
    Swag.require(ColorPickerHeadlessChangedCount == 0)

    host.keyPress(.Up)
    Swag.require(Math.abs(picker.hue - (0.5 - (1.0 / 255))) < 0.0001)
    Swag.require(Math.abs(picker.saturation - 0.5) < 0.0001)
    Swag.require(Math.abs(picker.lightness - 0.5) < 0.0001)
    Swag.require(Math.abs(picker.alpha - 0.5) < 0.0001)
    Swag.require(ColorPickerHeadlessChangedCount == 1)

    picker.setMode(.AlphaHorizontal)
    host.keyPress(.Left)
    Swag.require(Math.abs(picker.alpha - (0.5 - (1.0 / 255))) < 0.0001)
    Swag.require(Math.abs(picker.hue - (0.5 - (1.0 / 255))) < 0.0001)
    Swag.require(ColorPickerHeadlessChangedCount == 2)
}

// Channel values clamp at both bounds, and a clamped key does not emit a color change.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    ColorPickerHeadlessChangedCount = 0

    let picker = ColorPicker.create(&host.root, {10, 10, 180, 100})
    picker.setColor(Argb.Red, false)
    picker.setMode(.RedHorizontal)
    picker.sigColorChanged += &colorPickerHeadlessChanged
    host.focus(picker)

    host.keyPress(.Right)
    Swag.require(picker.red == 1)
    Swag.require(ColorPickerHeadlessChangedCount == 0)

    host.keyPress(.Left)
    Swag.require(Math.abs(picker.red - (1 - (1.0 / 255))) < 0.0001)
    Swag.require(ColorPickerHeadlessChangedCount == 1)

    picker.setColor(Argb.Black, false)
    host.keyPress(.Left)
    Swag.require(picker.red == 0)
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
