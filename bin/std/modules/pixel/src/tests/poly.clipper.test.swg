#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Math, Pixel.Clipper

// Signed area of one closed contour, positive for one winding direction and negative for the
// other, so a solution's holes subtract themselves from its outers.
func contourArea(contour: ClipperPath)->f64
{
    let count = contour.count
    if count < 3 do
        return 0

    var total = 0.0'f64
    var prev  = count - 1
    for i in count
    {
        total += cast(f64) (contour[prev].x + contour[i].x) * cast(f64) (contour[prev].y - contour[i].y)
        prev  = i
    }

    return total * 0.5
}

// Area of the region a solution covers, whatever orientation the solver gave its contours.
func solutionArea(paths: ClipperPaths)->f64
{
    var total = 0.0'f64
    for path in paths do
        total += contourArea(path)
    return Math.abs(total)
}

// Runs one boolean operation over two path sets under the nonzero rule.
func runOp(subject, clip: *ClipperPaths, op: ClipType)->ClipperPaths
{
    var result: retval

    var trf: Transform
    for &path in subject do
        trf.addPath(path, .Subject)
    for &path in clip do
        trf.addPath(path, .Clip)
    trf.execute(op, &result, .NonZero, .NonZero)

    return result
}

// Area of the region one set covers on its own, which is the union of the set with nothing.
func selfArea(paths: *ClipperPaths)->f64
{
    var none: ClipperPaths
    return solutionArea(runOp(paths, &none, .Union))
}

// A star-shaped contour around a centre: its vertices sit at increasing angles, so the contour
// never crosses itself whatever radii the generator draws, and every contour of a set winds the
// same way.
func randomContour(rng: *Random.Generator, cx, cy: f64, count: u32)->ClipperPath
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

// A set of one to three star contours scattered over a region wide enough that they sometimes
// miss each other and often overlap.
func randomSet(rng: *Random.Generator)->ClipperPaths
{
    var result: retval

    for rng.nextU32(1, 3)
    {
        let cx = rng.nextF64(-60_000, 60_000)
        let cy = rng.nextF64(-60_000, 60_000)
        result.add(randomContour(rng, cx, cy, rng.nextU32(3, 24)))
    }

    return result
}

// The four boolean operations cover and partition the same plane, so their areas satisfy the
// algebra of a union and an intersection.
//
// The exactness is bounded: the solver rounds a computed crossing to the integer grid by
// rounding its Y and then reading X back off the edge, which slides a nearly horizontal edge's
// crossing along itself by half its slope. That is what the tolerance below covers, and it
// stays two orders of magnitude under what a defect costs — a mis-ordered intersection or an
// overlap test that always answers yes moves an area by a region, not by a boundary.
#test
{
    var rng: Random.Generator
    rng.seedU32(20260903)

    for 200
    {
        var subject = randomSet(&rng)
        var clip    = randomSet(&rng)

        let areaSubject = selfArea(&subject)
        let areaClip    = selfArea(&clip)

        let merged    = solutionArea(runOp(&subject, &clip, .Union))
        let shared    = solutionArea(runOp(&subject, &clip, .Intersection))
        let remainder = solutionArea(runOp(&subject, &clip, .Difference))
        let either    = solutionArea(runOp(&subject, &clip, .Xor))

        let tolerance = 1e-5 * (areaSubject + areaClip) + 1.0
        Swag.assert(Math.abs(merged + shared - areaSubject - areaClip) <= tolerance)
        Swag.assert(Math.abs(remainder - (areaSubject - shared)) <= tolerance)
        Swag.assert(Math.abs(either - (merged - shared)) <= tolerance)
    }
}

// A solution is a set of contours bounding regions that do not overlap, so unioning it with
// nothing gives back exactly the same area — the operation finds no crossing to round.
//
// A solution whose contours do cross each other is what a join stitched to the wrong partner
// leaves behind, and its covered area is then strictly less than the sum of its signed areas.
// This is the sharp form of that check: the tolerance is a rounding epsilon, not a margin.
#test
{
    var rng: Random.Generator
    rng.seedU32(981)

    const Operations: [4] ClipType = [.Union, .Intersection, .Difference, .Xor]

    for 200
    {
        var subject = randomSet(&rng)
        var clip    = randomSet(&rng)

        for op in Operations
        {
            var solution = runOp(&subject, &clip, op)
            let area     = solutionArea(solution)
            Swag.assert(Math.abs(selfArea(&solution) - area) <= 1e-9 * area + 1.0)
        }
    }
}
