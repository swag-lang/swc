#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Deep groups retain their transform, clip and paint order when the scopes close.
#[Swag.TestTag("stress")]
#test
{
    const Depth = 4096
    var source = String.from("""\
        <svg width='36' height='16'><defs><clipPath id='window'>\
        <rect width='12' height='10'/></clipPath></defs>\
        <g transform='translate(4 2)' clip-path='url(#window)' fill='lime'><g fill='red'>""")
    for Depth do
        source += "<g>"
    source += "<rect width='16' height='10'/>"
    for Depth do
        source += "</g>"
    source += """\
        </g><rect x='8' width='8' height='10'/></g>\
        <rect x='20' width='12' height='10' fill='blue'/></svg>"""

    let drawing = expect Svg.Drawing.parse(source.toString())
    let image   = drawing.rasterize(36, 16, 1)
    Swag.require(image.pixelColor(5, 5) == Color.fromRgb(255, 0, 0))
    Swag.require(image.pixelColor(13, 5) == Color.fromRgb(0, 255, 0))
    Swag.require(image.pixelColor(17, 5).a == 0)
    Swag.require(image.pixelColor(25, 5) == Color.fromRgb(0, 0, 255))
}
