#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Math, Pixel.Clipper

func addOffsetRect(list: *Pixel.LinePathList, serial: s32, x, y: f32)
{
    let path = list.newPath()
    path.serial = serial
    path.setRect(x, y, 20, 12)
}

func assertOffsetCleanPreservesPathIdentity()
{
    var paths: Pixel.LinePathList
    addOffsetRect(&paths, 10, 0, 0)
    addOffsetRect(&paths, 20, 100, 0)

    paths.flatten(.Normal)
    paths.offset(2)
    Swag.assert(paths.paths.count == 2)

    Swag.assert(paths.paths[0].serial == 10)
    Swag.assert(paths.paths[1].serial == 20)
    Swag.assert(paths.paths[0].polygon.points.count != 0)
    Swag.assert(paths.paths[1].polygon.points.count != 0)
}

#test
{
    assertOffsetCleanPreservesPathIdentity()
}

// A regular polygon of `sides` corners on a circle of radius `radius`, centred on the origin.
func regularPolygon(sides: u32, radius: f64)->ClipperPath
{
    var result: retval
    result.reserve(sides)

    for i in sides
    {
        let angle = ConstF64.TwoPi * cast(f64) i / cast(f64) sides
        result.add(IntPoint{cast(s64) (radius * Math.cos(angle)), cast(s64) (radius * Math.sin(angle))})
    }

    return result
}

// Runs one offset over one contour and returns the area its solution covers.
func offsetArea(contour: ClipperPath, delta: f64, joinType: JoinType)->{area: f64, contours: u64}
{
    var result: retval

    var off: Offset
    off.arcTolerance = 4        // A chord this far from its arc leaves the area exact to 1e-5.
    off.miterLimit   = 1000     // High enough that a regular polygon's corners never fall back.
    off.addPath(contour, joinType)

    var solution: ClipperPaths
    off.execute(&solution, delta)

    result.area     = solutionArea(solution)
    result.contours = solution.count
    return result
}

// Offsetting a convex region is Steiner's formula, and it is exact.
//
// Growing a convex body by `d` adds a band of the perimeter times `d` plus one full disc of
// radius `d` — the corner wedges of a closed contour always sum to a whole turn. A miter join
// replaces each wedge by the kite that its two edges cut out, which for a regular polygon is
// `d²·tan(π/n)` per corner. Shrinking removes the same band and disc.
//
// This is what says an offset is the shape it claims to be. A join emitted on the wrong side, a
// wedge swept the wrong way, or a union that keeps the offset's own self-intersections all move
// the area by far more than the tolerance below, which only has to cover the polygonal
// approximation of the arcs.
#test
{
    const Sides  = 12'u32
    const Radius = 400_000.0'f64

    let contour   = regularPolygon(Sides, Radius)
    let area      = Math.abs(contourArea(contour))
    let perimeter = 2.0 * cast(f64) Sides * Radius * Math.sin(ConstF64.Pi / cast(f64) Sides)

    for delta in [20_000.0'f64, 60_000.0]
    {
        let cornerTerm = cast(f64) Sides * delta * delta * Math.tan(ConstF64.Pi / cast(f64) Sides)

        let round = offsetArea(contour, delta, .Round)
        Swag.assert(round.contours == 1)
        let expectedRound = area + perimeter * delta + ConstF64.Pi * delta * delta
        Swag.assert(Math.abs(round.area - expectedRound) <= 1e-4 * expectedRound)

        let miter = offsetArea(contour, delta, .Miter)
        Swag.assert(miter.contours == 1)
        let expectedMiter = area + perimeter * delta + cornerTerm
        Swag.assert(Math.abs(miter.area - expectedMiter) <= 1e-4 * expectedMiter)

        // Shrinking stays inside the inradius, so the result is still one convex region — and a
        // convex corner has no arc on the inside, whatever the join type says: the two edges
        // simply meet, so the corner term is the miter's kite either way.
        let expectedShrunk = area - perimeter * delta + cornerTerm
        for joinType in [JoinType.Round, .Miter, .Square]
        {
            let shrunk = offsetArea(contour, -delta, joinType)
            Swag.assert(shrunk.contours == 1)
            Swag.assert(Math.abs(shrunk.area - expectedShrunk) <= 1e-4 * expectedShrunk)
        }
    }
}

// A contour with fewer than three corners encloses nothing, and the count is unsigned: the guard
// has to turn it away rather than compute a length of minus one.
#test
{
    var empty: ClipperPath
    var pair:  ClipperPath
    pair.add(IntPoint{0, 0})
    pair.add(IntPoint{1000, 0})

    var off: Offset
    off.addPath(empty, .Round)
    off.addPath(pair, .Round)

    var solution: ClipperPaths
    off.execute(&solution, 500)
    Swag.assert(solution.isEmpty())
}
