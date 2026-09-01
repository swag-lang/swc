#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Math

// Two nested clockwise squares: a shape whose ruled fill needs normalization, and whose
// direction fill does not.
func nestedSquares()->LinePathList
{
    var result: retval
    with let outer = result.newPath()
    {
        .start(0, 0)
        .lineTo(100, 0)
        .lineTo(100, 100)
        .lineTo(0, 100)
        .close()
    }

    with let hole = result.newPath()
    {
        .start(25, 25)
        .lineTo(75, 25)
        .lineTo(75, 75)
        .lineTo(25, 75)
        .close()
    }

    return result
}

// The ruled fill normalizes once per geometry change: the same list answers the cached copy,
// a rule change rebuilds it, and a geometry change rebuilds it again.
#test
{
    var list = nestedSquares()
    list.flatten(.Normal)

    // Under the alternating rule two nested same-direction contours enclose a ring.
    let ring = list.normalizedFill(.EvenOdd, byDirection: false)
    Swag.assert(ring != &list)
    Swag.assert(ring.count() == 2)

    // An unchanged list answers the exact cached storage.
    Swag.assert(list.normalizedFill(.EvenOdd, byDirection: false) == ring)

    // Under the winding count the inner contour counts twice and the shape is solid.
    let solid = list.normalizedFill(.NonZero, byDirection: false)
    Swag.assert(solid.count() == 1)

    // A geometry change is seen through the contours' revisions and rebuilds the cache.
    with let hole = list.paths[1]
    {
        .start(10, 10)
        .lineTo(20, 10)
        .lineTo(20, 20)
        .lineTo(10, 20)
        .close()
    }

    list.flatten(.Normal)
    let moved = list.normalizedFill(.EvenOdd, byDirection: false)
    Swag.assert(moved.count() == 2)
    var holeBounds: Math.Rectangle
    for p in moved.paths where !p.polygon.isClockwise do
        holeBounds = {p.minBounds.x, p.minBounds.y, p.maxBounds.x - p.minBounds.x, p.maxBounds.y - p.minBounds.y}
    Swag.assert(Math.isEqualEpsilon(holeBounds.x, 10, 0.01) and Math.isEqualEpsilon(holeBounds.width, 10, 0.01))
}

// The direction fill hands back the list itself when its simple contours already express the
// region, and caches that verdict too.
#test
{
    var list = nestedSquares()
    list.flatten(.Normal)
    Swag.assert(list.normalizedFill(.NonZero, byDirection: true) == &list)
    Swag.assert(list.normalizedFill(.NonZero, byDirection: true) == &list)

    // A self-intersecting contour cannot be triangulated as it is, so the direction fill
    // normalizes it — once.
    var bowtie: LinePathList
    with let path = bowtie.newPath()
    {
        .start(0, 0)
        .lineTo(100, 100)
        .lineTo(100, 0)
        .lineTo(0, 100)
        .close()
    }

    bowtie.flatten(.Normal)
    let cleaned = bowtie.normalizedFill(.NonZero, byDirection: true)
    Swag.assert(cleaned != &bowtie)
    Swag.assert(bowtie.normalizedFill(.NonZero, byDirection: true) == cleaned)
}

// A deep copy leaves the fill cache with the source and rebuilds its own.
#test
{
    var list = nestedSquares()
    list.flatten(.Normal)
    let ring = list.normalizedFill(.EvenOdd, byDirection: false)

    var copy = list
    copy.flatten(.Normal)
    let copyRing = copy.normalizedFill(.EvenOdd, byDirection: false)
    Swag.assert(copyRing != ring)
    Swag.assert(copyRing.count() == 2)
    Swag.assert(list.normalizedFill(.EvenOdd, byDirection: false) == ring)
}

// Filling through the painter keeps the normalized copy's tessellation from one fill to the
// next, which is what makes repainting an unchanged shape cheap.
#test
{
    var list = nestedSquares()

    var painter: Painter
    painter.begin()
    painter.fillPath(&list, Color.fromArgb(Argb.Black), .EvenOdd)
    painter.end()

    let cache         = list.fillCache!
    var triangleCount = 0'u64
    for p in cache.paths do
        triangleCount += p.triangles.vertices.count
    Swag.assert(triangleCount > 0)

    painter.begin()
    painter.fillPath(&list, Color.fromArgb(Argb.Black), .EvenOdd)
    painter.end()
    Swag.assert(list.fillCache! == cache)
    var again = 0'u64
    for p in cache.paths do
        again += p.triangles.vertices.count
    Swag.assert(again == triangleCount)
}

// The flattening tolerance follows the declared scale: a zoomed curve takes more segments,
// and the finest flattening produced so far stays cached.
#test
{
    var path: LinePath
    path.setEllipseRaw(50, 50, 40, 40)
    path.flatten(.Normal)
    let coarse = path.polygon.points.count
    path.flatten(.Normal, 8)
    let fine = path.polygon.points.count
    Swag.assert(fine > coarse)
    path.flatten(.Normal)
    Swag.assert(path.polygon.points.count == fine)
}

// The painter quantizes the flattening scale to power-of-two buckets, between a sixty-fourth
// and sixty-four.
#test
{
    var painter: Painter
    Swag.assert(painter.flattenScale() == 1)
    painter.setFlattenScale(1.7)
    Swag.assert(painter.flattenScale() == 1)
    painter.setFlattenScale(2)
    Swag.assert(painter.flattenScale() == 2)
    painter.setFlattenScale(11.9)
    Swag.assert(painter.flattenScale() == 8)
    painter.setFlattenScale(1000)
    Swag.assert(painter.flattenScale() == 64)
    painter.setFlattenScale(0.2)
    Swag.assert(painter.flattenScale() == 0.125)
    painter.setFlattenScale(0.5)
    Swag.assert(painter.flattenScale() == 0.5)
    painter.setFlattenScale(0.0001)
    Swag.assert(painter.flattenScale() == 1.0'f32 / 64)
}

// A minified pass never coarsens the flattening itself: a contour keeps the finest
// tessellation anything asked of it, whichever order the consumers arrived in.
#test
{
    var path: LinePath
    path.setEllipseRaw(50, 50, 40, 40)
    path.flatten(.Normal)
    let expected = path.polygon.points.count
    path.flatten(.Normal, 1.0 / 32)
    Swag.assert(path.polygon.points.count == expected)
}
