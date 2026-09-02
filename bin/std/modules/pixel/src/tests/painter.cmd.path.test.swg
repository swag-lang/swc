#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Command-stream goldens for paths, strokes and render targets. See [[Testing.assertGolden]].

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var path:    LinePath

    path.start(10, 10)
    path.lineTo(90, 10)
    path.lineTo(50, 80)
    path.close()

    painter.begin()
    painter.fillPath(&path, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "path.fill.triangle")
}

// A convex polygon can skip the general tessellator; the vertex count in the golden is what
// tells the two paths apart.
#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var path:    LinePath

    path.start(10, 10)
    path.lineTo(90, 10)
    path.lineTo(50, 80)
    path.close()

    painter.begin()
    painter.fillPolygon(&path, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "path.fillpolygon.triangle")
}

// A self-intersecting outline in a list must be normalized before reaching Poly2Tri.
#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var list:    LinePathList
    let path = list.newPath()

    path.start(10, 10)
    path.lineTo(90, 90)
    path.lineTo(90, 10)
    path.lineTo(10, 90)
    path.close()

    painter.begin()
    painter.fillPath(&list, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "path.fill.selfintersect")
}

// An outer contour plus an inner one: the inner contour must be punched out, not filled.
#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var list:    LinePathList

    let outer = list.newPath()
    outer.setRect(0, 0, 100, 100)
    let inner = list.newPath()
    inner.setRect(30, 30, 40, 40)

    painter.begin()
    painter.fillPath(&list, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "path.fill.hole")
}

// Several holes in this real PDF glyph-like outline meet at exact vertices. Each contour is
// simple by itself, but Poly2Tri also requires contours to be mutually disjoint.
#[Swag.TestTag("golden")]
#test
{
    func addContour(list: *LinePathList, points: const [..] Math.Vector2)
    {
        let path = list.newPath()
        path.start(points[0].x, points[0].y)
        for point, index in points where index do
            path.lineTo(point.x, point.y)
        path.close()
    }

    var painter: Painter
    var list:    LinePathList
    addContour(&list, [{115.8, 226}, {118.5, 232.7}, {119, 233.8}, {117.9, 233.2}, {115.5, 231.7}, {112.9, 233.2}, {111.9, 233.8}, {112.3, 232.7}, {115.1, 226}, {115.5, 225.1}])
    addContour(&list, [{117.8, 233}, {118.2, 232.8}, {118.4, 232.5}, {117.3, 231.9}])
    addContour(&list, [{115.5, 227.2}, {113.6, 231.8}, {115.2, 230.9}, {115.5, 230.8}, {115.6, 230.9}, {117.3, 231.9}])
    addContour(&list, [{115.1, 226.3}, {115.5, 227.2}, {115.8, 226.3}, {115.5, 226.2}])
    addContour(&list, [{115.2, 231.6}, {115.5, 231.7}, {115.6, 231.6}, {115.5, 231.3}])
    addContour(&list, [{112.5, 232.5}, {112.7, 232.8}, {113.1, 233}, {113.6, 231.8}])

    painter.begin()
    painter.fillPath(&list, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "path.fill.touching-holes")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    painter.begin()
    painter.fillCircle(50, 50, 40, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "path.fill.circle")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    painter.begin()
    painter.fillEllipse(50, 50, 40, 20, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "path.fill.ellipse")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    painter.begin()
    painter.drawCircle(50, 50, 40, Color.fromArgb(Argb.Red), 3)
    painter.end()
    Testing.assertGolden(&painter, "path.draw.circle")
}

