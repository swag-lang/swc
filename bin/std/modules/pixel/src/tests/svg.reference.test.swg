#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Returns the bounds and the area of the ink a source rasterizes to, in a square of `side`.
private func inkBounds(source: string, side = 100's32)->{ minX, minY, maxX, maxY: s32, area: s32 }
{
    var result: retval
    result.minX = side
    result.minY = side
    result.maxX = -1
    result.maxY = -1

    let drawing = expect Svg.Drawing.parse(source)
    let image   = drawing.rasterize(side, side, 2)
    for y in side
    {
        for x in side where image.pixelColor(x, y).a >= 128
        {
            result.area += 1
            result.minX = Math.min(result.minX, x)
            result.minY = Math.min(result.minY, y)
            result.maxX = Math.max(result.maxX, x)
            result.maxY = Math.max(result.maxY, y)
        }
    }

    return result
}

// A `clip-path` keeps only the part of an element the clip covers.
#test
{
    const Unclipped = "<svg viewBox='0 0 100 100'><rect x='10' y='10' width='80' height='80' fill='#000'/></svg>"
    let plain = inkBounds(Unclipped)
    Swag.assert(plain.area == 6400)

    // A rectangular clip cuts the square down to the columns it holds.
    let rect = inkBounds("<svg viewBox='0 0 100 100'><clipPath id='c'><rect x='10' y='10' width='40' height='80'/></clipPath>" ++
                         "<rect x='10' y='10' width='80' height='80' fill='#000' clip-path='url(#c)'/></svg>")
    Swag.assert(rect.minX == 10 and rect.maxX == 49)
    Swag.assert(rect.area == 3200)

    // A round clip leaves a disc, not its bounding box.
    let disc = inkBounds("<svg viewBox='0 0 100 100'><clipPath id='c'><circle cx='50' cy='50' r='25'/></clipPath>" ++
                         "<rect width='100' height='100' fill='#000' clip-path='url(#c)'/></svg>")
    Swag.assert(disc.minX == 25 and disc.maxX == 74)
    Swag.assert(disc.minY == 25 and disc.maxY == 74)
    Swag.assert(Math.abs(disc.area - 1963) < 100)

    // A reference to nothing leaves the element alone rather than hiding it.
    let missing = inkBounds("<svg viewBox='0 0 100 100'><rect x='10' y='10' width='80' height='80' fill='#000' clip-path='url(#nothing)'/></svg>")
    Swag.assert(missing.area == plain.area)
}

// A clip stated on a group applies to every child, in the group's own space: a child that
// transforms itself moves under the clip instead of taking the clip with it.
#test
{
    let clipped = inkBounds("<svg viewBox='0 0 100 100'><clipPath id='c'><rect width='50' height='100'/></clipPath>" ++
                            "<g clip-path='url(#c)'><rect width='40' height='40' fill='#000'/>" ++
                            "<rect x='40' y='50' width='40' height='40' fill='#000'/></g></svg>")

    // The first square is inside the clip; the second keeps only its first ten columns.
    Swag.assert(clipped.area == 1600 + 400)
    Swag.assert(clipped.maxX == 49)
}

// Two elements clipped by different paths do not inherit each other's region.
#test
{
    const Source = "<svg viewBox='0 0 100 100'>" ++
                   "<clipPath id='left'><rect width='50' height='100'/></clipPath>" ++
                   "<clipPath id='top'><rect width='100' height='50'/></clipPath>" ++
                   "<rect y='60' width='100' height='40' fill='#000' clip-path='url(#left)'/>" ++
                   "<rect x='60' width='40' height='100' fill='#000' clip-path='url(#top)'/></svg>"

    let both = inkBounds(Source)
    Swag.assert(both.area == 50 * 40 + 40 * 50)
    Swag.assert(both.minX == 0 and both.maxX == 99)
    Swag.assert(both.minY == 0 and both.maxY == 99)
}

// A `symbol` brings its own viewport: a `use` fits the view box into the size it asks for.
#test
{
    let scaled = inkBounds("<svg viewBox='0 0 100 100'>" ++
                           "<defs><symbol id='s' viewBox='0 0 10 10'><rect width='10' height='5' fill='#000'/></symbol></defs>" ++
                           "<use href='#s' x='20' y='20' width='60' height='60'/></svg>")
    Swag.assert(scaled.minX == 20 and scaled.maxX == 79)
    Swag.assert(scaled.minY == 20 and scaled.maxY == 49)
    Swag.assert(scaled.area == 60 * 30)

    // An ordinary definition has no viewport, so a `use` only offsets it.
    let plain = inkBounds("<svg viewBox='0 0 100 100'><defs><rect id='r' width='20' height='10' fill='#000'/></defs>" ++
                          "<use href='#r' x='30' y='40'/></svg>")
    Swag.assert(plain.minX == 30 and plain.maxX == 49)
    Swag.assert(plain.minY == 40 and plain.maxY == 49)
}

// Markers are drawn on the vertices of a contour, turned by the direction it runs in.
#test
{
    const Marker = "<defs><marker id='tip' viewBox='0 0 10 10' refX='5' refY='5' markerWidth='10' markerHeight='10' orient='auto'>" ++
                   "<rect x='0' y='4' width='10' height='2' fill='#000'/></marker></defs>"

    // On a horizontal line the marker keeps its own orientation: a bar two units tall.
    let horizontal = inkBounds("<svg viewBox='0 0 100 100'>" ++ Marker ++
                               "<path d='M20,50 L80,50' fill='none' stroke='none' stroke-width='1' marker-end='url(#tip)'/></svg>")
    Swag.assert(horizontal.maxX - horizontal.minX > horizontal.maxY - horizontal.minY)
    Swag.assert(horizontal.minX == 75 and horizontal.maxX == 84)

    // On a vertical line the same marker stands up, which is what `orient="auto"` states.
    let vertical = inkBounds("<svg viewBox='0 0 100 100'>" ++ Marker ++
                             "<path d='M50,20 L50,80' fill='none' stroke='none' stroke-width='1' marker-end='url(#tip)'/></svg>")
    Swag.assert(vertical.maxY - vertical.minY > vertical.maxX - vertical.minX)
    Swag.assert(vertical.minY == 75 and vertical.maxY == 84)

    // Every position is addressable, and the count of drawn markers follows the vertices.
    let all = inkBounds("<svg viewBox='0 0 100 100'>" ++ Marker ++
                        "<polyline points='20,50 50,50 80,50' fill='none' stroke='none' stroke-width='1' " ++
                        "marker-start='url(#tip)' marker-mid='url(#tip)' marker-end='url(#tip)'/></svg>")
    Swag.assert(all.area == 3 * horizontal.area)

    // The shorthand covers all three positions at once.
    let shorthand = inkBounds("<svg viewBox='0 0 100 100'>" ++ Marker ++
                              "<polyline points='20,50 50,50 80,50' fill='none' stroke='none' stroke-width='1' marker='url(#tip)'/></svg>")
    Swag.assert(shorthand.area == all.area)
}

// `markerUnits` decides whether the stroke width scales the marker, and `orient` may state a
// fixed angle instead of following the contour.
#test
{
    const Definition = "<defs>" ++
                       "<marker id='scaled' viewBox='0 0 10 10' refX='5' refY='5' markerWidth='10' markerHeight='10' orient='0'>" ++
                       "<rect width='10' height='10' fill='#000'/></marker>" ++
                       "<marker id='fixed' viewBox='0 0 10 10' refX='5' refY='5' markerWidth='10' markerHeight='10' orient='0' markerUnits='userSpaceOnUse'>" ++
                       "<rect width='10' height='10' fill='#000'/></marker></defs>"

    // The default units multiply the marker by the stroke width.
    let scaled = inkBounds("<svg viewBox='0 0 100 100'>" ++ Definition ++
                           "<path d='M20,50 L50,50' fill='none' stroke='none' stroke-width='3' marker-end='url(#scaled)'/></svg>")
    Swag.assert(scaled.maxX - scaled.minX == 29)

    // User-space units ignore it.
    let fixed = inkBounds("<svg viewBox='0 0 100 100'>" ++ Definition ++
                          "<path d='M20,50 L50,50' fill='none' stroke='none' stroke-width='3' marker-end='url(#fixed)'/></svg>")
    Swag.assert(fixed.maxX - fixed.minX == 9)
}
