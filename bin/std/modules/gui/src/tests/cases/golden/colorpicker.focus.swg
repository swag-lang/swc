#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

func assertFocusedColorPicker(light: bool)
{
    var host: Testing.HeadlessHost
    host.setup(220, 200)
    host.theme.colors.apply(light ? ThemeColors.papierPalette() : ThemeColors.encrePalette())

    let picker = ColorPicker.create(&host.root, {24, 24, 160, 140})
    host.app.setFocusVisible(true)
    picker.setFocus()
    host.root.applyLayout()
    host.settleAnimations()

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, light ? "colorpicker.focus.paper" : "colorpicker.focus.ink")
}

// Encre keeps the active focus ring on the selected ColorPicker.
#[Swag.TestTag("golden")]
#test
{
    assertFocusedColorPicker(false)
}

// Papier uses the theme's ink focus ring on the same control.
#[Swag.TestTag("golden")]
#test
{
    assertFocusedColorPicker(true)
}
