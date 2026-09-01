#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Returns the bounds of the ink a source rasterizes to, in a square of `side` pixels.
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

// `transform` is a full affine matrix: a rotation, a matrix and a skew place geometry where the
// document says, and a nested one composes with the space it is written in.
#test
{
    // The reference: an unrotated bar across the middle.
    let plain = inkBounds("<svg viewBox='0 0 100 100'><rect x='20' y='40' width='60' height='20' fill='#000'/></svg>")
    Swag.assert(plain.minX == 20 and plain.minY == 40 and plain.maxX == 79 and plain.maxY == 59)

    // A quarter turn about the middle stands it up.
    let turned = inkBounds("<svg viewBox='0 0 100 100'><g transform='rotate(90 50 50)'><rect x='20' y='40' width='60' height='20' fill='#000'/></g></svg>")
    Swag.assert(turned.minX == 40 and turned.minY == 20 and turned.maxX == 59 and turned.maxY == 79)

    // The same turn written as a matrix.
    let matrix = inkBounds("<svg viewBox='0 0 100 100'><g transform='matrix(0,1,-1,0,100,0)'><rect x='20' y='40' width='60' height='20' fill='#000'/></g></svg>")
    Swag.assert(matrix.minX == turned.minX and matrix.minY == turned.minY)
    Swag.assert(matrix.maxX == turned.maxX and matrix.maxY == turned.maxY)

    // Half a turn keeps the bounds and covers the same area.
    let half = inkBounds("<svg viewBox='0 0 100 100'><g transform='rotate(45 50 50)'><rect x='20' y='40' width='60' height='20' fill='#000'/></g></svg>")
    Swag.assert(Math.abs(half.minX - 22) <= 1 and Math.abs(half.maxX - 77) <= 1)
    Swag.assert(Math.abs(half.minY - 22) <= 1 and Math.abs(half.maxY - 77) <= 1)

    // A skew leans the bar without moving its rows.
    let skewed = inkBounds("<svg viewBox='0 0 100 100'><g transform='skewX(20)'><rect x='20' y='40' width='40' height='20' fill='#000'/></g></svg>")
    Swag.assert(skewed.minY == 40 and skewed.maxY == 59)
    Swag.assert(skewed.minX > 20 and skewed.maxX > 60)

    // Nested transforms compose: the inner turn happens in the space the outer one placed.
    let nested = inkBounds("<svg viewBox='0 0 100 100'><g transform='translate(50,50)'><g transform='rotate(45)'>" ++
                           "<rect x='-20' y='-5' width='40' height='10' fill='#000'/></g></g></svg>")
    Swag.assert(Math.abs(nested.minX - 32) <= 1 and Math.abs(nested.maxX - 67) <= 1)
    Swag.assert(Math.abs(nested.minY - 32) <= 1 and Math.abs(nested.maxY - 67) <= 1)
}

// An ellipse and a rounded rectangle under a turning transform become the curves they stand for,
// instead of an axis-aligned stand-in placed at the transformed centre.
#test
{
    // A flat ellipse turned by thirty degrees is wider than it is tall, and taller than the
    // untransformed one: an axis-aligned stand-in would keep the original bounds.
    let turned = inkBounds("<svg viewBox='0 0 100 100'><g transform='rotate(30 50 50)'><ellipse cx='50' cy='50' rx='40' ry='10' fill='#000'/></g></svg>")
    Swag.assert(Math.abs(turned.minX - 15) <= 1 and Math.abs(turned.maxX - 84) <= 1)
    Swag.assert(Math.abs(turned.minY - 28) <= 1 and Math.abs(turned.maxY - 71) <= 1)

    // A rounded rectangle keeps its area under a quarter turn, corners included: the curves are
    // written out rather than reduced to an axis-aligned stand-in. The two forms are sampled by
    // different primitives — one raw round rectangle, four cubic corners — so the areas agree to
    // within the handful of pixels that difference is worth, not to the pixel.
    let plain   = inkBounds("<svg viewBox='0 0 100 100'><rect x='20' y='30' width='60' height='40' rx='10' ry='10' fill='#000'/></svg>")
    let rotated = inkBounds("<svg viewBox='0 0 100 100'><g transform='rotate(90 50 50)'><rect x='20' y='30' width='60' height='40' rx='10' ry='10' fill='#000'/></g></svg>")
    Swag.assert(rotated.minX == 30 and rotated.maxX == 69)
    Swag.assert(rotated.minY == 20 and rotated.maxY == 79)
    Swag.assert(Math.abs(rotated.area - plain.area) <= 16)
}

// An arc states its own x-axis rotation, which turns the ellipse it is an arc of.
#test
{
    // Without rotation the chord is the ellipse's own major axis, so the arc is a cap exactly
    // two radii wide and one radius tall.
    let upright = inkBounds("<svg viewBox='0 0 100 100'><path d='M20,50 A30,10 0 1 1 80,50 Z' fill='#000'/></svg>")
    Swag.assert(upright.minX == 20 and upright.maxX == 79)
    Swag.assert(upright.minY == 40 and upright.maxY == 49)

    // A quarter turn puts the short radius across the chord, which no longer spans it: the
    // radii grow to reach and the cap becomes a tall one.
    let quarter = inkBounds("<svg viewBox='0 0 100 100'><path d='M20,50 A30,10 90 1 1 80,50 Z' fill='#000'/></svg>")
    Swag.assert(quarter.minX == 20 and quarter.maxX == 79)
    Swag.assert(quarter.maxY == 49 and quarter.minY < 10)
    Swag.assert(quarter.area > upright.area * 4)

    // A leaning ellipse is neither of the two.
    let leaning = inkBounds("<svg viewBox='0 0 100 100'><path d='M20,50 A30,10 45 1 1 80,50 Z' fill='#000'/></svg>")
    Swag.assert(leaning.area > upright.area and leaning.area < quarter.area)
    Swag.assert(leaning.minX < upright.minX)
}
