#global #if #command == Swag.CompilerCommand.Test
using Swag, Core, Core.Math

// Stress the Painter polygon/path pipeline (flatten -> clean -> triangulate ->
// fringe AA). This is the path exercised by the pixel1 example; non-convex
// antialiased fills used to crash in the triangulation (poly2tri.edgeIndex).

// Build a closed star polygon with 'branches' points.
func makeStar(cx, cy, outer, inner: f32, branches: s32)->Array'Vector2
{
    var result: retval
    let total = branches * 2
    for i in total
    {
        var r = inner
        if (i & 1) == 0 do
            r = outer
        let a = -Math.ConstF32.Pi * 0.5 + (cast(f32) i) * (Math.ConstF32.TwoPi / cast(f32) total)
        result.add(Vector2{cx + Math.cos(a) * r, cy + Math.sin(a) * r})
    }
    return result
}

// Build a closed line path from a list of points (mirrors the pixel1 example).
func buildClosedPath(pts: [..] Vector2)->Pixel.LinePath
{
    var result: retval
    let first = pts[0]
    result.start(first.x, first.y)
    foreach pt in pts where @index do
        result.lineTo(pt.x, pt.y)
    result.close()
    return result
}

// Fill a polygon and return the number of generated vertices.
func fillCount(pts: [..] Vector2, aa: bool)->u64
{
    var painter: Pixel.Painter
    painter.begin()
    painter.setAntialiased(aa)
    painter.fillPolygon(pts, Pixel.Brush.createSolid(Argb.Goldenrod))
    let n = painter.vertexBuffer.count
    painter.end()
    return n
}

// A 5-point star, antialiased and aliased, must produce geometry (no crash).
#test
{
    let star = makeStar(100, 100, 60, 25, 5)
    @assert(fillCount(star[to], false) > 0)
    @assert(fillCount(star[to], true) > 0)
}

// Stars with 3..12 branches: a wide range of non-convex contours.
#test
{
    for b in 3 until 13
    {
        let star = makeStar(200, 200, 80, 30, b)
        @assert(fillCount(star[to], true) > 0)
    }
}

// Assorted concave shapes.
#test
{
    var lshape = [
        Vector2{0, 0}, Vector2{60, 0}, Vector2{60, 20},
        Vector2{20, 20}, Vector2{20, 60}, Vector2{0, 60},
    ]
    @assert(fillCount(lshape, true) > 0)

    var dart = [
        Vector2{0, 0}, Vector2{50, 30}, Vector2{100, 0}, Vector2{50, 100},
    ]
    @assert(fillCount(dart, true) > 0)

    var comb: Array'Vector2
    comb.add(Vector2{0, 0})
    for i in 4
    {
        let x = cast(f32) (i * 20)
        comb.add(Vector2{x + 5, 40})
        comb.add(Vector2{x + 10, 0})
    }
    comb.add(Vector2{80, 60})
    comb.add(Vector2{0, 60})
    @assert(fillCount(comb[to], true) > 0)
}

// Convex fills (fast, non-triangulated path).
#test
{
    var quad = [Vector2{0, 0}, Vector2{100, 0}, Vector2{100, 100}, Vector2{0, 100}]
    @assert(fillCount(quad, true) > 0)
    @assert(fillCount(quad, false) > 0)

    var tri = [Vector2{0, 0}, Vector2{100, 0}, Vector2{50, 100}]
    @assert(fillCount(tri, true) > 0)

    let hexa = makeStar(50, 50, 40, 40, 3) // outer==inner -> convex hexagon
    @assert(fillCount(hexa[to], true) > 0)
}

// Closed outline stroking through drawPath.
#test
{
    let star = makeStar(100, 100, 60, 25, 5)
    var path = buildClosedPath(star[to])

    var painter: Pixel.Painter
    painter.begin()
    painter.setAntialiased(true)
    painter.drawPath(&path, Pixel.Pen.createSolid(Argb.MidnightBlue, 4))
    @assert(painter.vertexBuffer.count > 0)
    painter.end()
}
