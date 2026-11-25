#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Dense compound paths retain their winding rule without triangulating every hole.
#test
{
    const Rings = "M2 2h12v12H2z M5 5h6v6H5z "
    var path = String.from(Rings)
    for 512 do
        path += "M18 18h1v1h-1z "

    for rule in ["nonzero", "evenodd"]
    {
        let source = Format.toString("<svg width='16' height='16'><path fill='#ff0000' fill-rule='%' d='%'/></svg>", rule, path)
        let drawing = expect Svg.Drawing.parse(source)
        let image = drawing.rasterize(16, 16, 1)
        Swag.require(image.pixelColor(0, 0).a == 0)
        Swag.require(image.pixelColor(3, 3).argb == Color.fromRgb(255, 0, 0).argb)
        Swag.require(image.pixelColor(7, 7).a == (rule == "evenodd" ? 0 : 255))
    }
}

// A compound fill with stroke keeps the nesting and placement of spatially separated contours.
#test
{
    var path = String.from("M2 2h16v16H2z M5 5v10h10V5z M8 8h4v4H8z ")
    for i in 64
    {
        let island = Format.toString("M% 20h2v2h-2z ", 24 + i * 4)
        path += island.toString()
    }

    let source  = Format.toString("""\
        <svg width='300' height='24'><path fill='red' stroke='blue' \
        stroke-width='0.25' fill-rule='evenodd' d='%'/></svg>""", path)
    let drawing = expect Svg.Drawing.parse(source.toString())
    Swag.require(drawing.shapeCount() == 66)
    let image = drawing.rasterize(300, 24, 1)
    Swag.require(image.pixelColor(3, 3) == Color.fromRgb(255, 0, 0))
    Swag.require(image.pixelColor(6, 6).a == 0)
    Swag.require(image.pixelColor(9, 9) == Color.fromRgb(255, 0, 0))
    Swag.require(image.pixelColor(277, 21).r > 200)
}

// Layout can reserve the final image box without parsing paths or decoding embedded images.
#test
{
    for source in [
        "<svg width='464' height='464px' viewBox='40 40 928 928'/>",
        "<svg width='200' viewBox='0 0 400 100'/>",
        "<svg height='50' viewBox='0 0 400 100'/>",
        "<svg width='100%' height='auto' viewBox='0 0 400 100'/>",
        "<svg width='20' height='10'/>"]
    {
        let drawing = expect Svg.Drawing.parse(source)
        Swag.require((expect Svg.parseImageSize(source)) == drawing.naturalSize())
    }

    const Deferred = "<?xml version='1.0'?><svg width='120' height='60'><image width='120' height='60' href='unavailable.png'/></svg>"
    Swag.require((expect Svg.parseImageSize(Deferred)) == Math.Vector2{120, 60})
    var contentErrorOutcome: Swag.Error
    discard catch Svg.Drawing.parse(Deferred) as contentErrorOutcome
    let contentError = contentErrorOutcome.value()
    Swag.require(contentError != null)
    var sizeErrorOutcome: Swag.Error
    discard catch Svg.parseImageSize("<svg/>") as sizeErrorOutcome
    let sizeError = sizeErrorOutcome.value()
    Swag.require(sizeError != null)
}

// A symbol keeps its viewport. An empty href overrides its fallback; an omitted href uses it.
#test
{
    func parseDrawing()->Svg.Drawing
    {
        let source = String.from("""\
            <svg width='50' height='10' xmlns:xlink='http://www.w3.org/1999/xlink'>\
            <defs><symbol id='tile' viewBox='0 0 5 5'>\
            <rect width='5' height='5' fill='red'/></symbol></defs>\
            <use href='#tile' width='10' height='10'/><use x='10'/>\
            <use x='20' href='' xlink:href='#tile' width='10' height='10'/>\
            <use x='30' xlink:href='#tile' width='10' height='10'/>\
            <rect x='40' width='10' height='10' fill="blue" data-note='a > "b"'/>\
            <rect y='5' height='5' fill='green'/></svg>""")
        return expect Svg.Drawing.parse(source.toString())
    }

    let drawing = parseDrawing()
    let image   = drawing.rasterize(50, 10, 1)
    Swag.require(image.pixelColor(8, 8).r == 255)
    Swag.require(image.pixelColor(15, 8).a == 0)
    Swag.require(image.pixelColor(25, 8).a == 0)
    Swag.require(image.pixelColor(35, 8).r == 255)
    Swag.require(image.pixelColor(45, 8).b == 255)
}

