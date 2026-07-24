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
    painter.drawString(rect.x + 12, rect.vertCenter() - 8, title, notnull g_HelpFont, Argb.White)
}

func drawGradientFillCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Gradient fills", "Linear, radial and sweep gradients are ordinary brushes, so every filled primitive can use them.")
    let gap = 16.0
    let itemW = (body.width - gap * 2) / 3
    let itemH = body.height - 36
    let left = Math.Rectangle{body.x, body.y + 18, itemW, itemH}
    let mid = Math.Rectangle{left.right() + gap, body.y + 18, itemW, itemH}
    let right = Math.Rectangle{mid.right() + gap, body.y + 18, itemW, itemH}

    let linear = makeSunsetGradient(left)
    painter.fillRoundRect(left, 24, 24, linear)
    painter.drawRoundRect(left, 24, 24, Color.fromArgb(100, Argb.MidnightBlue), 2)

    let radialCenter = Math.Vector2{mid.horzCenter(), mid.vertCenter() - 2}
    let radialRadius = Math.min(mid.width, mid.height) * 0.48
    let radial = Brush.createRadialGradient(radialCenter, radialRadius, Argb.White, Argb.DarkMagenta)
    painter.fillCircle(radialCenter.x, radialCenter.y, radialRadius * 0.96, radial)
    painter.drawCircle(radialCenter.x, radialCenter.y, radialRadius * 0.96, Color.fromArgb(96, Argb.Indigo), 2)

    let sweepCenter = Math.Vector2{right.horzCenter(), right.vertCenter() - 2}
    let sweepRadius = Math.min(right.width, right.height) * 0.46
    var sweep = Brush.createSweepGradient(sweepCenter, 0.0'deg, 360.0'deg, Argb.DeepSkyBlue, Argb.Crimson, .Repeat)
    sweep.addGradientStop(0.33, Argb.Goldenrod)
    sweep.addGradientStop(0.66, Argb.SeaGreen)
    painter.fillCircle(sweepCenter.x, sweepCenter.y, sweepRadius, sweep)
    painter.drawCircle(sweepCenter.x, sweepCenter.y, sweepRadius, Color.fromArgb(96, Argb.MidnightBlue), 2)
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
    starPen.brush     = Brush.createRadialGradient(body.x + body.width * 0.73, body.vertCenter() + 2, 82, Argb.White, Argb.SeaGreen)
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
    let body = drawPanel(painter, rect, "Gradient text", "drawString and translucent overlays use the same paint binding as shapes.")
    let text = "GRADIENT"
    let size = Painter.measureString(text, notnull g_TitleFont)
    let x = body.horzCenter() - size.width * 0.5
    let y = body.vertCenter() - (notnull g_TitleFont).height * 0.5

    let back = Math.Rectangle{body.x + 26, body.y + 18, body.width - 52, body.height - 42}
    var backBrush = Brush.createLinearGradient(back.x, back.y, back.right(), back.bottom(), Argb.DeepSkyBlue, Argb.Goldenrod)
    backBrush.setOpacityf(0.32)
    painter.fillRoundRect(back, 22, 22, backBrush)

    let glowCenter = Math.Vector2{body.horzCenter(), body.vertCenter()}
    var glowBrush = Brush.createSweepGradient(glowCenter, Argb.White, Argb.Crimson, .Repeat)
    glowBrush.multiplyOpacity(0.42)
    painter.fillCircle(glowCenter.x, glowCenter.y, Math.min(body.width, body.height) * 0.42, glowBrush)

    var brush = Brush.createSweepGradient(Math.Vector2{x + size.width * 0.5, y + size.height * 0.5}, 0.0'deg, 360.0'deg, Argb.DeepSkyBlue, Argb.Crimson, .Repeat)
    brush.addGradientStop(0.45, Argb.Goldenrod)
    brush.multiplyTint(Color.fromArgb(235'u8, Argb.White))
    painter.drawString(x, y, text, notnull g_TitleFont, brush)
    painter.drawString(body.x + 22, body.bottom() - 28, "setOpacityf + multiplyTint + drawString", notnull g_HelpFont, Argb.DimGray)
}

func drawGradientsPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel gradient paints", "Page 6 : linear, radial, sweep, opacity-tinted, repeating and mirrored gradient brushes across fills, strokes and text.")

    drawGradientFillCard(painter, {28, 104, 452, 268})
    drawGradientStrokeCard(painter, {500, 104, 452, 268})
    drawGradientSpreadCard(painter, {28, 398, 452, 266})
    drawGradientTextCard(painter, {500, 398, 452, 266})
}
