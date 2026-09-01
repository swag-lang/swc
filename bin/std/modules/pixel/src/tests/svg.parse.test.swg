#global if #command == Swag.CompilerCommand.Test

using Swag, Core

private const ManyStopSvg = "<svg width='20' height='8'>" ++
                            "<style>.accent { fill: url(#many); }</style>" ++
                            "<rect class='accent' width='20' height='8'/>" ++
                            "<defs><linearGradient id='many' gradientUnits='userSpaceOnUse' x1='0' y1='0' x2='20' y2='0'>" ++
                            "<stop offset='0%' stop-color='red'/>" ++
                            "<stop offset='10%' stop-color='#e61920'/>" ++
                            "<stop offset='20%' stop-color='#cc3333'/>" ++
                            "<stop offset='30%' stop-color='#b34c46'/>" ++
                            "<stop offset='40%' stop-color='#99665a'/>" ++
                            "<stop offset='50%' stop-color='#807f6d'/>" ++
                            "<stop offset='60%' stop-color='#669981'/>" ++
                            "<stop offset='70%' stop-color='#4cb294'/>" ++
                            "<stop offset='80%' stop-color='#33cca8'/>" ++
                            "<stop offset='90%' stop-color='#19e5bb'/>" ++
                            "<stop offset='100%' stop-color='cyan'/>" ++
                            "</linearGradient></defs></svg>"

// Paint servers resolve after the complete document, so forward references,
// class rules, named colors, percentages and more than eight stops compose.
#test
{
    let drawing = expect Svg.Drawing.parse(ManyStopSvg)
    Swag.assert(drawing.shapeCount() == 1)

    let image = drawing.rasterize(20, 8, 1)
    let left  = image.pixelColor(1, 4)
    let right = image.pixelColor(18, 4)
    Swag.assert(left.r > left.b)
    Swag.assert(right.b > right.r)
    Swag.assert(left.a == 255 and right.a == 255)

    const ColorSource = "<svg width='30' height='10'>" ++
                        "<rect width='10' height='10' fill='rgba(255,0,0,0.5)'/>" ++
                        "<rect x='10' width='10' height='10' fill='hsl(120,100%,50%)'/>" ++
                        "<rect x='20' width='10' height='10' fill='rgb(0%,0%,100%)' fill-opacity='50%'/></svg>"
    let colorDrawing = expect Svg.Drawing.parse(ColorSource)
    let colors       = colorDrawing.rasterize(30, 10, 1)
    let red          = colors.pixelColor(5, 5)
    let green        = colors.pixelColor(15, 5)
    let blue         = colors.pixelColor(25, 5)
    Swag.assert(red.r > 170 and red.g == 0 and red.b == 0 and red.a > 120 and red.a < 136)
    Swag.assert(green.g > 240 and green.a == 255)
    Swag.assert(blue.b > 170 and blue.r == 0 and blue.g == 0 and blue.a > 120 and blue.a < 136)
}

// A radial paint server carries its inner radius, stop opacity and repeat policy.
#test
{
    const Source = "<svg viewBox='0 0 20 20'>" ++
                   "<defs><radialGradient id='r' cx='50%' cy='50%' r='50%' fr='20%' spreadMethod='reflect'>" ++
                   "<stop offset='0' stop-color='white' stop-opacity='0.5'/>" ++
                   "<stop offset='1' style='stop-color:black;stop-opacity:1'/>" ++
                   "</radialGradient></defs><circle cx='10' cy='10' r='10' fill='url(#r)'/></svg>"

    let drawing = expect Svg.Drawing.parse(Source)
    let image   = drawing.rasterize(20, 20, 1)
    let center  = image.pixelColor(10, 10)
    let edge    = image.pixelColor(18, 10)
    Swag.assert(center.r > edge.r)
    Swag.assert(center.a < edge.a)
}

// Public WPT files form a small compatibility corpus, including metadata and
// unsupported subtrees that must be skipped without losing following geometry.
#test
{
    const Names: [4] string = ["svg-wpt.radialgradient-basic-002.svg",
                               "svg-wpt.line-dasharray.svg",
                               "svg-wpt.circle-01.svg",
                               "svg-wpt.render-until-error.svg"]
    const ShapeCounts: [4] u64 = [2, 1, 0, 2]

    for name, i in Names
    {
        let text    = expect File.readAllText(getTestDataPath(name))
        let drawing = expect Svg.Drawing.parse(text.toString())
        Swag.assert(drawing.shapeCount() == ShapeCounts[i])
    }
}

// The public radial-gradient fixture is not merely accepted: both authored
// paint servers survive through the CPU rasterizer.
#test
{
    let text    = expect File.readAllText(getTestDataPath("svg-wpt.radialgradient-basic-002.svg"))
    let drawing = expect Svg.Drawing.parse(text.toString())
    let image   = drawing.rasterize(48, 36, 1)
    Swag.assert(image.pixelColor(12, 24).a > 0)
    Swag.assert(image.pixelColor(36, 24).a > 0)
}

