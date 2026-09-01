#global if #command == Swag.CompilerCommand.Test

using Swag, Core, Core.Math

// Direct stress tests for the poly2tri sweep-line triangulation, independent of
// the painter. A simple closed polygon with N vertices triangulates into N-2
// triangles. Regression guard for the edgeIndex() bug, where a constrained-edge
// side test asserted instead of returning -1 (so #null any >=4 vertex polygon crashed).

// Triangulate a closed simple polygon and return the triangle count.
func triCount(pts: [..] Vector2)->u64
{
    var poly: Pixel.Polygon
    for p in pts do
        poly.add(p)
    let first = pts[0]
    poly.add(first)     // close the ring
    poly.recompute()

    var tess: Pixel.Poly2Tri.Tessellate
    tess.addPolyLine(poly)
    tess.triangulate()
    let res = tess.takeResult()
    let n   = res.triangleCount()
    tess.clear()
    return n
}

// Cached geometry is identical whether the caller stores a conventional contour
// or repeats the first point as an explicit closing vertex.
#test
{
    var open: Pixel.Polygon
    open.add({0, 0})
    open.add({4, 0})
    open.add({0, 3})
    open.recompute()

    Swag.assert(Math.isEqualEpsilon(open.area, 6, 0.001))
    Swag.assert(Math.isEqualEpsilon(open.perimeter, 12, 0.001))
    Swag.assert(open.minBounds == Vector2{0, 0})
    Swag.assert(open.maxBounds == Vector2{4, 3})
    Swag.assert(open.isClockwise)
    Swag.assert(open.isConvex)
    Swag.assert(open.isSimple)

    var explicitlyClosed = open
    let closingPoint     = explicitlyClosed.points[0]
    explicitlyClosed.add(closingPoint)
    explicitlyClosed.recompute()

    Swag.assert(Math.isEqualEpsilon(explicitlyClosed.area, open.area, 0.001))
    Swag.assert(Math.isEqualEpsilon(explicitlyClosed.perimeter, open.perimeter, 0.001))
    Swag.assert(explicitlyClosed.minBounds == open.minBounds)
    Swag.assert(explicitlyClosed.maxBounds == open.maxBounds)
}

// Degenerate contours remain well-defined and never inherit stale cached bounds.
#test
{
    var poly: Pixel.Polygon
    poly.add({7, 9})
    poly.recompute()
    Swag.assert(poly.area == 0)
    Swag.assert(poly.perimeter == 0)
    Swag.assert(poly.minBounds == Vector2{7, 9})
    Swag.assert(poly.maxBounds == Vector2{7, 9})

    poly.clear()
    poly.recompute()
    Swag.assert(poly.minBounds == Vector2{})
    Swag.assert(poly.maxBounds == Vector2{})
}

// Regular convex N-gon centered at (cx,cy).
func makeNgon(cx, cy, radius: f32, count: s32)->Array'Vector2
{
    var result: retval
    for i in count
    {
        let a = (cast(f32) i) * (Math.ConstF32.TwoPi / cast(f32) count)
        result.add(Vector2{cx + Math.cos(a) * radius, cy + Math.sin(a) * radius})
    }

    return result
}

// Convex polygons: a simple ring of N vertices yields N-2 triangles.
#test
{
    for n in 3 until 13
    {
        let poly = makeNgon(100, 100, 60, n)
        Swag.assert(triCount(poly[to]) == cast(u64) (n - 2))
    }
}

// Axis-aligned quad and triangle.
#test
{
    var tri  = [Vector2{0, 0}, Vector2{100, 0}, Vector2{50, 100}]
    var quad = [Vector2{0, 0}, Vector2{100, 0}, Vector2{100, 100}, Vector2{0, 100}]

    Swag.assert(triCount(tri) == 1)
    Swag.assert(triCount(quad) == 2)
}

// Concave polygons: still N-2 triangles for a simple ring.
#test
{
    // Concave dart (4 vertices)
    var dart = [Vector2{0, 0}, Vector2{50, 30}, Vector2{100, 0}, Vector2{50, 100}]
    Swag.assert(triCount(dart) == 2)

    // L-shape (6 vertices)
    var lshape = [
        Vector2{0, 0}, Vector2{60, 0}, Vector2{60, 20},
        Vector2{20, 20}, Vector2{20, 60}, Vector2{0, 60}]
    Swag.assert(triCount(lshape) == 4)

    // Plus / cross (12 vertices). Coordinates are deliberately irregular: a
    // perfectly axis-aligned cross makes several vertices share an x/y during the
    // sweep, which is a known degeneracy of the poly2tri algorithm (collinear
    // points are not supported) and unrelated to path construction.
    var plus = [
        Vector2{21, 1}, Vector2{41, 2}, Vector2{43, 21}, Vector2{61, 23},
        Vector2{62, 41}, Vector2{43, 43}, Vector2{41, 61}, Vector2{22, 62},
        Vector2{21, 43}, Vector2{2, 41}, Vector2{1, 22}, Vector2{19, 19}]
    Swag.assert(triCount(plus) == 10)
}

// Star polygons (non-convex, many concavities) with 3..10 branches.
#test
{
    for b in 3 until 11
    {
        var pts: Array'Vector2
        let total = b * 2
        for i in total
        {
            var r = 25'f32
            if (i & 1) == 0 do
                r = 60
            let a = (cast(f32) i) * (Math.ConstF32.TwoPi / cast(f32) total)
            pts.add(Vector2{100 + Math.cos(a) * r, 100 + Math.sin(a) * r})
        }

        // A 2b-vertex simple star ring -> 2b-2 triangles.
        Swag.assert(triCount(pts[to]) == cast(u64) (total - 2))
    }
}

// Triangulates one closed ring twice: once through 'reused', which has already run, and once
// through a tessellator that never has.
func assertRecycledMatchesFresh(reused: *Pixel.Poly2Tri.Tessellate, pts: [..] Vector2)
{
    var poly: Pixel.Polygon
    for pt in pts do
        poly.add(pt)
    poly.add(pts[0])
    poly.recompute()

    reused.addPolyLine(poly)
    reused.triangulate()
    let recycled = reused.takeResult()
    reused.clear()

    var fresh: Pixel.Poly2Tri.Tessellate
    fresh.addPolyLine(poly)
    fresh.triangulate()
    let expected = fresh.takeResult()

    Swag.assert(recycled.vertices.count == expected.vertices.count)
    for index in recycled.vertices.count do
        Swag.assert(recycled.vertices[index] == expected.vertices[index])
}

// One tessellator serves every fill of a frame, and it recycles its points, edges and triangles
// from one tessellation to the next rather than returning them to the allocator. A recycled
// object still carrying anything of the shape before it would corrupt the sweep, so a reused
// tessellator has to answer exactly what a fresh one answers, run after run.
#test
{
    let ngon   = makeNgon(100, 100, 60, 7)
    var dart   = [Vector2{0, 0}, Vector2{50, 30}, Vector2{100, 0}, Vector2{50, 100}]
    var lshape = [
        Vector2{0, 0}, Vector2{60, 0}, Vector2{60, 20},
        Vector2{20, 20}, Vector2{20, 60}, Vector2{0, 60}]

    var reused: Pixel.Poly2Tri.Tessellate
    for pass in 3
    {
        assertRecycledMatchesFresh(&reused, ngon[to])
        assertRecycledMatchesFresh(&reused, dart)
        assertRecycledMatchesFresh(&reused, lshape)
    }
}
