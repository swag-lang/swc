#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Math, Pixel.Clipper

// How one operation is set up: the two fill rules and whether self-touching contours are split.
struct Rules
{
    subject:      PolyFillType = NonZero
    clip:         PolyFillType = NonZero
    strictSimple: bool
}

// Runs one boolean operation over two path sets.
func runOp(subject, clip: *ClipperPaths, op: ClipType, rules: Rules)->ClipperPaths
{
    var result: retval

    var trf: Transform
    trf.strictSimple = rules.strictSimple
    for &path in subject do
        trf.addPath(path, .Subject)
    for &path in clip do
        trf.addPath(path, .Clip)
    trf.execute(op, &result, rules.subject, rules.clip)

    return result
}

// Area of the region one set covers on its own, which is the union of the set with nothing under
// that set's own rule.
func selfArea(paths: *ClipperPaths, rule: PolyFillType, strictSimple: bool)->f64
{
    var none: ClipperPaths
    return solutionArea(runOp(paths, &none, .Union, {rule, rule, strictSimple}))
}

// The shapes a generator can draw. Each stresses a different part of the solver.
enum Shape
{
    Star     // Smooth outlines that cross each other at general angles.
    Grid     // Axis-aligned cells on a coarse lattice: shared edges, long horizontal runs.
    Comb     // A spiky outline whose teeth touch and overlap along vertical walls.
}

// A star-shaped contour around a centre: its vertices sit at increasing angles, so the contour
// never crosses itself whatever radii the generator draws.
func starContour(rng: *Random.Generator, cx, cy: f64, count: u32)->ClipperPath
{
    var result: retval
    result.reserve(count)

    for i in count
    {
        let angle  = ConstF64.TwoPi * cast(f64) i / cast(f64) count
        let radius = rng.nextF64(20_000, 90_000)
        result.add(IntPoint{cast(s64) (cx + radius * Math.cos(angle)), cast(s64) (cy + radius * Math.sin(angle))})
    }

    return result
}

// A rectangle whose corners land on a coarse lattice, then slide by at most one unit. Neighbours
// share whole edges, meet exactly at a corner, or miss by a thousandth of a cell — the three
// arrangements a horizontal join has to tell apart, and the one that froze a real document.
func gridContour(rng: *Random.Generator)->ClipperPath
{
    const Cell = 20_000'f64

    var result: retval
    let col = cast(f64) rng.nextS32(-3, 3)
    let row = cast(f64) rng.nextS32(-3, 3)
    let x0  = cast(s64) (col * Cell) + cast(s64) rng.nextS32(-1, 1)
    let y0  = cast(s64) (row * Cell) + cast(s64) rng.nextS32(-1, 1)
    let x1  = x0 + cast(s64) (Cell * cast(f64) rng.nextU32(1, 3))
    let y1  = y0 + cast(s64) (Cell * cast(f64) rng.nextU32(1, 3))

    result.add(IntPoint{x0, y0})
    result.add(IntPoint{x1, y0})
    result.add(IntPoint{x1, y1})
    result.add(IntPoint{x0, y1})
    return result
}

// A row of teeth of random height standing on a common base, so consecutive contours overlap
// along vertical walls and share their base exactly.
func combContour(rng: *Random.Generator, teeth: u32)->ClipperPath
{
    var result: retval

    let x0   = cast(s64) rng.nextS32(-60_000, 60_000)
    let y0   = cast(s64) rng.nextS32(-60_000, 60_000)
    let step = cast(s64) rng.nextS32(4_000, 12_000)

    for i in teeth
    {
        let x = x0 + cast(s64) i * step
        result.add(IntPoint{x, y0})
        result.add(IntPoint{x, y0 + cast(s64) rng.nextS32(5_000, 40_000)})
        result.add(IntPoint{x + step / 2, y0 + cast(s64) rng.nextS32(5_000, 40_000)})
    }

    result.add(IntPoint{x0 + cast(s64) teeth * step, y0})
    return result
}

// A set of one to four contours of the requested shape.
func randomSet(rng: *Random.Generator, shape: Shape)->ClipperPaths
{
    var result: retval

    for rng.nextU32(1, 4)
    {
        switch shape
        {
        case .Star:
            let cx = rng.nextF64(-60_000, 60_000)
            let cy = rng.nextF64(-60_000, 60_000)
            result.add(starContour(rng, cx, cy, rng.nextU32(3, 24)))

        case .Grid:
            result.add(gridContour(rng))

        case .Comb:
            result.add(combContour(rng, rng.nextU32(2, 8)))
        }
    }

    return result
}

