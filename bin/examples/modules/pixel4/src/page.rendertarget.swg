using Core, Pixel

func drawRenderTargetContent(painter: #nonull *Pixel.Painter, width, height: s32)
{
    painter.clear(Color.fromArgb(255, 243, 246, 250))

    let backRect = Math.Rectangle{18, 18, cast(f32) width - 36, cast(f32) height - 36}
    painter.fillRoundRect(backRect, 26, 26, Brush.createTexture(g_FillTexture))

    var ringPen = Pen.createSolid(Argb.White, 18)
    ringPen.brush     = Brush.createTiled(g_TileTexture)
    ringPen.joinStyle = .Round
    painter.drawCircle(backRect.x + 90, backRect.y + 92, 54, ringPen)
    painter.fillCircle(backRect.x + 90, backRect.y + 92, 24, Color.fromArgb(210, Argb.MidnightBlue))

    painter.fillRoundRect(backRect.right() - 150, backRect.y + 26, 110, 74, 18, 18, Color.fromArgb(180, Argb.DeepSkyBlue))
    painter.fillRoundRect(backRect.right() - 120, backRect.y + 54, 110, 74, 18, 18, Color.fromArgb(160, Argb.Tomato))
    painter.drawString(backRect.x + 164, backRect.y + 92, "RT", assume g_TitleFont, Argb.MidnightBlue)

    var star = makeStarPolygon(backRect.right() - 106, backRect.bottom() - 70, 48, 20, 5)
    painter.fillPolygon(star[to], Brush.createTiled(g_TileTexture))
    drawClosedOutline(painter, star[to], Pen.createSolid(Argb.White, 6))
}

func drawRenderTargetPreviewCard(painter: #nonull *Pixel.Painter, rect: Math.Rectangle, texture: Texture)
{
    let body      = drawPanel(painter, rect, "Offscreen texture reuse", "The render target is drawn once, then sampled back as a normal texture at different scales.")
    let sampleGap = 18.0
    let sampleW   = (body.width - 2 * sampleGap) / 3.0
    let leftRect  = Math.Rectangle{body.x, body.y, sampleW, body.height}
    let midRect   = Math.Rectangle{leftRect.right() + sampleGap, body.y, sampleW, body.height}
    let rightRect = Math.Rectangle{midRect.right() + sampleGap, body.y, sampleW, body.height}

    painter.fillRoundRect(leftRect, 16, 16, Color.fromArgb(255, 247, 249, 251))
    painter.fillRoundRect(midRect, 16, 16, Color.fromArgb(255, 247, 249, 251))
    painter.fillRoundRect(rightRect, 16, 16, Color.fromArgb(255, 247, 249, 251))

    painter.drawString(leftRect.x + 14, leftRect.y + 12, "Raw target", assume g_HelpFont, Argb.DarkSlateGray)
    painter.drawTexture(insetRect(leftRect, 14, 34, 14, 14), texture)

    let midDst = insetRect(midRect, 18, 38, 18, 18)
    painter.drawString(midRect.x + 14, midRect.y + 12, "Rotated drawTexture", assume g_HelpFont, Argb.DarkSlateGray)
    painter.pushTransform()
    painter.rotateTransform(8.0'deg, midDst.horzCenter(), midDst.vertCenter())
    painter.drawTexture(midDst, texture)
    painter.popTransform()

    let srcRect = Math.Rectangle{cast(f32) texture.width * 0.50, cast(f32) texture.height * 0.10, cast(f32) texture.width * 0.36, cast(f32) texture.height * 0.52}
    painter.drawString(rightRect.x + 14, rightRect.y + 12, "Source-rect zoom", assume g_HelpFont, Argb.DarkSlateGray)
    painter.drawTexture(insetRect(rightRect, 14, 34, 14, 14), srcRect, texture)
}

func drawRenderTargetBrushCard(painter: #nonull *Pixel.Painter, rect: Math.Rectangle, texture: Texture)
{
    let body = drawPanel(painter, rect, "Render target as a brush", "Once the offscreen pass is complete, its color buffer can feed regular brush and pen paths in the main scene.")

    {
        let leftRect = Math.Rectangle{body.x + 18, body.y + 18, body.width * 0.44, body.height - 36}
        let fillBrush = Brush.createTexture(texture)
        var pen       = Pen.createSolid(Argb.White, 12)
        pen.brush     = Brush.createTiled(g_TileTexture)
        pen.joinStyle = .Round

        painter.fillRoundRect(leftRect, 22, 22, fillBrush)
        painter.drawRoundRect(leftRect, 22, 22, pen)
        drawWrappedText(painter, {leftRect.x + 16, leftRect.bottom() - 36, leftRect.width - 32, 28}, "Brush.createTexture(target.colorBuffer)", assume g_HelpFont, Argb.White)
    }

    {
        let rightRect = Math.Rectangle{body.x + body.width * 0.52, body.y + 18, body.width * 0.42, body.height - 36}
        let center    = Math.Vector2{rightRect.horzCenter(), rightRect.vertCenter() - 6}
        let flower    = makeStarPolygon(center.x, center.y, 72, 30, 6)
        var pen       = Pen.createSolid(Argb.White, 10)
        pen.brush     = Brush.createTexture(texture)
        pen.joinStyle = .Round

        painter.fillPolygon(flower[to], Brush.createTiled(g_TileTexture))
        drawClosedOutline(painter, flower[to], pen)
        drawWrappedText(painter, {rightRect.x + 10, rightRect.bottom() - 36, rightRect.width - 20, 28}, "Textured outline from the same target", assume g_HelpFont, Argb.DarkSlateGray)
    }
}

func drawRenderTargetPage(painter: #nonull *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel render targets", "Page 9 : offscreen drawing, texture reuse, source-rect sampling and brush reuse from a live render target.")

    let tgt = g_Renderer.getRenderTarget(360, 220)
    defer g_Renderer.releaseRenderTarget(tgt)

    painter.bindRenderTarget(tgt, true)
    drawRenderTargetContent(painter, tgt.colorBuffer.width, tgt.colorBuffer.height)
    painter.unbindRenderTarget()

    drawRenderTargetPreviewCard(painter, {28, 104, 924, 304}, tgt.colorBuffer)
    drawRenderTargetBrushCard(painter, {28, 432, 924, 232}, tgt.colorBuffer)
}
