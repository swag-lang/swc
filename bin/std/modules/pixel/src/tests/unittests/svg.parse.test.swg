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
    @assert(drawing.shapeCount() == 1)

    let image = drawing.rasterize(20, 8, 1)
    let left  = image.pixelColor(1, 4)
    let right = image.pixelColor(18, 4)
    @assert(left.r > left.b)
    @assert(right.b > right.r)
    @assert(left.a == 255 and right.a == 255)

    const ColorSource = "<svg width='30' height='10'>" ++
                        "<rect width='10' height='10' fill='rgba(255,0,0,0.5)'/>" ++
                        "<rect x='10' width='10' height='10' fill='hsl(120,100%,50%)'/>" ++
                        "<rect x='20' width='10' height='10' fill='rgb(0%,0%,100%)' fill-opacity='50%'/></svg>"
    let colorDrawing = expect Svg.Drawing.parse(ColorSource)
    let colors       = colorDrawing.rasterize(30, 10, 1)
    let red          = colors.pixelColor(5, 5)
    let green        = colors.pixelColor(15, 5)
    let blue         = colors.pixelColor(25, 5)
    @assert(red.r > 170 and red.g == 0 and red.b == 0 and red.a > 120 and red.a < 136)
    @assert(green.g > 240 and green.a == 255)
    @assert(blue.b > 170 and blue.r == 0 and blue.g == 0 and blue.a > 120 and blue.a < 136)
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
    @assert(center.r > edge.r)
    @assert(center.a < edge.a)
}

// Public WPT files form a small compatibility corpus, including metadata and
// unsupported subtrees that must be skipped without losing following geometry.
#test
{
    const Names: [4] string = ["svg-wpt/radialgradient-basic-002.svg",
                               "svg-wpt/line-dasharray.svg",
                               "svg-wpt/circle-01.svg",
                               "svg-wpt/render-until-error.svg"]
    const ShapeCounts: [4] u64 = [2, 1, 0, 2]

    for name, i in Names
    {
        let text    = expect File.readAllText(getTestDataPath(name))
        let drawing = expect Svg.Drawing.parse(text.toString())
        @assert(drawing.shapeCount() == ShapeCounts[i])
    }
}

// The public radial-gradient fixture is not merely accepted: both authored
// paint servers survive through the CPU rasterizer.
#test
{
    let text    = expect File.readAllText(getTestDataPath("svg-wpt/radialgradient-basic-002.svg"))
    let drawing = expect Svg.Drawing.parse(text.toString())
    let image   = drawing.rasterize(48, 36, 1)
    @assert(image.pixelColor(12, 24).a > 0)
    @assert(image.pixelColor(36, 24).a > 0)
}

// The public line fixture calibrates its dash pattern through pathLength=25:
// a 200-unit line turns the authored 3/1 sequence into 24/8 user-unit spans.
#test
{
    let text    = expect File.readAllText(getTestDataPath("svg-wpt/line-dasharray.svg"))
    let drawing = expect Svg.Drawing.parse(text.toString())
    let image   = drawing.rasterize(300, 200, 1)
    @assert(image.pixelColor(60, 100).a > 0)
    @assert(image.pixelColor(78, 100).a == 0)
    @assert(image.pixelColor(90, 100).a > 0)

    const OffsetSource = "<svg width='100' height='20'><line x1='0' y1='10' x2='100' y2='10' " ++
                         "stroke='blue' stroke-width='2' stroke-dasharray='10 10' stroke-dashoffset='5'/></svg>"
    let offsetDrawing = expect Svg.Drawing.parse(OffsetSource)
    let offsetImage   = offsetDrawing.rasterize(100, 20, 1)
    @assert(offsetImage.pixelColor(2, 10).a > 0)
    @assert(offsetImage.pixelColor(8, 10).a == 0)
    @assert(offsetImage.pixelColor(18, 10).a > 0)
}
