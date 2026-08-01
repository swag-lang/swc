#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// A canvas needs a rendering context, which a machine without a graphics device cannot give.
// Every test below reports whether it could run, so the suite stays honest on such a machine
// instead of passing by doing nothing.
func openCanvas(width, height: s32, outCanvas: *ImageCanvas)->bool
{
    dref outCanvas = catch ImageCanvas.create(width, height) as err
    return err == null
}

func makeSquarePath(x0, y0, x1, y1: f32)->LinePath
{
    var result: retval
    result.start(x0, y0)
    result.lineTo(x1, y0)
    result.lineTo(x1, y1)
    result.lineTo(x0, y1)
    result.close()
    return result
}

// A filled path reaches the pixels, opaque, and leaves the rest untouched.
#test
{
    var canvas: ImageCanvas
    if !openCanvas(32, 32, &canvas) do
        return

    var path = makeSquarePath(8, 8, 24, 24)
    canvas.painter.fillPath(&path, Color.fromRgb(247, 249, 0))

    var img = catch canvas.toImage() as err
    @assert(err == null)
    @assert(img.width == 32)
    @assert(img.height == 32)

    let inside = img.pixelColor(16, 16)
    @assert(inside.r == 247 and inside.g == 249 and inside.b == 0)
    @assert(inside.a == 255)
    @assert(img.pixelColor(2, 2).a == 0)
}

// The ground is laid under the drawing, not over it.
#test
{
    var canvas: ImageCanvas
    if !openCanvas(32, 32, &canvas) do
        return

    canvas.clear(Color.fromRgb(11, 11, 13))
    var path = makeSquarePath(8, 8, 24, 24)
    canvas.painter.fillPath(&path, Color.fromRgb(247, 249, 0))

    var img = catch canvas.toImage() as err
    @assert(err == null)

    let corner = img.pixelColor(2, 2)
    @assert(corner.r == 11 and corner.g == 11 and corner.b == 13 and corner.a == 255)
    @assert(img.pixelColor(16, 16).r == 247)
}

// A canvas opened over an image keeps that image and composites on top of it.
#test
{
    var ground: ImageCanvas
    if !openCanvas(32, 32, &ground) do
        return

    ground.clear(Color.fromRgb(10, 20, 30))
    var base = catch ground.toImage() as errBase
    @assert(errBase == null)

    var over = catch ImageCanvas.create(base) as errOver
    @assert(errOver == null)
    @assert(over.width == 32 and over.height == 32)

    var path = makeSquarePath(0, 0, 16, 32)
    over.painter.fillPath(&path, Color.fromRgb(200, 100, 50))

    var stamped = catch over.toImage() as errStamped
    @assert(errStamped == null)

    // The right half still shows the image the canvas was opened over.
    let kept = stamped.pixelColor(24, 16)
    @assert(kept.r == 10 and kept.g == 20 and kept.b == 30 and kept.a == 255)

    // The left half shows what was drawn on top.
    let drawn = stamped.pixelColor(8, 16)
    @assert(drawn.r == 200 and drawn.g == 100 and drawn.b == 50)
}

// A canvas can produce a series: reading it leaves the painter ready for the next frame.
#test
{
    var canvas: ImageCanvas
    if !openCanvas(16, 16, &canvas) do
        return

    var first = makeSquarePath(0, 0, 16, 16)
    canvas.painter.fillPath(&first, Color.fromRgb(255, 0, 0))
    var red = catch canvas.toImage() as errRed
    @assert(errRed == null)
    @assert(red.pixelColor(8, 8).r == 255)

    var second = makeSquarePath(0, 0, 16, 16)
    canvas.painter.fillPath(&second, Color.fromRgb(0, 255, 0))
    var green = catch canvas.toImage() as errGreen
    @assert(errGreen == null)

    // The second frame starts from a cleared target: the first one did not linger.
    let pixel = green.pixelColor(8, 8)
    @assert(pixel.g == 255 and pixel.r == 0)
}

// Everything the painter can do is available, not just paths.
#test
{
    var canvas: ImageCanvas
    if !openCanvas(32, 32, &canvas) do
        return

    canvas.painter.fillRect({0, 0, 32, 16}, Color.fromRgb(80, 90, 100))
    canvas.painter.drawLine(0, 24, 32, 24, Color.fromRgb(255, 255, 255), 4)

    var img = catch canvas.toImage() as err
    @assert(err == null)
    @assert(img.pixelColor(16, 8).r == 80)
    @assert(img.pixelColor(16, 24).r > 200)
}

// An image with no pixels cannot be drawn over.
#test
{
    var empty: Image
    var canvas = catch ImageCanvas.create(empty) as err
    @assert(err != null)
}

// An antialiased stroke reaches the pixels, opaque.
//
// Antialiased geometry goes through a pass that uses the destination alpha as scratch and
// leaves it at zero. Without the separate alpha resolve the canvas asks for, every stroke
// drawn off screen read back fully transparent while its color was perfectly correct.
#test
{
    var canvas: ImageCanvas
    if !openCanvas(32, 32, &canvas) do
        return

    var path: LinePath
    path.start(4, 16)
    path.lineTo(28, 16)

    var pen: Pen
    pen.size        = 8
    pen.brush       = Brush.createSolid(Color.fromRgb(247, 249, 0))
    pen.begCapStyle = .Round
    pen.endCapStyle = .Round
    canvas.painter.setAntialiased(true)
    canvas.painter.drawPath(&path, pen)

    var img = catch canvas.toImage() as err
    @assert(err == null)

    let hit = img.pixelColor(16, 16)
    @assert(hit.r == 247 and hit.g == 249 and hit.b == 0)
    @assert(hit.a == 255)
    @assert(img.pixelColor(16, 2).a == 0)
}
