#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Shapes in separate spatial buckets still paint in document order across raster tiles.
#[Swag.TestTag("stress")]
#test
{
    var source = String.from("""\
        <svg viewBox='0 0 96 8192'><defs><clipPath id='left'>\
        <rect x='16' y='4070' width='16' height='48'/></clipPath></defs>""")
    for i in 8192 do
        source.appendFormat("<rect x='1' y='%' width='2' height='1'/>", (i * 2053) % 8192)

    source += """\
        <rect x='10' y='4078' width='60' height='24' fill='red'/>\
        <rect x='18' y='4086' width='32' height='26' fill='blue'/>\
        <rect x='18' y='4080' width='40' height='26' fill='lime' clip-path='url(#left)'/>\
        <rect x='78' y='4088' width='10' height='24' fill='yellow'/></svg>"""
    let drawing = expect Svg.Drawing.parse(source.toString())
    let image   = drawing.rasterize(96, 4200, 1)
    Swag.require(image.pixelColor(12, 4098) == Color.fromRgb(255, 0, 0))
    Swag.require(image.pixelColor(22, 4098) == Color.fromRgb(0, 255, 0))
    Swag.require(image.pixelColor(42, 4098) == Color.fromRgb(0, 0, 255))
    Swag.require(image.pixelColor(83, 4098) == Color.fromRgb(255, 255, 0))
}
