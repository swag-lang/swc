#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

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
