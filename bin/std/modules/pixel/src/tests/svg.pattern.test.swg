#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// A user-space pattern repeats its vector tile and clips it to the painted geometry.
#test
{
    const Source = "<svg width='20' height='12'><defs>" ++
                   "<pattern id='bars' patternUnits='userSpaceOnUse' width='4' height='4'>" ++
                   "<rect width='2' height='4' fill='#ff0000'/><rect x='2' width='2' height='4' fill='#0000ff'/>" ++
                   "</pattern></defs><rect x='2' y='2' width='16' height='8' fill='url(#bars)'/></svg>"

    let drawing = expect Svg.Drawing.parse(Source)
    let image   = drawing.rasterize(20, 12, 1)
    Swag.assert(image.pixelColor(0, 6).a == 0)
    let red  = image.pixelColor(4, 6)
    let blue = image.pixelColor(6, 6)
    Swag.assert(red.r > 200 and red.b < 32 and red.a == 255)
    Swag.assert(blue.b > 200 and blue.r < 32 and blue.a == 255)
    Swag.assert(image.pixelColor(19, 6).a == 0)
}
