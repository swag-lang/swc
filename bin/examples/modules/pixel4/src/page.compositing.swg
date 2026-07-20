using Core, Pixel

func drawClipRectCard(painter: #nonull *Pixel.Painter, rect: Math.Rectangle)
{
    let body     = drawPanel(painter, rect, "Clipping rect", "pushClippingRect constrains a sample to the preview card while still using normal painter calls.")
    let clipRect = insetRect(body, 26, 20, 26, 26)

    painter.fillRoundRect(clipRect, 18, 18, Color.fromArgb(255, 246, 248, 250))
    painter.pushClippingRect(clipRect)
    painter.fillCircle(clipRect.horzCenter() - 38, clipRect.vertCenter(), 82, Brush.createTexture(g_FillTexture))
    painter.fillCircle(clipRect.horzCenter() + 46, clipRect.vertCenter() - 10, 78, Brush.createTiled(g_TileTexture))
    painter.popClippingRect()

    var border = Pen.createSolid(Argb.MidnightBlue, 4)
    border.borderPos = .Inside
    painter.drawRoundRect(clipRect, 18, 18, border)
}

func drawClipRegionCard(painter: #nonull *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Clipping region", "A region can be carved with a second pass to create holes before the actual color fill happens.")
    let maskRect = insetRect(body, 34, 22, 34, 26)

    painter.startClippingRegion(.Set)
    painter.fillRoundRect(maskRect, 28, 28, Argb.White)
    painter.setClippingRegionMode(.Clear)
    painter.fillCircle(maskRect.horzCenter(), maskRect.vertCenter(), 44, Argb.White)
    painter.endClippingRegion()
    painter.fillRoundRect(maskRect, 28, 28, Brush.createTexture(g_FillTexture))
    painter.resetClippingRegion()

    painter.drawRoundRect(maskRect, 28, 28, Color.fromArgb(70, Argb.MidnightBlue), 2)
    painter.drawCircle(maskRect.horzCenter(), maskRect.vertCenter(), 44, Color.fromArgb(90, Argb.Crimson), 2)
}

func drawBlendSample(painter: #nonull *Pixel.Painter, rect: Math.Rectangle, mode: BlendingMode, label: #nonull string)
{
    painter.fillRoundRect(rect, 14, 14, Color.fromArgb(255, 245, 247, 250))
    painter.drawRoundRect(rect, 14, 14, Color.fromArgb(34, Argb.SlateGray), 1)
    painter.drawString(rect.x + 14, rect.y + 10, label, assume g_HelpFont, Argb.DarkSlateGray)

    painter.setBlendingMode(mode)
    painter.fillRoundRect(rect.x + 24, rect.y + 42, 78, 78, 18, 18, Color.fromArgb(150, Argb.RoyalBlue))
    painter.fillRoundRect(rect.x + 72, rect.y + 64, 78, 78, 18, 18, Color.fromArgb(150, Argb.Tomato))
    painter.fillCircle(rect.x + 112, rect.y + 88, 36, Color.fromArgb(150, Argb.Goldenrod))
    painter.setBlendingMode(.Alpha)
}

func drawBlendCard(painter: #nonull *Pixel.Painter, rect: Math.Rectangle)
{
    let body      = drawPanel(painter, rect, "Blending modes", "Add and Max stay visible side by side so the page still tests alternate compositing paths.")
    let sampleGap = 18.0
    let sampleW   = (body.width - sampleGap) * 0.5

    drawBlendSample(painter, {body.x, body.y + 18, sampleW, body.height - 18}, .Add, "Add")
    drawBlendSample(painter, {body.x + sampleW + sampleGap, body.y + 18, sampleW, body.height - 18}, .Max, "Max")
}

func buildPathModeList(x, y: f32)->LinePathList
{
    var list: retval

    {
        let path = list.newPath()
        path.start(x + 52, y + 10)
        path.lineTo(x + 52, y + 114)
    }

    {
        let path = list.newPath()
        path.start(x + 0, y + 62)
        path.lineTo(x + 104, y + 62)
    }

    return list
}

func drawPathModeCard(painter: #nonull *Pixel.Painter, rect: Math.Rectangle)
{
    let body    = drawPanel(painter, rect, "Path-list modes", "Separate and Merge behave differently once thick strokes overlap, so both remain in the replacement showcase.")
    let leftBox = Math.Rectangle{body.x + 20, body.y + 20, body.width * 0.5 - 30, body.height - 40}
    let rightBox = Math.Rectangle{leftBox.right() + 20, body.y + 20, body.width - leftBox.width - 40, body.height - 40}
    var listL   = buildPathModeList(leftBox.x + 58, leftBox.y + 28)
    var listR   = buildPathModeList(rightBox.x + 58, rightBox.y + 28)

    painter.fillRoundRect(leftBox, 16, 16, Color.fromArgb(255, 247, 249, 251))
    painter.fillRoundRect(rightBox, 16, 16, Color.fromArgb(255, 247, 249, 251))
    painter.drawString(leftBox.x + 14, leftBox.y + 12, "Separate", assume g_HelpFont, Argb.DarkSlateGray)
    painter.drawString(rightBox.x + 14, rightBox.y + 12, "Merge + textured pen", assume g_HelpFont, Argb.DarkSlateGray)

    var penL = Pen.createSolid(Color.fromArgb(146, Argb.SeaGreen), 28)
    penL.joinStyle = .Round
    painter.drawPath(&listL, penL, .Separate)

    var penR = Pen.createSolid(Color.fromArgb(146, Argb.SeaGreen), 28)
    penR.brush     = Brush.createTexture(g_FillTexture)
    penR.joinStyle = .Round
    painter.drawPath(&listR, penR, .Merge)
}

func drawCompositingPage(painter: #nonull *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel compositing", "Page 8 : clipping rectangles, clipping regions, alternate blending modes and path-list composition.")
    drawClipRectCard(painter, {28, 104, 294, 262})
    drawClipRegionCard(painter, {343, 104, 294, 262})
    drawBlendCard(painter, {658, 104, 294, 262})
    drawPathModeCard(painter, {28, 392, 924, 272})
}