// Image dimensions and drawing coordinates are separate, including offset view boxes.
#test
{
    let drawing = expect Svg.Drawing.parse("<svg width='464' height='464px' viewBox='40 40 928 928'/>")
    Swag.require(drawing.width == 928 and drawing.height == 928)
    Swag.require(drawing.naturalSize() == Math.Vector2{464, 464})

    let widthOnly = expect Svg.Drawing.parse("<svg width='200' viewBox='0 0 400 100'/>")
    Swag.require(widthOnly.naturalSize() == Math.Vector2{200, 50})
    let heightOnly = expect Svg.Drawing.parse("<svg height='50' viewBox='0 0 400 100'/>")
    Swag.require(heightOnly.naturalSize() == Math.Vector2{200, 50})
    let relative = expect Svg.Drawing.parse("<svg width='100%' height='auto' viewBox='0 0 400 100'/>")
    Swag.require(relative.naturalSize() == Math.Vector2{400, 100})
    let noViewBox = expect Svg.Drawing.parse("<svg width='20' height='10'/>")
    Swag.require(noViewBox.naturalSize() == Math.Vector2{20, 10})
}

// Absolute CSS units resolve without a host; relative and nonpositive lengths remain unspecified.
#test
{
    for length in ["96", "96px", "1in", "2.54cm", "25.4mm", "101.6Q", "72pt", "6pc"]
    {
        let source  = Format.toString("<svg width='%' viewBox='0 0 200 100'/>", length)
        let drawing = expect Svg.Drawing.parse(source.toString())
        Swag.require(Math.abs(drawing.naturalSize().x - 96) < 0.001)
        Swag.require(Math.abs(drawing.naturalSize().y - 48) < 0.001)
    }

    for length in ["100%", "auto", "2em", "-4", "0", ".", "-."]
    {
        let source  = Format.toString("<svg width='%' height='50' viewBox='0 0 200 100'/>", length)
        let drawing = expect Svg.Drawing.parse(source.toString())
        Swag.require(drawing.naturalSize() == Math.Vector2{100, 50})
    }
}

#test
{
    let source  = "<svg width='1e30' viewBox='0 0 1e30 1e30'/>"
    let drawing = expect Svg.Drawing.parse(source)
    let size    = drawing.naturalSize()
    Swag.require(Math.isFinite(size.x) and
                 Math.isFinite(size.y) and
                 size.x == 1e30 and
                 size.y == 1e30)
    Swag.require((expect Svg.parseImageSize(source)) == size)

    var error: Swag.Error
    let tooLarge = "<svg width='1e30' viewBox='0 0 1 1e30'/>"
    discard catch Svg.parseImageSize(tooLarge) as error
    Swag.require(error.value() is Swag.SystemError)
    discard catch Svg.Drawing.parse(tooLarge) as error
    Swag.require(error.value() is Swag.SystemError)
}

