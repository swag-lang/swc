#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core
using Pixel

// Colors can be added individually and in generated ranges.
#test
{
    var host: GuiHeadlessHost
    host.setup(240, 120)

    let picker = PalettePicker.create(&host.root, {10, 10, 220, 100})
    @assert(picker.pal.count == 0)

    picker.addColor(Argb.Red)
    picker.addColor(Argb.Blue)
    @assert(picker.pal.count == 2)
    @assert(picker.pal[0] == Argb.Red)

    picker.addHueColors(8, 1, 0.5)
    @assert(picker.pal.count == 10)

    host.shutdown()
}
