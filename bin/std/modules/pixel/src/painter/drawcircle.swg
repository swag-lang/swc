#global public

using Core

impl Painter
{
    // Strokes a circular arc from `startAngle` to `endAngle`.
    //
    // Angles run clockwise from the top of the circle, and `endAngle` must be greater than
    // `startAngle`. The center and radius are snapped to the pixel grid.
    mtd drawArc(centerX, centerY: f32, radius: f32, startAngle, endAngle: Math.Angle, color: Color, penSize: f32 = 1)
    {
        if radius == 0 or .isInvisible(color) do
            return
        if Math.isZeroEpsilon(endAngle.radians - startAngle.radians) do
            return
        Swag.assert(endAngle.radians > startAngle.radians)

        let pen = Pen.createSolid(color, penSize)
        .sharedLinePath.setArc(centerX, centerY, radius, startAngle, endAngle)
        .drawPath(&.sharedLinePath, pen)
    }

    mtd drawArc(centerX, centerY: f32, radius: f32, startAngle, endAngle: Math.Angle, pen: Pen)
    {
        if radius == 0 or .isInvisible(pen.brush) do
            return
        if Math.isZeroEpsilon(endAngle.radians - startAngle.radians) do
            return
        Swag.assert(endAngle.radians > startAngle.radians)
        .sharedLinePath.setArc(centerX, centerY, radius, startAngle, endAngle)
        .drawPath(&.sharedLinePath, pen)
    }

    // Strokes the outline of a circle.
    mtd drawCircle(centerX, centerY: f32, radius: f32, color: Color, penSize: f32 = 1)
    {
        if radius == 0 or .isInvisible(color) do
            return

        let pen = Pen.createSolid(color, penSize)
        .drawCircle(centerX, centerY, radius, pen)
    }

    mtd drawCircle(centerX, centerY: f32, radius: f32, pen: Pen)
    {
        .drawEllipse(centerX, centerY, radius, radius, pen)
    }

    // Fills a circle.
    //
    // The center is snapped to whole pixels and the radius to half pixels.
    mtd fillCircle(centerX, centerY: f32, radius: f32, brush: Brush)
    {
        if radius == 0 or .isInvisible(brush) do
            return
        .sharedLinePath.setCircle(centerX, centerY, radius)
        .fillPath(&.sharedLinePath, brush)
    }

    mtd fillCircle(centerX, centerY: f32, radius: f32, color: Color)
    {
        if radius == 0 or .isInvisible(color) do
            return
        .fillCircle(centerX, centerY, radius, Brush.createSolid(color))
    }

    // Strokes the outline of an axis-aligned ellipse.
    //
    // With [[Pixel.BorderPos.Inside]], the stroke stays inside the radii.
    mtd drawEllipse(centerX, centerY: f32, radiusX, radiusY: f32, color: Color, penSize: f32 = 1)
    {
        if radiusX == 0 or radiusY == 0 or .isInvisible(color) or penSize == 0 do
            return

        let pen = Pen.createSolid(color, penSize)
        .drawEllipse(centerX, centerY, radiusX, radiusY, pen)
    }

    mtd drawEllipse(centerX, centerY: f32, radiusX, radiusY: f32, pen: Pen)
    {
        if radiusX == 0 or radiusY == 0 or .isInvisible(pen.brush) do
            return

        var rX = radiusX
        var rY = radiusY

        switch #complete pen.borderPos
        {
        case .None:
            break

        case .Inside:
            rX -= pen.size * 0.5
            rY -= pen.size * 0.5
        }

        .sharedLinePath.setEllipseRaw(centerX, centerY, rX, rY)
        .drawPath(&.sharedLinePath, pen)
    }

    mtd drawEllipse(rect: Math.Rectangle, color: Color, penSize: f32 = 1)
    {
        .drawEllipse(rect.horzCenter(), rect.vertCenter(), rect.width * 0.5, rect.height * 0.5, color, penSize)
    }

    mtd drawEllipse(rect: Math.Rectangle, pen: Pen)
    {
        .drawEllipse(rect.horzCenter(), rect.vertCenter(), rect.width * 0.5, rect.height * 0.5, pen)
    }

    // Fills an axis-aligned ellipse.
    //
    // The geometry is not snapped, so the fill covers exactly the outline drawn by
    // [[Pixel.Painter.drawEllipse]] with the same arguments.
    mtd fillEllipse(centerX, centerY: f32, radiusX, radiusY: f32, brush: Brush)
    {
        if radiusX == 0 or radiusY == 0 or .isInvisible(brush) do
            return
        .sharedLinePath.setEllipseRaw(centerX, centerY, radiusX, radiusY)
        .fillPath(&.sharedLinePath, brush)
    }

    mtd fillEllipse(centerX, centerY: f32, radiusX, radiusY: f32, color: Color)
    {
        if radiusX == 0 or radiusY == 0 or .isInvisible(color) do
            return
        .fillEllipse(centerX, centerY, radiusX, radiusY, Brush.createSolid(color))
    }

    mtd fillEllipse(rect: Math.Rectangle, brush: Brush)
    {
        .fillEllipse(rect.horzCenter(), rect.vertCenter(), rect.width * 0.5, rect.height * 0.5, brush)
    }

    mtd fillEllipse(rect: Math.Rectangle, color: Color)
    {
        .fillEllipse(rect.horzCenter(), rect.vertCenter(), rect.width * 0.5, rect.height * 0.5, color)
    }
}