private const ManyStopSvg = """\
    <svg width='20' height='8'>\
    <style>.accent { fill: url(#many); }</style>\
    <rect class='accent' width='20' height='8'/>\
    <defs><linearGradient id='many' gradientUnits='userSpaceOnUse' x1='0' y1='0' x2='20' y2='0'>\
    <stop offset='0%' stop-color='red'/>\
    <stop offset='10%' stop-color='#e61920'/>\
    <stop offset='20%' stop-color='#cc3333'/>\
    <stop offset='30%' stop-color='#b34c46'/>\
    <stop offset='40%' stop-color='#99665a'/>\
    <stop offset='50%' stop-color='#807f6d'/>\
    <stop offset='60%' stop-color='#669981'/>\
    <stop offset='70%' stop-color='#4cb294'/>\
    <stop offset='80%' stop-color='#33cca8'/>\
    <stop offset='90%' stop-color='#19e5bb'/>\
    <stop offset='100%' stop-color='cyan'/>\
    </linearGradient></defs></svg>"""

// Paint servers resolve after the complete document, so forward references,
// class rules, named colors, percentages and more than eight stops compose.
#test
{
    let drawing = expect Svg.Drawing.parse(ManyStopSvg)
    Swag.require(drawing.shapeCount() == 1)

    let image = drawing.rasterize(20, 8, 1)
    let left  = image.pixelColor(1, 4)
    let right = image.pixelColor(18, 4)
    Swag.require(left.r > left.b)
    Swag.require(right.b > right.r)
    Swag.require(left.a == 255 and right.a == 255)

    const ColorSource = """\
        <svg width='30' height='10'>\
        <rect width='10' height='10' fill='rgba(255,0,0,0.5)'/>\
        <rect x='10' width='10' height='10' fill='hsl(120,100%,50%)'/>\
        <rect x='20' width='10' height='10' fill='rgb(0%,0%,100%)' fill-opacity='50%'/></svg>"""
    let colorDrawing = expect Svg.Drawing.parse(ColorSource)
    let colors       = colorDrawing.rasterize(30, 10, 1)
    let red          = colors.pixelColor(5, 5)
    let green        = colors.pixelColor(15, 5)
    let blue         = colors.pixelColor(25, 5)
    Swag.require(red.r > 170 and red.g == 0 and red.b == 0 and red.a > 120 and red.a < 136)
    Swag.require(green.g > 240 and green.a == 255)
    Swag.require(blue.b > 170 and blue.r == 0 and blue.g == 0 and blue.a > 120 and blue.a < 136)
}

// Decreasing offsets clamp to the preceding stop while preserving the authored transition.
#test
{
    const Source = """\
        <svg width='32' height='8'><defs><linearGradient id='edge'>\
        <stop offset='0' stop-color='red'/><stop offset='0.5' stop-color='red'/>\
        <stop offset='0.25' stop-color='blue'/><stop offset='2' stop-color='blue'/>\
        </linearGradient></defs><rect width='32' height='8' fill='url(#edge)'/></svg>"""
    let drawing = expect Svg.Drawing.parse(Source)
    let image   = drawing.rasterize(32, 8, 1)
    Swag.require(image.pixelColor(12, 4) == Color.fromRgb(255, 0, 0))
    Swag.require(image.pixelColor(20, 4) == Color.fromRgb(0, 0, 255))
}

// Shapes sharing a user-space gradient can use different opacities and transforms.
#test
{
    const Source = """\
        <svg width='28' height='16'><defs>\
        <linearGradient id='color' gradientUnits='userSpaceOnUse' x1='0' x2='12'>\
        <stop offset='0' stop-color='red'/><stop offset='1' stop-color='blue'/>\
        </linearGradient></defs><g fill='url(#color)'>\
        <rect width='12' height='8'/><rect y='8' width='12' height='8' fill-opacity='0.5'/>\
        <g transform='translate(16,0)'><rect width='12' height='8'/></g></g></svg>"""
    let drawing = expect Svg.Drawing.parse(Source)
    let image   = drawing.rasterize(28, 16, 1)
    let solid   = image.pixelColor(2, 4)
    let faded   = image.pixelColor(2, 12)
    Swag.require(solid.r > solid.b and solid.a == 255)
    Swag.require(image.pixelColor(18, 4) == solid)
    Swag.require(faded.r > faded.b and faded.a > 120 and faded.a < 135)
}

