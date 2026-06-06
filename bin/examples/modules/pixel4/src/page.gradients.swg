using Core, Pixel

func makeSunsetGradient(rect: Math.Rectangle)->Brush
{
    var brush = Brush.createLinearGradient(rect.x, rect.y, rect.right(), rect.bottom(), Color.fromArgb(Argb.DeepSkyBlue), Color.fromArgb(Argb.MediumPurple))
    brush.addGradientStop(0.42, Argb.Goldenrod)
    brush.addGradientStop(0.72, Argb.Tomato)
    return brush
}

func drawSpreadSample(painter: *Pixel.Painter, rect: Math.Rectangle, title: string, spread: GradientSpread)
{
    let axisEnd = rect.x + rect.width * 0.28
    let brush   = Brush.createLinearGradient(rect.x, rect.y, axisEnd, rect.y, Argb.DeepSkyBlue, Argb.Tomato, spread)
    painter.fillRoundRect(rect, 12, 12, brush)
    painter.drawRoundRect(rect, 12, 12, Color.fromArgb(80, Argb.MidnightBlue), 1)
    painter.drawString(rect.x + 12, rect.vertCenter() - 8, title, g_HelpFont, Argb.White)
}

func drawGradientFillCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Gradient fills", "Linear and radial gradients are ordinary brushes, so every filled primitive can use them.")
    let left = Math.Rectangle{body.x + 12, body.y + 18, body.width * 0.52, body.height - 36}
    let right = Math.Rectangle{left.right() + 34, body.y + 18, body.width - left.width - 58, body.height - 36}

    let linear = makeSunsetGradient(left)
    painter.fillRoundRect(left, 28, 28, linear)
    painter.drawRoundRect(left, 28, 28, Color.fromArgb(100, Argb.MidnightBlue), 2)

    let center = Math.Vector2{right.horzCenter(), right.vertCenter() - 2}
    let radial = Brush.createRadialGradient(center, Math.min(right.width, right.height) * 0.48, Argb.White, Argb.DarkMagenta)
    painter.fillCircle(center.x, center.y, Math.min(right.width, right.height) * 0.46, radial)
    painter.drawCircle(center.x, center.y, Math.min(right.width, right.height) * 0.46, Color.fromArgb(96, Argb.Indigo), 2)
}

func drawGradientStrokeCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Gradient strokes", "The same brush can drive pens for paths, round rectangles and polygon outlines.")

    var path = makeBlobPath(insetRect(body, 16, 18, body.width * 0.55, 24))
    var pen = Pen.createSolid(Argb.White, 22)
    pen.brush = Brush.createLinearGradient(body.x, body.y, body.right(), body.bottom(), Argb.DeepSkyBlue, Argb.Crimson)
    pen.brush.addGradientStop(0.5, Argb.Goldenrod)
    pen.joinStyle = .Round
    painter.drawPath(&path, pen)

    let star = makeStarPolygon(body.x + body.width * 0.73, body.vertCenter() + 2, 72, 32, 7)
    var starPen = Pen.createSolid(Argb.White, 16)
    starPen.brush = Brush.createRadialGradient(body.x + body.width * 0.73, body.vertCenter() + 2, 82, Argb.White, Argb.SeaGreen)
    starPen.joinStyle = .Round
    drawClosedOutline(painter, star[to], starPen)
}

func drawGradientSpreadCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Spread modes", "Clamp, repeat and mirror define what happens outside the first gradient interval.")
    let gap = 14.0
    let h = (body.height - 2 * gap) / 3
    drawSpreadSample(painter, {body.x + 18, body.y + 10, body.width - 36, h}, "Clamp", .Clamp)
    drawSpreadSample(painter, {body.x + 18, body.y + 10 + h + gap, body.width - 36, h}, "Repeat", .Repeat)
    drawSpreadSample(painter, {body.x + 18, body.y + 10 + (h + gap) * 2, body.width - 36, h}, "Mirror", .Mirror)
}

func drawGradientTextCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Gradient text", "drawString uses the same paint binding as shapes, including MSDF glyphs.")
    let text = "GRADIENT"
    let size = Painter.measureString(text, g_TitleFont)
    let x = body.horzCenter() - size.width * 0.5
    let y = body.vertCenter() - g_TitleFont.height * 0.5

    let brush = Brush.createLinearGradient(x, y, x + size.width, y + size.height, Argb.DeepSkyBlue, Argb.Crimson)
    painter.drawString(x, y, text, g_TitleFont, brush)
    painter.drawString(body.x + 22, body.bottom() - 28, "Brush.createLinearGradient + drawString", g_HelpFont, Argb.DimGray)
}

func drawGradientsPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel gradient paints", "Page 6 : linear, radial, repeating and mirrored gradient brushes across fills, strokes and text.")

    drawGradientFillCard(painter, {28, 104, 452, 268})
    drawGradientStrokeCard(painter, {500, 104, 452, 268})
    drawGradientSpreadCard(painter, {28, 398, 452, 266})
    drawGradientTextCard(painter, {500, 398, 452, 266})
}