// Checks that the four operations over one pair of sets satisfy the algebra of areas.
//
// The exactness is bounded: the solver rounds a computed crossing to the integer grid by
// rounding its Y and then reading X back off the edge, which slides a nearly horizontal edge's
// crossing along itself by half its slope. That is what the tolerance covers, and it stays two
// orders of magnitude under what a defect costs — a mis-ordered intersection or an overlap test
// that always answers yes moves an area by a region, not by a boundary.
func assertBooleanAlgebra(subject, clip: *ClipperPaths, rules: Rules)
{
    let areaSubject = selfArea(subject, rules.subject, rules.strictSimple)
    let areaClip    = selfArea(clip, rules.clip, rules.strictSimple)

    let merged    = solutionArea(runOp(subject, clip, .Union, rules))
    let shared    = solutionArea(runOp(subject, clip, .Intersection, rules))
    let remainder = solutionArea(runOp(subject, clip, .Difference, rules))
    let either    = solutionArea(runOp(subject, clip, .Xor, rules))

    let tolerance = 3e-5 * (areaSubject + areaClip) + 1.0
    Swag.assert(Math.abs(merged + shared - areaSubject - areaClip) <= tolerance)
    Swag.assert(Math.abs(remainder - (areaSubject - shared)) <= tolerance)
    Swag.assert(Math.abs(either - (merged - shared)) <= tolerance)
}

// Checks that every operation over one pair of sets returns contours that bound regions which do
// not overlap.
//
// Unioning a solution with nothing has to give back exactly the same area, because that operation
// finds no crossing to round. A solution whose contours do cross each other is what a join
// stitched to the wrong partner leaves behind, and its covered area is then strictly less than the
// sum of its signed areas. This is the sharp form of the check: the tolerance is a rounding
// epsilon, not a margin.
func assertSolutionsAreSimple(subject, clip: *ClipperPaths, rules: Rules)
{
    const Operations: [4] ClipType = [.Union, .Intersection, .Difference, .Xor]

    for op in Operations
    {
        var solution = runOp(subject, clip, op, rules)
        let area     = solutionArea(solution)
        Swag.assert(Math.abs(selfArea(&solution, .NonZero, rules.strictSimple) - area) <= 1e-9 * area + 1.0)
    }
}

// The boolean algebra holds over smooth outlines that cross at general angles, over axis-aligned
// cells that share their edges, and over combs whose teeth overlap along vertical walls — under
// every fill rule, and whether or not self-touching contours are split.
#test
{
    const Shapes: [3] Shape        = [.Star, .Grid, .Comb]
    const Fills:  [4] PolyFillType = [.NonZero, .EvenOdd, .Positive, .Negative]

    var rng: Random.Generator
    rng.seedU32(20260903)

    for shape in Shapes
    {
        for fill in Fills
        {
            for round in 24
            {
                var subject = randomSet(&rng, shape)
                var clip    = randomSet(&rng, shape)
                assertBooleanAlgebra(&subject, &clip, {fill, fill, strictSimple: (round & 1) == 1})
            }
        }
    }
}

// Every operation returns simple, non-overlapping contours, over the same shapes and rules.
#test
{
    const Shapes: [3] Shape        = [.Star, .Grid, .Comb]
    const Fills:  [4] PolyFillType = [.NonZero, .EvenOdd, .Positive, .Negative]

    var rng: Random.Generator
    rng.seedU32(981)

    for shape in Shapes
    {
        for fill in Fills
        {
            for round in 24
            {
                var subject = randomSet(&rng, shape)
                var clip    = randomSet(&rng, shape)
                assertSolutionsAreSimple(&subject, &clip, {fill, fill, strictSimple: (round & 1) == 1})
            }
        }
    }
}

// Coordinates above the low range switch the slope tests onto 128-bit products. Nothing in this
// repository scales that far — a page of a document reaches about a million units — so the
// algebra is checked there explicitly rather than by accident.
#test
{
    var rng: Random.Generator
    rng.seedU32(77)

    // Just past 0x3FFFFFFF, where `rangeTest` gives up on 64-bit products.
    const Origin = 2_000_000_000'f64

    for 12
    {
        var subject: ClipperPaths
        var clip:    ClipperPaths
        subject.add(starContour(&rng, Origin, Origin, rng.nextU32(3, 12)))
        clip.add(starContour(&rng, Origin, Origin, rng.nextU32(3, 12)))
        assertBooleanAlgebra(&subject, &clip, {})
        assertSolutionsAreSimple(&subject, &clip, {})
    }
}