// Class rules follow stylesheet order, even with a reordered or repeated class on the element.
#test
{
    const Source = """\
        <svg width='50' height='10'>\
        <style>RECT { fill: yellow; } .second { fill: blue; opacity: 0.5; }\
        .first { fill: red; } #selected { fill: lime; } #inline { fill: lime; }</style>\
        <rect width='10' height='10' class='first second second'/>\
        <style>.second { fill: blue; }</style>\
        <rect x='10' width='10' height='10' class='second first'/>\
        <rect x='20' width='10' height='10' class='first' id='selected'/>\
        <rect x='30' width='10' height='10' style='fill:white' id='inline'/>\
        <rect x='40' width='10' height='10' class='Second' id='SELECTED'/></svg>"""

    let drawing = expect Svg.Drawing.parse(Source)
    let image   = drawing.rasterize(50, 10, 1)
    let red     = image.pixelColor(5, 5)
    let blue    = image.pixelColor(15, 5)
    Swag.require(red.r >= 253 and red.g == 0 and red.b == 0)
    Swag.require(blue.r == 0 and blue.g == 0 and blue.b >= 253)
    Swag.require(red.a == blue.a and Math.abs(cast(s32, red.a) - 128) <= 2)
    Swag.require(image.pixelColor(25, 5) == Color.fromRgb(0, 255, 0))
    Swag.require(image.pixelColor(35, 5) == Color.fromRgb(255, 255, 255))
    Swag.require(image.pixelColor(45, 5) == Color.fromRgb(255, 255, 0))
}

// Repeated class rules keep their presentation inputs and are reevaluated when the sheet grows.
#test
{
    const Source = """\
        <svg width='40' height='10'>\
        <style>.ink { fill: currentColor; }</style>\
        <rect width='10' height='10' class='ink' color='lime'/>\
        <rect x='10' width='10' height='10' class='ink' color='lime'/>\
        <rect x='20' width='10' height='10' class='ink' color='blue'/>\
        <style>.ink { fill: red; }</style>\
        <rect x='30' width='10' height='10' class='ink' color='blue'/></svg>"""

    let drawing = expect Svg.Drawing.parse(Source)
    let image   = drawing.rasterize(40, 10, 1)
    Swag.require(image.pixelColor(5, 5) == Color.fromRgb(0, 255, 0))
    Swag.require(image.pixelColor(15, 5) == Color.fromRgb(0, 255, 0))
    Swag.require(image.pixelColor(25, 5) == Color.fromRgb(0, 0, 255))
    Swag.require(image.pixelColor(35, 5) == Color.fromRgb(255, 0, 0))
}

// Hidden primitives are skipped while a visible descendant still emits its geometry.
#test
{
    const Source = """\
        <svg width='48' height='16'><g visibility='hidden'>\
        <rect x='1' y='2' width='8' height='10'/>\
        <circle cx='14' cy='7' r='4'/><ellipse cx='23' cy='7' rx='4' ry='3'/>\
        <rect x='29' y='2' width='8' height='10' visibility='visible' fill='red'/>\
        </g><ellipse cx='42' cy='8' rx='3' ry='5' fill='none' stroke='blue'/></svg>"""
    let drawing = expect Svg.Drawing.parse(Source)
    let image   = drawing.rasterize(48, 16, 1)
    Swag.require(drawing.shapeCount() == 2)
    Swag.require(image.pixelColor(5, 7).a == 0 and
                 image.pixelColor(14, 7).a == 0 and
                 image.pixelColor(23, 7).a == 0)
    Swag.require(image.pixelColor(33, 7) == Color.fromRgb(255, 0, 0))
}

