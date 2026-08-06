#global public

using Core

impl Painter
{
    // Draw an arc between two angles
    mtd drawArc(centerX, centerY: f32, radius: f32, startAngle, endAngle: Math.Angle, color: Color, penSize: f32 = 1)
    {
        if radius == 0 or .isInvisible(color) do
            return
        if Math.isZeroEpsilon(endAngle.radians - startAngle.radians) do
            return
        Debug.assert(endAngle.radians > startAngle.radians)

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
        .sharedLinePath.setArc(centerX, centerY, radius, startAngle, endAngle)
        .drawPath(&.sharedLinePath, pen)
    }

    // Draw an empty circle
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

    // Draw a solid circle
    mtd fillCircle(centerX, centerY: f32, radius: f32, brush: Brush)
    {
        if radius == 0 or .isInvisible(brush) do
            return
        .sharedLinePath.setEllipse(centerX, centerY, radius, radius)
        .fillPath(&.sharedLinePath, brush)
    }

    mtd fillCircle(centerX, centerY: f32, radius: f32, color: Color)
    {
        if radius == 0 or .isInvisible(color) do
            return

        let brush = Brush.createSolid(color)
        .sharedLinePath.setEllipse(centerX, centerY, radius, radius)
        .fillPath(&.sharedLinePath, brush)
    }

    // Draw an empty ellipse
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

    // Draw a solid ellipse
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

        let brush = Brush.createSolid(color)
        .sharedLinePath.setEllipse(centerX, centerY, radiusX, radiusY)
        .fillPath(&.sharedLinePath, brush)
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
