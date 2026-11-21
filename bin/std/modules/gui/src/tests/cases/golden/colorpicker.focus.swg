#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Encre keeps the active focus ring on the selected ColorPicker.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 200)
    host.theme.colors.apply(ThemeColors.encrePalette())

    let picker = ColorPicker.create(&host.root, {24, 24, 160, 140})
    host.root.applyLayout()
    host.keyPress(.Tab)
    Swag.require(picker.hasVisibleFocus())
    host.settleAnimations()

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, "colorpicker.focus.ink")
}