// Join style changes the geometry emitted at every corner, and nothing else.
#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var path:    LinePath
    var pen = Pen.createSolid(Color.fromArgb(Argb.Red), 6)
    pen.joinStyle = .Miter

    path.start(10, 80)
    path.lineTo(50, 10)
    path.lineTo(90, 80)

    painter.begin()
    painter.drawPath(&path, pen)
    painter.end()
    Testing.assertGolden(&painter, "path.stroke.join.miter")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var path:    LinePath
    var pen = Pen.createSolid(Color.fromArgb(Argb.Red), 6)
    pen.joinStyle = .Round

    path.start(10, 80)
    path.lineTo(50, 10)
    path.lineTo(90, 80)

    painter.begin()
    painter.drawPath(&path, pen)
    painter.end()
    Testing.assertGolden(&painter, "path.stroke.join.round")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var path:    LinePath
    var pen = Pen.createSolid(Color.fromArgb(Argb.Red), 6)
    pen.joinStyle = .Bevel

    path.start(10, 80)
    path.lineTo(50, 10)
    path.lineTo(90, 80)

    painter.begin()
    painter.drawPath(&path, pen)
    painter.end()
    Testing.assertGolden(&painter, "path.stroke.join.bevel")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var path:    LinePath
    var pen = Pen.createSolid(Color.fromArgb(Argb.Red), 6)
    pen.begCapStyle = .Square
    pen.endCapStyle = .Triangle

    path.start(10, 50)
    path.lineTo(90, 50)

    painter.begin()
    painter.drawPath(&path, pen)
    painter.end()
    Testing.assertGolden(&painter, "path.stroke.caps")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var path:    LinePath
    var pen = Pen.createSolid(Color.fromArgb(Argb.Red), 2)
    pen.dashStyle = .Dash

    path.start(10, 50)
    path.lineTo(90, 50)

    painter.begin()
    painter.drawPath(&path, pen)
    painter.end()
    Testing.assertGolden(&painter, "path.stroke.dash")
}

// Binding a render target resets the paint state and pushes it; unbinding restores it. The
// golden pins that symmetry, which a stack bug would break.
#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var target:  RenderTarget

    target.attach(cast(RenderTargetHandle) 1, cast(TextureHandle) 11, .BGRA8, 128, 64)

    painter.begin()
    painter.setBlendingMode(.Add)
    painter.bindRenderTarget(&target)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.unbindRenderTarget()
    painter.releaseRenderTarget(&target)
    painter.end()
    Testing.assertGolden(&painter, "target.bind.unbind")
}

// Returns the total darkness a horizontal stroke of `size` lays over a white ground.
private func strokeDarkness(size: f32, contentScale = 1.0'f32)->u64
{
    const Side = 64's32

    var path: LinePath
    path.start(8, 32)
    path.lineTo(56, 32)

    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.setContentScale(contentScale)
    painter.clear(Color.fromArgb(Argb.White))
    painter.drawPath(&path, Color.fromArgb(Argb.Black), size)
    painter.end()

    var renderer: RenderCpu
    renderer.begin(cast(s32) (cast(f32) Side * contentScale), cast(s32) (cast(f32) Side * contentScale))
    let render: IRenderer = &renderer
    render.draw(&painter)
    render.end()

    let image  = renderer.surfaceImage()
    var result = 0'u64
    for y in image.height
    {
        for x in image.width do
            result += cast(u64) (255 - image.pixelColor(x, y).r)
    }

    return result
}

// A stroke thinner than one device pixel is drawn one pixel wide with the width it lost moved
// into its opacity, instead of being dropped: a vector drawing shown small is mostly such
// strokes, and losing them reads as missing geometry rather than as a light line.
#test
{
    let full = strokeDarkness(1)
    Swag.assert(full > 0)

    // Half a pixel is half the ink of a whole one, and a quarter is a quarter of it.
    let half    = strokeDarkness(0.5)
    let quarter = strokeDarkness(0.25)
    Swag.assert(half > 0 and quarter > 0)
    Swag.assert(Math.abs(cast(f32) half - cast(f32) quarter * 2) < cast(f32) quarter * 0.2)

    // The measure is device pixels, so a hairline on a display that scales up is a whole pixel
    // and keeps its full weight.
    let scaledUp = strokeDarkness(0.5, 2)
    Swag.assert(cast(f32) scaledUp > cast(f32) half * 3)

    // A pen with no width at all still draws nothing.
    Swag.assert(strokeDarkness(0) == 0)
}
