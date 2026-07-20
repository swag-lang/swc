using Core, Pixel

func drawBlobSurface(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    var blob = makeBlobPath(rect)
    blob.flatten(.Normal)
    painter.fillPath(&blob, Color.fromArgb(42, Argb.MediumPurple))

    let outlineOffset = blob.polygon.isClockwise ? 3.0 : -3.0
    var outline = blob.polygon.getOffset(outlineOffset, JoinStyle.Round)

    var pen = Pen.createSolid(Color.fromArgb(136, Argb.MediumPurple), 6)
    pen.begCapStyle = .None
    pen.endCapStyle = .None
    pen.joinStyle   = .Round
    painter.drawPath(&outline, pen, .Merge)
}

func drawAlphaRow(painter: *Pixel.Painter, rect: Math.Rectangle, alpha: u8, label: string)
{
    painter.drawString(rect.x, rect.y + 10, label, assume g_LabelFont, Argb.DarkSlateGray)

    let pathRect = insetRect(rect, 150, 6, 16, 8)
    painter.drawLine(pathRect.x, pathRect.vertCenter(), pathRect.right(), pathRect.vertCenter(), Color.fromArgb(24, Argb.Black), 1)

    var path = makeTransparencyPath(pathRect, 0)
    var pen  = Pen.createSolid(Color.fromArgb(alpha, Argb.DeepSkyBlue), 20)
    pen.begCapStyle = .RoundAnchor
    pen.endCapStyle = .ArrowAnchor
    pen.joinStyle   = .Round
    painter.drawPath(&path, pen)
}

func drawTransparencyPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel path drawing", "Page 3 : color stacking and alpha blending on a filled surface plus overlapping strokes.")

    let sceneBody = drawPanel(painter, {28, 102, 924, 404}, "Transparency and layering", "A translucent surface sits behind overlapping paths, with a border that stays outside the fill.")
    painter.fillRoundRect(sceneBody.x, sceneBody.y, sceneBody.width, sceneBody.height, 14, 14, Color.fromArgb(255, 248, 250, 252))
    painter.pushClippingSurfaceRect(sceneBody)

    drawBlobSurface(painter, sceneBody)

    {
        var path = makeTransparencyPath(sceneBody, 0)
        var pen  = Pen.createSolid(Color.fromArgb(122, Argb.Tomato), 34)
        pen.begCapStyle = .Round
        pen.endCapStyle = .Round
        pen.joinStyle   = .Round
        painter.drawPath(&path, pen)
    }

    {
        var path = makeTransparencyPath(sceneBody, 1)
        var pen  = Pen.createSolid(Color.fromArgb(126, Argb.SeaGreen), 28)
        pen.begCapStyle  = .Square
        pen.endCapStyle  = .SquareAnchor
        pen.joinStyle    = .Bevel
        pen.capEndScaleX = 2.5
        pen.capEndScaleY = 2.4
        painter.drawPath(&path, pen)
    }

    {
        var path = makeTransparencyPath(sceneBody, 2)
        var pen  = Pen.createSolid(Color.fromArgb(120, Argb.DeepSkyBlue), 24)
        pen.begCapStyle  = .ArrowAnchor2
        pen.endCapStyle  = .RoundAnchor
        pen.joinStyle    = .MiterBevel
        pen.capBegScaleX = 2.6
        pen.capBegScaleY = 2.3
        pen.capEndScaleX = 2.4
        pen.capEndScaleY = 2.2
        painter.drawPath(&path, pen)
    }

    painter.popClippingRect()

    let alphaBody = drawPanel(painter, {28, 530, 924, 154}, "Opacity samples", "Same path, same geometry, different alpha values.")
    let alphaRowHeight = alphaBody.height / 3.0
    drawAlphaRow(painter, {alphaBody.x, alphaBody.y + 0 * alphaRowHeight, alphaBody.width, alphaRowHeight}, 64, "25% alpha")
    drawAlphaRow(painter, {alphaBody.x, alphaBody.y + 1 * alphaRowHeight, alphaBody.width, alphaRowHeight}, 128, "50% alpha")
    drawAlphaRow(painter, {alphaBody.x, alphaBody.y + 2 * alphaRowHeight, alphaBody.width, alphaRowHeight}, 216, "85% alpha")
}
