#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Filter primitives compose in declaration order: blur first, then offset the result.
#test
{
    const Source = "<svg width='32' height='20'><defs><filter id='soft-shift'>" ++
                   "<feGaussianBlur stdDeviation='2'/><feOffset dx='5' dy='0'/>" ++
                   "</filter></defs><rect x='4' y='6' width='8' height='8' fill='#ff0000' filter='url(#soft-shift)'/></svg>"

    let drawing = expect Svg.Drawing.parse(Source)
    let image   = drawing.rasterize(32, 20, 1)
    let before  = image.pixelColor(3, 10)
    let center  = image.pixelColor(13, 10)
    let feather = image.pixelColor(18, 10)
    Swag.assert(before.a < 16)
    Swag.assert(center.r > 80 and center.a > 80)
    Swag.assert(feather.a > 0 and feather.a < center.a)
}