// A radial paint server carries its inner radius, stop opacity and repeat policy.
#test
{
    const Source = """\
        <svg viewBox='0 0 20 20'>\
        <defs><radialGradient id='r' cx='50%' cy='50%' r='50%' fr='20%' spreadMethod='reflect'>\
        <stop offset='0' stop-color='white' stop-opacity='0.5'/>\
        <stop offset='1' style='stop-color:black;stop-opacity:1'/>\
        </radialGradient></defs><circle cx='10' cy='10' r='10' fill='url(#r)'/></svg>"""

    let drawing = expect Svg.Drawing.parse(Source)
    let image   = drawing.rasterize(20, 20, 1)
    let center  = image.pixelColor(10, 10)
    let edge    = image.pixelColor(18, 10)
    Swag.require(center.r > edge.r)
    Swag.require(center.a < edge.a)
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
        Swag.require(drawing.shapeCount() == ShapeCounts[i])
    }
}

// The public radial-gradient fixture is not merely accepted: both authored
// paint servers survive through the CPU rasterizer.
#test
{
    let text    = expect File.readAllText(getTestDataPath("svg-wpt.radialgradient-basic-002.svg"))
    let drawing = expect Svg.Drawing.parse(text.toString())
    let image   = drawing.rasterize(48, 36, 1)
    Swag.require(image.pixelColor(12, 24).a > 0)
    Swag.require(image.pixelColor(36, 24).a > 0)
}

// The public line fixture calibrates its dash pattern through pathLength=25:
// a 200-unit line turns the authored 3/1 sequence into 24/8 user-unit spans.
#test
{
    let text    = expect File.readAllText(getTestDataPath("svg-wpt.line-dasharray.svg"))
    let drawing = expect Svg.Drawing.parse(text.toString())
    let image   = drawing.rasterize(300, 200, 1)
    Swag.require(image.pixelColor(60, 100).a > 0)
    Swag.require(image.pixelColor(78, 100).a == 0)
    Swag.require(image.pixelColor(90, 100).a > 0)

    const OffsetSource = """\
        <svg width='100' height='20'><line x1='0' y1='10' x2='100' y2='10' \
        stroke='blue' stroke-width='2' stroke-dasharray='10 10' stroke-dashoffset='5'/></svg>"""
    let offsetDrawing = expect Svg.Drawing.parse(OffsetSource)
    let offsetImage   = offsetDrawing.rasterize(100, 20, 1)
    Swag.require(offsetImage.pixelColor(2, 10).a > 0)
    Swag.require(offsetImage.pixelColor(8, 10).a == 0)
    Swag.require(offsetImage.pixelColor(18, 10).a > 0)
}

// Sample-aligned tiles preserve every resolved byte when geometry crosses both tile axes.
#test
{
    const Source = """\
        <svg viewBox='0 0 68 68'>\
        <rect x='5' y='5' width='62' height='62' rx='8' fill='#2878d0'/>\
        <circle cx='60' cy='58' r='14' fill='#f4b43c' fill-opacity='0.63'/>\
        <path d='M1 67 L67 1' stroke='white' stroke-width='1'/></svg>"""

    let drawing = expect Svg.Drawing.parse(Source)
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    cpu.begin(68, 68)
    defer renderer.end()

    let tiled   = drawing.rasterizeWithSampleTileSide(renderer, 68, 68, 4, 256)
    let untiled = drawing.rasterizeWithSampleTileSide(renderer, 68, 68, 4, 2048)
    Swag.require(tiled.pixels.count == untiled.pixels.count)

    // A tile paints its geometry at its own offset, so the same sample is reached through
    // different coordinates in the two renders. A stroke measured from its centre line carries a
    // coverage that varies across the whole width rather than saturating over a solid core, which
    // makes it read that last bit of the difference. Losing a sample to the tiling would be worth
    // thousands of them, so the count and the magnitude are both held down rather than demanding
    // equality.
    var apart = 0'u64
    for value, index in tiled.pixels
    {
        let delta = Math.abs(cast(s32, value) - cast(s32, untiled.pixels[index]))
        Swag.require(delta <= 1)
        if delta != 0 do
            apart += 1
    }

    Swag.require(apart < tiled.pixels.count / 1000)
}

