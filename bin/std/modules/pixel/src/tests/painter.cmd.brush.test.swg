#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Command-stream goldens for the brush parameters carried by BindTexture0. A brush never
// changes the geometry, only the uniforms the renderer will bind, so these goldens are exactly
// the contract between the painter and the shaders. See [[Testing.assertGolden]].

// A texture handle is an opaque runtime value; the dump remaps it to 'tex#0' so the golden does
// not depend on allocation order.
private func makeTestTexture(handle: u64, w, h: s32)->Texture
{
    var result: retval
    result.attach(cast(TextureHandle) handle, .BGRA8, w, h)
    return result
}

// A solid brush must NOT emit a BindTexture0: it resets texture0 instead, which is what lets
// solid fills batch together.
#test
{
    var painter: Painter
    painter.begin()
    painter.fillRect(0, 0, 100, 100, Brush.createSolid(Color.fromArgb(Argb.Red)))
    painter.end()
    Testing.assertGolden(&painter, "brush.solid")
}

#test
{
    var painter: Painter
    let brush = Brush.createLinearGradient(0, 0, 100, 0, Color.fromArgb(Argb.Red), Color.fromArgb(Argb.Blue))

    painter.begin()
    painter.fillRect(0, 0, 100, 100, brush)
    painter.end()
    Testing.assertGolden(&painter, "brush.gradient.linear")
}

#test
{
    var painter: Painter
    let brush = Brush.createLinearGradient(0, 0, 100, 0, Color.fromArgb(Argb.Red), Color.fromArgb(Argb.Blue), .Mirror)

    painter.begin()
    painter.fillRect(0, 0, 100, 100, brush)
    painter.end()
    Testing.assertGolden(&painter, "brush.gradient.linear.mirror")
}

// Stops are kept sorted by offset whatever the insertion order, so the golden pins both the
// count and the ordering.
#test
{
    var painter: Painter
    var brush = Brush.createLinearGradient(0, 0, 100, 0, Color.fromArgb(Argb.Red), Color.fromArgb(Argb.Blue))
    brush.addGradientStop(0.75, Color.fromArgb(Argb.Green))
    brush.addGradientStop(0.25, Color.fromArgb(Argb.Yellow))

    painter.begin()
    painter.fillRect(0, 0, 100, 100, brush)
    painter.end()
    Testing.assertGolden(&painter, "brush.gradient.stops")
}

#test
{
    var painter: Painter
    let brush = Brush.createRadialGradient(50, 50, 40, Color.fromArgb(Argb.Red), Color.fromArgb(Argb.Blue))

    painter.begin()
    painter.fillRect(0, 0, 100, 100, brush)
    painter.end()
    Testing.assertGolden(&painter, "brush.gradient.radial")
}

#test
{
    var painter: Painter
    let brush = Brush.createSweepGradient(Math.Vector2{50, 50}, Color.fromArgb(Argb.Red), Color.fromArgb(Argb.Blue))

    painter.begin()
    painter.fillRect(0, 0, 100, 100, brush)
    painter.end()
    Testing.assertGolden(&painter, "brush.gradient.sweep")
}

// A hatch brush always samples with Pixel interpolation, whatever the painter state says.
#test
{
    var painter: Painter
    let brush = Brush.createHatch(.DiagonalCross, Color.fromArgb(Argb.Red))

    painter.begin()
    painter.setInterpolationMode(.Linear)
    painter.fillRect(0, 0, 100, 100, brush)
    painter.end()
    Testing.assertGolden(&painter, "brush.hatch")
}

#test
{
    var painter: Painter
    let texture = makeTestTexture(7, 64, 32)

    painter.begin()
    painter.drawTexture(10, 10, 64, 32, texture)
    painter.end()
    Testing.assertGolden(&painter, "brush.texture.fill")
}

// A sub-rectangle brush computes normalized texture coordinates inset by half a texel.
#test
{
    var painter: Painter
    let texture = makeTestTexture(7, 64, 32)

    painter.begin()
    painter.drawTexture(10, 10, 32, 16, Math.Rectangle{16, 8, 32, 16}, texture)
    painter.end()
    Testing.assertGolden(&painter, "brush.texture.subrect")
}

#test
{
    var painter: Painter
    let texture = makeTestTexture(7, 64, 32)
    let brush   = Brush.createTiled(texture)

    painter.begin()
    painter.setInterpolationMode(.Linear)
    painter.fillRect(0, 0, 200, 100, brush)
    painter.end()
    Testing.assertGolden(&painter, "brush.texture.tiled")
}

// Two different textures get two different indices, in first-use order.
#test
{
    var painter: Painter
    let first  = makeTestTexture(7, 64, 32)
    let second = makeTestTexture(9, 16, 16)

    painter.begin()
    painter.drawTexture(0, 0, 64, 32, first)
    painter.drawTexture(0, 40, 16, 16, second)
    painter.drawTexture(0, 60, 64, 32, first)
    painter.end()
    Testing.assertGolden(&painter, "brush.texture.remap")
}
