#global public

using Core

impl Painter
{
    // Draw a line
    mtd drawLine(start, end: Math.Vector2, pen: Pen)
    {
        .drawLine(start.x, start.y, end.x, end.y, pen)
    }

    mtd drawLine(startX, startY, endX, endY: f32, color: Color, penSize: f32 = 1)
    {
        if (startX == endX and startY == endY) or .isInvisible(color) or penSize == 0 do
            return

        let pen = Pen.createSolid(color, penSize)
        .drawLine(startX, startY, endX, endY, pen)
    }

    mtd drawLine(startX, startY, endX, endY: f32, pen: Pen)
    {
        if (startX == endX and startY == endY) or .isInvisible(pen.brush) or pen.size == 0 do
            return
        .sharedLinePath.start(startX, startY)
        .sharedLinePath.lineTo(endX, endY)
        .drawPath(&.sharedLinePath, pen)
    }

    // Strokes a quadratic Bézier segment from the start point to the end point.
    //
    // `ptX` and `ptY` define the control point in path-space pixels. A zero-width
    // or fully transparent pen produces no geometry.
    mtd drawBezier(startX, startY, endX, endY: f32, ptX, ptY: f32, pen: Pen)
    {
        if (startX == endX and startY == endY) or .isInvisible(pen.brush) or pen.size == 0 do
            return
        .sharedLinePath.start(startX, startY)
        .sharedLinePath.bezierTo(endX, endY, ptX, ptY)
        .drawPath(&.sharedLinePath, pen)
    }
}
