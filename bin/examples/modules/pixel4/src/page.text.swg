using Core, Pixel

func drawTextCardSurface(painter: *Pixel.Painter, rect: Math.Rectangle, color: Color)
{
    painter.fillRoundRect(rect, 16, 16, color)
    painter.drawRoundRect(rect, 16, 16, Color.fromArgb(34, Argb.SlateGray), 1)
}

func drawTextFlowCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body      = drawPanel(painter, rect, "Word wrap and alignment", "Word wrap, centering and palette changes stay inside the same painter pass.")
    let columnGap = 18.0
    let leftWidth = (body.width - columnGap) * 0.5
    let leftRect  = Math.Rectangle{body.x, body.y, leftWidth, body.height}
    let rightRect = Math.Rectangle{leftRect.right() + columnGap, body.y, body.width - leftWidth - columnGap, body.height}

    drawTextCardSurface(painter, leftRect, Color.fromArgb(255, 247, 249, 251))
    drawTextCardSurface(painter, rightRect, Color.fromArgb(255, 245, 248, 252))

    var leftText: RichString = "drawRichString word-wraps copy inside a fixed card without leaving the rest of the painter layout."
    var leftFmt: RichStringFormat
    leftFmt.flags        = .WordWrap | .Clip
    leftFmt.lineGap      = 1
    leftFmt.font.regular = g_LabelFont
    leftFmt.palette[0]   = Argb.DarkSlateGray
    painter.drawRichString(insetRect(leftRect, 16, 16, 16, 16), &leftText, leftFmt)

    var rightText: RichString = "<u>Centered labels</u>\npreserve line breaks\nand <p1>highlight</p> key words."
    var rightFmt: RichStringFormat
    rightFmt.flags         = .WordWrap | .Clip
    rightFmt.horzAlignment = .Center
    rightFmt.vertAlignment = .Center
    rightFmt.lineGap       = 0
    rightFmt.font.regular  = g_HelpFont
    rightFmt.palette[0]    = Argb.MidnightBlue
    rightFmt.palette[1]    = Argb.Crimson
    painter.drawRichString(insetRect(rightRect, 18, 16, 18, 16), &rightText, rightFmt)
}

func drawTexturedStringCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body        = drawPanel(painter, rect, "Measured and textured strings", "Measured bounds stay visible while drawString switches to texture-backed brushes.")
    let sampleRect  = insetRect(body, 18, 12, 18, 12)
    let titleText   = "PIXEL"
    let titleSize   = Painter.measureString(titleText, g_TitleFont)
    let titleX      = sampleRect.horzCenter() - titleSize.width * 0.5
    let titleY      = sampleRect.y + 22
    let boundsY     = titleY + g_TitleFont.height - titleSize.height
    let brushText   = "Brush.createTexture"
    let brushSize   = Painter.measureString(brushText, g_LabelFont)
    let brushX      = sampleRect.horzCenter() - brushSize.width * 0.5
    let brushY      = boundsY + titleSize.height + 16

    drawTextCardSurface(painter, sampleRect, Color.fromArgb(255, 246, 248, 250))
    painter.fillRect(titleX, boundsY, titleSize.width, titleSize.height, Color.fromArgb(24, Argb.DeepSkyBlue))
    painter.fillRect(titleX, boundsY, titleSize.width, titleSize.ascent, Color.fromArgb(28, Argb.Tomato))
    painter.drawString(titleX, titleY, titleText, g_TitleFont, Brush.createTexture(g_FillTexture), UnderlineStyle.Underline)
    painter.drawString(brushX, brushY, brushText, g_LabelFont, Brush.createTiled(g_TileTexture))
    drawWrappedText(painter, {sampleRect.x + 16, sampleRect.bottom() - 30, sampleRect.width - 32, 18}, "Blue = bounds, red = ascent.", g_HelpFont, Argb.DimGray)
}

func drawOutlineTextCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body        = drawPanel(painter, rect, "Typeface outlines", "Outline paths can be filled and stroked like the rest of the vector showcase.")
    let previewRect = insetRect(body, 18, 14, 18, 42)
    let outlineSize = Painter.measureString("PIXEL", g_OutlineFont)
    let outlineX    = previewRect.horzCenter() - outlineSize.width * 0.5
    let outlineTop  = previewRect.y + (previewRect.height - outlineSize.height) * 0.5
    let outlineY    = outlineTop + g_OutlineFont.ascent

    drawTextCardSurface(painter, previewRect, Color.fromArgb(255, 246, 248, 250))

    painter.pushClippingSurfaceRect(previewRect)
    painter.pushTransform()
    painter.translateTransform(outlineX, outlineY)
    painter.fillPath(&g_OutlineText, Brush.createTiled(g_TileTexture))

    var pen = Pen.createSolid(Argb.White, 6)
    pen.brush     = Brush.createTexture(g_FillTexture)
    pen.joinStyle = .Round
    painter.drawPath(&g_OutlineText, pen, .Merge)

    painter.popTransform()
    painter.popClippingRect()
    drawWrappedText(painter, {body.x + 18, body.bottom() - 34, body.width - 36, 24}, "TypeFace.getStringOutline + fillPath + drawPath", g_HelpFont, Argb.DimGray)
}

func drawTextPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel text rendering", "Page 7 : wrapped strings, textured glyphs and vector outlines without switching away from painter primitives.")
    drawTextFlowCard(painter, {28, 104, 452, 280})
    drawTexturedStringCard(painter, {500, 104, 452, 280})
    drawOutlineTextCard(painter, {28, 406, 924, 258})
}