// Returns the colors a source paints at five points across a wide band.
private func gradientBand(source: string)->[5] Color
{
    var result: #returntype
    let drawing = expect Svg.Drawing.parse(source)
    let image   = drawing.rasterize(40, 8, 1)
    let columns = [2, 12, 20, 28, 37]
    for column, index in columns do
        result[index] = image.pixelColor(cast(s32, column), 4)

    return result
}

// Cyclic and unresolved gradient references retain each definition's authored stops.
#test
{
    const Source = """\
        <svg width='20' height='10'><defs>\
        <linearGradient id='a' href='#b'/>\
        <linearGradient id='b' href='#a'><stop offset='0' stop-color='red'/></linearGradient>\
        <linearGradient id='missing' href='#unknown'><stop offset='0' stop-color='lime'/></linearGradient>\
        </defs><rect width='10' height='10' fill='url(#a)'/>\
        <rect x='10' width='10' height='10' fill='url(#missing)'/></svg>"""

    let drawing = expect Svg.Drawing.parse(Source)
    let image   = drawing.rasterize(20, 10, 1)
    Swag.require(image.pixelColor(5, 5) == Color.fromRgb(255, 0, 0))
    Swag.require(image.pixelColor(15, 5) == Color.fromRgb(0, 255, 0))
}

// A gradient inherits from the one it references, whichever order the two are written in.
#test
{
    // The referenced gradient is defined after the reference, so the chain is followed once the
    // whole document is read.
    let forward = gradientBand("""\
                               <svg width='40' height='8'><rect width='40' height='8' fill='url(#a)'/>\
                               <linearGradient id='a' href='#b'/>\
                               <linearGradient id='b'><stop offset='0' stop-color='#ff0000'/>\
                               <stop offset='1' stop-color='#0000ff'/></linearGradient></svg>""")
    Swag.require(forward[0].r > 200 and forward[0].b < 60)
    Swag.require(forward[4].b > 200 and forward[4].r < 60)

    // A two-step chain, where the middle link states only the geometry.
    let chained = gradientBand("""\
                               <svg width='40' height='8'>\
                               <linearGradient id='c'><stop offset='0' stop-color='#00ff00'/>\
                               <stop offset='1' stop-color='#000000'/></linearGradient>\
                               <linearGradient id='d' href='#c' x1='0' y1='0' x2='1' y2='0'/>\
                               <linearGradient id='e' href='#d'/>\
                               <rect width='40' height='8' fill='url(#e)'/></svg>""")
    Swag.require(chained[0].g > 200 and chained[4].g < 60)

    // A gradient states its own stops, and inheritance never overwrites them.
    let own = gradientBand("""\
                           <svg width='40' height='8'>\
                           <linearGradient id='f'><stop offset='0' stop-color='#ff0000'/>\
                           <stop offset='1' stop-color='#0000ff'/></linearGradient>\
                           <linearGradient id='g' href='#f'><stop offset='0' stop-color='#000000'/>\
                           <stop offset='1' stop-color='#ffffff'/></linearGradient>\
                           <rect width='40' height='8' fill='url(#g)'/></svg>""")
    Swag.require(own[0].r < 60 and own[0].g < 60 and own[0].b < 60)
    Swag.require(own[4].r > 200 and own[4].g > 200 and own[4].b > 200)
}

// A reference that loops back on itself stops contributing instead of hanging, and the gradient
// keeps what it states itself.
#test
{
    let cycle = gradientBand("""\
                             <svg width='40' height='8'>\
                             <linearGradient id='h' href='#i'><stop offset='0' stop-color='#ffffff'/>\
                             <stop offset='1' stop-color='#000000'/></linearGradient>\
                             <linearGradient id='i' href='#h'/>\
                             <rect width='40' height='8' fill='url(#h)'/></svg>""")
    Swag.require(cycle[0].r > 200 and cycle[4].r < 60)
}
