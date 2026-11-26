#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    let full = strokeDarkness(1)
    Swag.require(full > 0)

    // Half a pixel is half the ink of a whole one, and a quarter is a quarter of it.
    let half    = strokeDarkness(0.5)
    let quarter = strokeDarkness(0.25)
    Swag.require(half > 0 and quarter > 0)
    Swag.require(Math.abs(cast(f32, half) - cast(f32, quarter) * 2) < cast(f32, quarter) * 0.2)

    // The measure is device pixels, so a hairline on a display that scales up is a whole pixel
    // and keeps its full weight.
    let scaledUp = strokeDarkness(0.5, 2)
    Swag.require(cast(f32, scaledUp) > cast(f32, half) * 3)

    // A pen with no width at all still draws nothing.
    Swag.require(strokeDarkness(0) == 0)
}

// A solid stroke can draw the flattened contour before fill metrics are computed.
#test
{
    var curve: LinePath
    curve.start(4, 10)
    curve.bezierTo(27, 10, 10, 1, 21, 1)

    var short: LinePath
    short.start(8, 23)
    short.lineTo(8.25, 23)
    let pen = Pen.createSolid(Color.fromArgb(Argb.White), 4)
    var images: [2] Image
    for pass in 2
    {
        var path = curve
        if pass do
            path.flatten()

        var painter: Painter
        painter.begin()
        painter.drawPath(&path, pen)
        painter.drawPath(&short, pen)
        painter.end()
        images[pass] = renderCpu(32, 28, &painter)
        Swag.require(path.hasPolygonMetrics == (pass != 0))
        Swag.require(path.flattenedPolygon().perimeter > 0)
    }

    Swag.require(images[0].pixelColor(6, 8).r != 0)
    Swag.require(images[0].pixelColor(8, 23).r == 0)
    for byte, index in images[0].pixels do
        Swag.require(byte == images[1].pixels[index])
}
