using Core, Pixel

func drawClipRectCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter,
                         rect,
                         "Clipping rect",
                         "pushClippingRect constrains a sample to the preview card while still using normal painter calls.")
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

func drawClipRegionCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter,
                         rect,
                         "Clipping region",
                         "A region can be carved with a second pass to create holes before the actual color fill happens.")
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

func drawPathModeCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter,
                         rect,
                         "Path-list modes",
                         "The same translucent stroke is drawn separately on each path or merged before blending.")
    const Gap = 16.0
    let width = (body.width - Gap) * 0.5
    let cards = [Math.Rectangle{body.x, body.y + 8, width, body.height - 8},
                 Math.Rectangle{body.x + width + Gap, body.y + 8, width, body.height - 8}]

    let labels   = ["Separate", "Merge"]
    with var pen = Pen.createSolid(Color.fromArgb(146, Argb.SeaGreen), 24)
    {
        .begCapStyle = .Round
        .endCapStyle = .Round
    }

    for card, index in cards
    {
        painter.fillRoundRect(card, 10, 10, Color.fromArgb(255, 247, 249, 251))
        painter.drawString(card.x + 16, card.y + 12, labels[index], g_HelpFont, Argb.DarkSlateGray)

        let cx       = card.horzCenter()
        let cy       = card.vertCenter() + 10
        var paths: LinePathList
        let vertical = paths.newPath()
        vertical.start(cx, cy - 36)
        vertical.lineTo(cx, cy + 36)
        let horizontal = paths.newPath()
        horizontal.start(cx - 36, cy)
        horizontal.lineTo(cx + 36, cy)

        let mode = index == 0 ? DrawPathListMode.Separate : DrawPathListMode.Merge
        painter.drawPath(&paths, pen, mode)
    }
}

func drawCompositingPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter,
                   "Pixel clipping and composition",
                   "Rectangular and stencil clipping, followed by separate and merged path-list rendering.")
    drawClipRectCard(painter, {28, 104, 452, 262})
    drawClipRegionCard(painter, {500, 104, 452, 262})
    drawPathModeCard(painter, {28, 392, 924, 272})
}
