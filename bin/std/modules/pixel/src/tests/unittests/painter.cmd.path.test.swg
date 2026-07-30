#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Command-stream goldens for paths, strokes and render targets. See [[Testing.assertGolden]].

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

// A self-intersecting outline exercises the tessellator's crossing handling.
#test
{
    var painter: Painter
    var path:    LinePath

    path.start(10, 10)
    path.lineTo(90, 90)
    path.lineTo(90, 10)
    path.lineTo(10, 90)
    path.close()

    painter.begin()
    painter.fillPath(&path, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "path.fill.selfintersect")
}

// An outer contour plus an inner one: the inner contour must be punched out, not filled.
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

#test
{
    var painter: Painter
    painter.begin()
    painter.fillCircle(50, 50, 40, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "path.fill.circle")
}

#test
{
    var painter: Painter
    painter.begin()
    painter.fillEllipse(50, 50, 40, 20, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "path.fill.ellipse")
}

#test
{
    var painter: Painter
    painter.begin()
    painter.drawCircle(50, 50, 40, Color.fromArgb(Argb.Red), 3)
    painter.end()
    Testing.assertGolden(&painter, "path.draw.circle")
}

// Join style changes the geometry emitted at every corner, and nothing else.
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
#test
{
    var painter: Painter
    var target:  RenderTarget

    target.colorBuffer.handle = cast(TextureHandle) 11
    target.colorBuffer.pf     = .BGRA8
    target.colorBuffer.width  = 128
    target.colorBuffer.height = 64
    target.colorBuffer.valid  = true

    painter.begin()
    painter.setBlendingMode(.Add)
    painter.bindRenderTarget(&target)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.unbindRenderTarget()
    painter.releaseRenderTarget(&target)
    painter.end()
    Testing.assertGolden(&painter, "target.bind.unbind")
}