// The public line fixture calibrates its dash pattern through pathLength=25:
// a 200-unit line turns the authored 3/1 sequence into 24/8 user-unit spans.
#test
{
    let text    = expect File.readAllText(getTestDataPath("svg-wpt.line-dasharray.svg"))
    let drawing = expect Svg.Drawing.parse(text.toString())
    let image   = drawing.rasterize(300, 200, 1)
    Swag.assert(image.pixelColor(60, 100).a > 0)
    Swag.assert(image.pixelColor(78, 100).a == 0)
    Swag.assert(image.pixelColor(90, 100).a > 0)

    const OffsetSource = "<svg width='100' height='20'><line x1='0' y1='10' x2='100' y2='10' " ++
                         "stroke='blue' stroke-width='2' stroke-dasharray='10 10' stroke-dashoffset='5'/></svg>"
    let offsetDrawing = expect Svg.Drawing.parse(OffsetSource)
    let offsetImage   = offsetDrawing.rasterize(100, 20, 1)
    Swag.assert(offsetImage.pixelColor(2, 10).a > 0)
    Swag.assert(offsetImage.pixelColor(8, 10).a == 0)
    Swag.assert(offsetImage.pixelColor(18, 10).a > 0)
}

// Sample-aligned tiles preserve every resolved byte when geometry crosses both tile axes.
#test
{
    const Source = "<svg viewBox='0 0 300 260'>" ++
                   "<rect x='20' y='18' width='270' height='232' rx='31' fill='#2878d0'/>" ++
                   "<circle cx='256' cy='210' r='46' fill='#f4b43c' fill-opacity='0.63'/>" ++
                   "<path d='M4 257 L296 3' stroke='white' stroke-width='3'/></svg>"

    let drawing             = expect Svg.Drawing.parse(Source)
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    cpu.begin(300, 260)
    defer renderer.end()

    let tiled   = drawing.rasterize(renderer, 300, 260, 4)
    let untiled = drawing.rasterizeWithSampleTileSide(renderer, 300, 260, 4, 2048)
    Swag.assert(tiled.pixels.count == untiled.pixels.count)
    for value, index in tiled.pixels do
        Swag.assert(value == untiled.pixels[index])
}

// Returns the colors a source paints at five points across a wide band.
private func gradientBand(source: string)->[5] Color
{
    var result: retval
    let drawing = expect Svg.Drawing.parse(source)
    let image   = drawing.rasterize(40, 8, 1)
    let columns = [2, 12, 20, 28, 37]
    for column, index in columns do
        result[index] = image.pixelColor(cast(s32) column, 4)

    return result
}

// A gradient inherits from the one it references, whichever order the two are written in.
#test
{
    // The referenced gradient is defined after the reference, so the chain is followed once the
    // whole document is read.
    let forward = gradientBand("<svg width='40' height='8'><rect width='40' height='8' fill='url(#a)'/>" ++
                               "<linearGradient id='a' href='#b'/>" ++
                               "<linearGradient id='b'><stop offset='0' stop-color='#ff0000'/>" ++
                               "<stop offset='1' stop-color='#0000ff'/></linearGradient></svg>")
    Swag.assert(forward[0].r > 200 and forward[0].b < 60)
    Swag.assert(forward[4].b > 200 and forward[4].r < 60)

    // A two-step chain, where the middle link states only the geometry.
    let chained = gradientBand("<svg width='40' height='8'>" ++
                               "<linearGradient id='c'><stop offset='0' stop-color='#00ff00'/>" ++
                               "<stop offset='1' stop-color='#000000'/></linearGradient>" ++
                               "<linearGradient id='d' href='#c' x1='0' y1='0' x2='1' y2='0'/>" ++
                               "<linearGradient id='e' href='#d'/>" ++
                               "<rect width='40' height='8' fill='url(#e)'/></svg>")
    Swag.assert(chained[0].g > 200 and chained[4].g < 60)

    // A gradient states its own stops, and inheritance never overwrites them.
    let own = gradientBand("<svg width='40' height='8'>" ++
                           "<linearGradient id='f'><stop offset='0' stop-color='#ff0000'/>" ++
                           "<stop offset='1' stop-color='#0000ff'/></linearGradient>" ++
                           "<linearGradient id='g' href='#f'><stop offset='0' stop-color='#000000'/>" ++
                           "<stop offset='1' stop-color='#ffffff'/></linearGradient>" ++
                           "<rect width='40' height='8' fill='url(#g)'/></svg>")
    Swag.assert(own[0].r < 60 and own[0].g < 60 and own[0].b < 60)
    Swag.assert(own[4].r > 200 and own[4].g > 200 and own[4].b > 200)
}

// A reference that loops back on itself stops contributing instead of hanging, and the gradient
// keeps what it states itself.
#test
{
    let cycle = gradientBand("<svg width='40' height='8'>" ++
                             "<linearGradient id='h' href='#i'><stop offset='0' stop-color='#ffffff'/>" ++
                             "<stop offset='1' stop-color='#000000'/></linearGradient>" ++
                             "<linearGradient id='i' href='#h'/>" ++
                             "<rect width='40' height='8' fill='url(#h)'/></svg>")
    Swag.assert(cycle[0].r > 200 and cycle[4].r < 60)
}
