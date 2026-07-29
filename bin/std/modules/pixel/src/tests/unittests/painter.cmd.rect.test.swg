#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Command-stream goldens for the rectangle primitives, including the batching guarantees the
// GUI relies on. See [[Testing.assertGolden]].

// An axis-aligned rectangle under a pure translation takes the fast path: two triangles, no
// antialiasing fringe. Losing that path shows up here as a larger vertex count and 'cov=aa'.
#test
{
    var painter: Painter
    painter.begin()
    painter.fillRect(10, 20, 100, 50, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "rect.fill.solid")
}

// The same rectangle under a rotation cannot be pixel snapped, so it goes through path
// tessellation and gains an antialiasing fringe.
#test
{
    var painter: Painter
    painter.begin()
    painter.rotateTransform(30.0'deg)
    painter.fillRect(10, 20, 100, 50, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "rect.fill.rotated")
}

// Non-integer coordinates are rounded before emission.
#test
{
    var painter: Painter
    painter.begin()
    painter.fillRect(10.4, 20.6, 100.5, 50.5, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "rect.fill.subpixel")
}

// A fully transparent brush must emit nothing at all.
#test
{
    var painter: Painter
    painter.begin()
    painter.fillRect(10, 20, 100, 50, Color.fromArgb(0'u8, 255'u8, 0'u8, 0'u8))
    painter.end()
    Testing.assertGolden(&painter, "rect.fill.transparent.noop")
}

// A degenerate rectangle must emit nothing at all.
#test
{
    var painter: Painter
    painter.begin()
    painter.fillRect(10, 20, 0, 50, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "rect.fill.empty.noop")
}

// Batching: consecutive solid fills share a single DrawTriangles command. This is the property
// that keeps widget backgrounds cheap, and the vertex count in the golden is what detects a
// regression that splits the batch.
#test
{
    var painter: Painter
    painter.begin()
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.fillRect(20, 0, 10, 10, Color.fromArgb(Argb.Green))
    painter.fillRect(40, 0, 10, 10, Color.fromArgb(Argb.Blue))
    painter.end()
    Testing.assertGolden(&painter, "rect.fill.batched")
}

// A clipping change between two fills must break the batch.
#test
{
    var painter: Painter
    painter.begin()
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.setClippingRect(0, 0, 5, 5)
    painter.fillRect(20, 0, 10, 10, Color.fromArgb(Argb.Green))
    painter.end()
    Testing.assertGolden(&painter, "rect.fill.batchbreak")
}

#test
{
    var painter: Painter
    painter.begin()
    painter.drawRect(10, 20, 100, 50, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "rect.draw.solid")
}

// A thick border drawn inside the rectangle shifts the stroke path by half the pen size.
#test
{
    var painter: Painter
    var pen = Pen.createSolid(Color.fromArgb(Argb.Red), 4)
    pen.borderPos = .Inside

    painter.begin()
    painter.drawRect(10, 20, 100, 50, pen)
    painter.end()
    Testing.assertGolden(&painter, "rect.draw.inside")
}

#test
{
    var painter: Painter
    painter.begin()
    painter.fillRoundRect(10, 20, 100, 50, 8, 8, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "rect.fillround")
}

#test
{
    var painter: Painter
    painter.begin()
    painter.drawRoundRect(10, 20, 100, 50, 8, 8, Color.fromArgb(Argb.Red), 2)
    painter.end()
    Testing.assertGolden(&painter, "rect.drawround")
}

// Draft quality flattens curves with fewer segments than Normal, so the two goldens must differ
// in vertex count.
#test
{
    var painter: Painter
    painter.begin()
    painter.setQuality(.Draft)
    painter.fillRoundRect(10, 20, 100, 50, 8, 8, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "rect.fillround.draft")
}

#test
{
    var painter: Painter
    painter.begin()
    painter.setAntialiased(false)
    painter.fillRoundRect(10, 20, 100, 50, 8, 8, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "rect.fillround.noaa")
}
