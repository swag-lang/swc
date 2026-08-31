#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Command-stream goldens for curve flattening. A curve turns into segments before it reaches the
// command stream, so the vertex count in these goldens is the flattening result itself: it moves
// as soon as the tolerance, the segment-count formula or the quality mapping changes.
// See [[Testing.assertGolden]].

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var path:    LinePath

    path.start(10, 80)
    path.bezierTo(90, 80, 50, 10)
    path.close()

    painter.begin()
    painter.fillPath(&path, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "curve.bezier.quadratic")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var path:    LinePath

    path.start(10, 80)
    path.bezierTo(90, 80, 25, 10, 75, 10)
    path.close()

    painter.begin()
    painter.fillPath(&path, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "curve.bezier.cubic")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var path:    LinePath

    path.start(10, 50)
    path.arcTo(50, 50, 40, 40, 180.0'deg, 180.0'deg)

    painter.begin()
    painter.drawPath(&path, Pen.createSolid(Color.fromArgb(Argb.Red), 2))
    painter.end()
    Testing.assertGolden(&painter, "curve.arc.half")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    painter.begin()
    painter.drawArc(50, 50, 40, 0.0'deg, 90.0'deg, Color.fromArgb(Argb.Red), 2)
    painter.end()
    Testing.assertGolden(&painter, "curve.arc.quarter")
}

// The three quality levels must produce three different segment counts for the same circle. A
// change that collapses two of them would go unnoticed without these three goldens side by side.
#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    painter.begin()
    painter.setQuality(.Draft)
    painter.fillCircle(50, 50, 40, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "curve.circle.draft")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    painter.begin()
    painter.setQuality(.Normal)
    painter.fillCircle(50, 50, 40, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "curve.circle.normal")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    painter.begin()
    painter.setQuality(.High)
    painter.fillCircle(50, 50, 40, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "curve.circle.high")
}

// A larger radius needs more segments for the same tolerance, so flattening must be radius
// dependent and not a fixed segment count.
#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    painter.begin()
    painter.fillCircle(200, 200, 190, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "curve.circle.large")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    painter.begin()
    painter.drawLine(10, 10, 90, 60, Color.fromArgb(Argb.Red), 3)
    painter.end()
    Testing.assertGolden(&painter, "curve.line")
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    painter.begin()
    painter.drawBezier(10, 80, 90, 80, 50, 10, Pen.createSolid(Color.fromArgb(Argb.Red), 3))
    painter.end()
    Testing.assertGolden(&painter, "curve.bezier.stroked")
}
