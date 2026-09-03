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

// A closed square whose corners are `(x, y)` and `(x + size, y + size)`.
func square(x, y, size: f32)->LinePathList
{
    var result: retval
    with let path = result.newPath()
    {
        .start(x, y)
        .lineTo(x + size, y)
        .lineTo(x + size, y + size)
        .lineTo(x, y + size)
        .close()
    }

    return result
}

// A transform maps every segment kind, and an arc is rewritten so that it maps exactly.
#test
{
    var list        = square(0, 0, 10)
    with let curved = list.newPath()
    {
        .start(20, 0)
        .bezierTo(30, 10, 20, 10)
        .bezierTo(40, 0, 35, 10, 40, 10)
    }

    var placement = Math.Transform2.createScale(2, 3, 0, 0)
    placement.multiply(Math.Transform2.createTranslation(5, 7))
    list.transform(placement)

    let bounds = list.controlBounds()
    Swag.assert(Math.isEqualEpsilon(bounds.x, 5, 0.001) and Math.isEqualEpsilon(bounds.y, 7, 0.001))
    Swag.assert(Math.isEqualEpsilon(bounds.width, 80, 0.001) and Math.isEqualEpsilon(bounds.height, 30, 0.001))
    Swag.assert(list.paths[1].startPoint.isEqualEpsilon({45, 7}, 0.001))
    Swag.assert(list.paths[1].endPoint.isEqualEpsilon({85, 7}, 0.001))

    // A half circle of radius 10 about (10, 10) becomes a half ellipse about (25, 37) with radii
    // 20 and 30: every flattened point lies on it.
    var arc: LinePathList
    with let path = arc.newPath()
    {
        .start(10, 0)
        .arcTo(10, 10, 10, 10, 0.0'deg, 180.0'deg)
    }

    arc.transform(placement)
    arc.flatten(.High)
    let polygon = arc.paths[0].flattenedPolygon(.High)
    Swag.assert(polygon.points.count > 8)
    for i in polygon.points.count
    {
        let pt = polygon.points[i]
        let dx = (pt.x - 25) / 20
        let dy = (pt.y - 37) / 30
        Swag.assert(Math.isEqualEpsilon(dx * dx + dy * dy, 1, 0.01))
    }
}

// An intersection keeps the region two lists share, honours each list's rule, and leaves
// nothing when they share no region.
#test
{
    var shape = square(0, 0, 100)
    var clip  = square(50, 50, 100)
    shape.flatten(.Normal)
    clip.flatten(.Normal)
    shape.intersect(&clip)
    Swag.assert(shape.count() == 1)
    Swag.assert(shape.minBounds.isEqualEpsilon({50, 50}, 0.01))
    Swag.assert(shape.maxBounds.isEqualEpsilon({100, 100}, 0.01))

    // A ring under the alternating rule clips as a ring: its hole lets nothing through.
    var ring = nestedSquares()
    var full = square(0, 0, 100)
    ring.flatten(.Normal)
    full.flatten(.Normal)
    full.intersect(&ring, .NonZero, .EvenOdd)
    Swag.assert(full.count() == 2)

    var far = square(500, 500, 10)
    far.flatten(.Normal)
    shape.intersect(&far)
    Swag.assert(shape.count() == 0)
}

// One cell of a table, by its corners in page units.
struct Cell
{
    left, top, right, bottom: f32
}

// A table whose column boundary is authored at 44.815002 on one side and 44.814999 on the other.
// The solver works in integers, so the two land one unit apart and the columns overlap along a
// strip a thousandth of a pixel wide: the cells touch along horizontal runs it has to stitch.
// Two such runs meeting head on used to be joined back to front, leaving a point whose successor
// did not name it as its predecessor; tidying that ring never terminated, and a real document
// froze its viewer on the page that holds this table.
const TouchingCells: [5] Cell = [
    {34.894001, 195.505005, 44.815002, 206.843994},
    {34.894001, 206.843018, 44.815002, 218.182007},
    {44.814999, 206.843018, 54.736000, 218.182007},
    {34.894001, 218.182007, 44.815002, 229.520996},
    {44.814999, 218.182007, 54.736000, 229.520996}]

#test
{
    var list: LinePathList
    for cell in TouchingCells
    {
        with let path = list.newPath()
        {
            .start(cell.left, cell.top)
            .lineTo(cell.right, cell.top)
            .lineTo(cell.right, cell.bottom)
            .lineTo(cell.left, cell.bottom)
            .close()
        }
    }

    list.flatten()
    list.clean()

    // The strip joins the two columns, so the union is one contour: the full left column with
    // the right column's pair of cells attached below its own top edge.
    Swag.assert(list.count() == 1)
    Swag.assert(list.minBounds.isEqualEpsilon({34.894, 195.505}, 0.01))
    Swag.assert(list.maxBounds.isEqualEpsilon({54.736, 229.521}, 0.01))

    // Six corners, because the step from the left column's top down to the right column's is the
    // only place the outline turns away from its bounding box.
    let outline = list.paths[0].polygon.points
    Swag.assert(outline.count == 7 and outline[0] == outline[6])
    Swag.assert(outline[3].isEqualEpsilon({44.815, 195.505}, 0.01))
    Swag.assert(outline[4].isEqualEpsilon({44.815, 206.843}, 0.01))
}
