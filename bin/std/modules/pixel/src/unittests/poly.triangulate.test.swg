#global #if #command == Swag.CompilerCommand.Test
#global #[Swag.ExplicitNullability]
using Swag, Core, Core.Math

// Direct stress tests for the poly2tri sweep-line triangulation, independent of
// the painter. A simple closed polygon with N vertices triangulates into N-2
// triangles. Regression guard for the edgeIndex() bug, where a constrained-edge
// side test asserted instead of returning -1 (so #null any >=4 vertex polygon crashed).

// Triangulate a closed simple polygon and return the triangle count.
func triCount(pts: #nonull [..] Vector2)->u64
{
    var poly: Pixel.Polygon
    for p in pts do
        poly.add(p)
    let first = pts[0]
    poly.add(first)   // close the ring
    poly.compute()

    var tess: Pixel.Poly2Tri.Tessellate
    tess.addPolyLine(poly)
    tess.triangulate()
    let res = tess.getResult()
    let n   = res.triIndices.count
    tess.clear()
    return n
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
        @assert(triCount(poly[to]) == cast(u64) (n - 2))
    }
}

// Axis-aligned quad and triangle.
#test
{
    var tri  = [Vector2{0, 0}, Vector2{100, 0}, Vector2{50, 100}]
    var quad = [Vector2{0, 0}, Vector2{100, 0}, Vector2{100, 100}, Vector2{0, 100}]

    @assert(triCount(tri) == 1)
    @assert(triCount(quad) == 2)
}

// Concave polygons: still N-2 triangles for a simple ring.
#test
{
    // Concave dart (4 vertices)
    var dart = [Vector2{0, 0}, Vector2{50, 30}, Vector2{100, 0}, Vector2{50, 100}]
    @assert(triCount(dart) == 2)

    // L-shape (6 vertices)
    var lshape = [
        Vector2{0, 0}, Vector2{60, 0}, Vector2{60, 20},
        Vector2{20, 20}, Vector2{20, 60}, Vector2{0, 60},
    ]
    @assert(triCount(lshape) == 4)

    // Plus / cross (12 vertices). Coordinates are deliberately irregular: a
    // perfectly axis-aligned cross makes several vertices share an x/y during the
    // sweep, which is a known degeneracy of the poly2tri algorithm (collinear
    // points are not supported) and unrelated to path construction.
    var plus = [
        Vector2{21, 1}, Vector2{41, 2}, Vector2{43, 21}, Vector2{61, 23},
        Vector2{62, 41}, Vector2{43, 43}, Vector2{41, 61}, Vector2{22, 62},
        Vector2{21, 43}, Vector2{2, 41}, Vector2{1, 22}, Vector2{19, 19},
    ]
    @assert(triCount(plus) == 10)
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
        @assert(triCount(pts[to]) == cast(u64) (total - 2))
    }
}
