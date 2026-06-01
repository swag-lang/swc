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

func buildBlobPath()->Pixel.LinePath
{
    var result: retval
    let cx = 320.0
    let cy = 240.0

    result.start(cx - 168, cy - 18)
    result.bezierTo(cx - 44, cy - 136, cx - 160, cy - 110, cx - 102, cy - 150)
    result.bezierTo(cx + 156, cy - 24, cx + 30, cy - 116, cx + 152, cy - 98)
    result.bezierTo(cx + 40, cy + 134, cx + 168, cy + 52, cx + 110, cy + 154)
    result.bezierTo(cx - 168, cy - 18, cx - 28, cy + 146, cx - 160, cy + 94)
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

func strokeOffsetCount(pts: [..] Vector2, offset: f32)->u64
{
    var path = buildClosedPath(pts)
    path.flatten(.Normal)

    var outline = path.polygon.getOffset(offset, Pixel.JoinStyle.Round)
    @assert(outline.count() > 0)

    foreach generated in outline.paths
    {
        @assert(generated.isPolyOnly)
        @assert(generated.isClosed)
        @assert(generated.startPoint.distanceToSquared(generated.endPoint) < 0.01)
        @assert(generated.polygon.points.count >= 4)
    }

    var pen = Pixel.Pen.createSolid(Argb.MediumPurple, 6)
    pen.begCapStyle = .None
    pen.endCapStyle = .None
    pen.joinStyle   = .Round

    var painter: Pixel.Painter
    painter.begin()
    painter.setAntialiased(true)
    painter.drawPath(&outline, pen, .Merge)
    let n = painter.vertexBuffer.count
    painter.end()
    return n
}

func strokeCleanCount(pts: [..] Vector2)->u64
{
    var path = buildClosedPath(pts)
    path.flatten(.Normal)

    var clean = path.polygon.getClean()
    @assert(clean.count() > 0)

    foreach generated in clean.paths
    {
        @assert(generated.isPolyOnly)
        @assert(generated.isClosed)
        @assert(generated.startPoint.distanceToSquared(generated.endPoint) < 0.01)
        @assert(generated.polygon.points.count >= 4)
    }

    var pen = Pixel.Pen.createSolid(Argb.SteelBlue, 4)
    pen.begCapStyle = .None
    pen.endCapStyle = .None
    pen.joinStyle   = .Round

    var painter: Pixel.Painter
    painter.begin()
    painter.setAntialiased(true)
    painter.drawPath(&clean, pen, .Merge)
    let n = painter.vertexBuffer.count
    painter.end()
    return n
}

func strokeOffsetBlobCount(iterations: s32)->u64
{
    var total = 0'u64

    for _ in iterations
    {
        var path = buildBlobPath()
        path.flatten(.Normal)

        var outline = path.polygon.getOffset(3.0, Pixel.JoinStyle.Round)
        @assert(outline.count() > 0)
        foreach generated in outline.paths do
            @assert(generated.isClosed)

        var pen = Pixel.Pen.createSolid(Argb.MediumPurple, 6)
        pen.begCapStyle = .None
        pen.endCapStyle = .None
        pen.joinStyle   = .Round

        var painter: Pixel.Painter
        painter.begin()
        painter.setAntialiased(true)
        painter.fillPath(&path, Color.fromArgb(42, Argb.MediumPurple))
        painter.drawPath(&outline, pen, .Merge)
        total += painter.vertexBuffer.count
        painter.end()
    }

    return total
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

// Paths generated from polygon offset/clean are closed contours and must be
// drawable again without crashing.
#test
{
    let star = makeStar(160, 160, 70, 28, 5)
    @assert(strokeOffsetCount(star[to], 8) > 0)
}

#test
{
    var concave = [
        Vector2{0, 0}, Vector2{110, 0}, Vector2{110, 26},
        Vector2{46, 26}, Vector2{46, 92}, Vector2{140, 92},
        Vector2{140, 126}, Vector2{0, 126},
    ]

    @assert(strokeCleanCount(concave) > 0)
}

#test
{
    @assert(strokeOffsetBlobCount(256) > 0)
}
