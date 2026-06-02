using Core, Pixel

func drawTextFlowCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body      = drawPanel(painter, rect, "Word wrap and alignment", "Rich strings wrap, align and colorize text without leaving the painter.")
    let columnGap = 18.0
    let leftWidth = (body.width - columnGap) * 0.5
    let leftRect  = Math.Rectangle{body.x, body.y, leftWidth, body.height}
    let rightRect = Math.Rectangle{leftRect.right() + columnGap, body.y, body.width - leftWidth - columnGap, body.height}

    painter.fillRoundRect(leftRect, 16, 16, Color.fromArgb(255, 247, 249, 251))
    painter.fillRoundRect(rightRect, 16, 16, Color.fromArgb(255, 245, 248, 252))
    painter.drawRoundRect(leftRect, 16, 16, Color.fromArgb(34, Argb.SlateGray), 1)
    painter.drawRoundRect(rightRect, 16, 16, Color.fromArgb(34, Argb.SlateGray), 1)

    var leftText: RichString = "drawRichString can word-wrap a paragraph inside a rounded panel while keeping the same layout helpers used by the rest of the showcase."
    var leftFmt: RichStringFormat
    leftFmt.flags        = .WordWrap
    leftFmt.lineGap      = 1
    leftFmt.font.regular = g_LabelFont
    leftFmt.palette[0]   = Argb.DarkSlateGray
    painter.drawRichString(insetRect(leftRect, 16, 16, 16, 16), &leftText, leftFmt)

    var rightText: RichString = "<u>Rich strings</u> can center labels, preserve line breaks, and <p1>highlight key words</p> while staying in the same paint pass.\n\nThat keeps UI copy and technical annotations close to the sample they describe."
    var rightFmt: RichStringFormat
    rightFmt.flags         = .WordWrap
    rightFmt.horzAlignment = .Center
    rightFmt.vertAlignment = .Center
    rightFmt.lineGap       = 1
    rightFmt.font.regular  = g_LabelFont
    rightFmt.palette[0]    = Argb.MidnightBlue
    rightFmt.palette[1]    = Argb.Crimson
    painter.drawRichString(insetRect(rightRect, 18, 16, 18, 16), &rightText, rightFmt)
}

func drawTexturedStringCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body       = drawPanel(painter, rect, "Measured and textured strings", "The sample keeps the glyph bounds visible while the text itself uses image-backed brushes.")
    let sampleRect = insetRect(body, 16, 16, 16, 16)
    let text       = "PIXEL"
    let measure    = Painter.measureString(text, g_TitleFont)
    let textX      = sampleRect.x + 18
    let textY      = sampleRect.y + 74
    let boundsY    = textY + g_TitleFont.height - measure.height

    painter.fillRoundRect(sampleRect, 16, 16, Color.fromArgb(255, 246, 248, 250))
    painter.fillRect(textX, boundsY, measure.width, measure.height, Color.fromArgb(24, Argb.DeepSkyBlue))
    painter.fillRect(textX, boundsY, measure.width, measure.ascent, Color.fromArgb(28, Argb.Tomato))

    painter.drawString(textX, textY, text, g_TitleFont, Brush.createTexture(g_FillTexture), UnderlineStyle.Underline)
    painter.drawString(textX, textY + 58, "Brush.createTexture", g_SubTitleFont, Brush.createTiled(g_TileTexture), UnderlineStyle.Strikeout)
    painter.drawString(textX, sampleRect.bottom() - 38, "Blue = measured bounds, red = ascent, patterned glyphs = texture-backed drawString.", g_HelpFont, Argb.DimGray)
}

func drawOutlineTextCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Typeface outlines", "Vector outlines can be filled and stroked like any other path, which keeps text in the same geometry pipeline.")
    let trs  = painter.getTransform()

    painter.pushClippingSurfaceRect(body)
    painter.translateTransform(body.x + 34, body.y + 142)
    painter.fillPath(&g_OutlineText, Brush.createTiled(g_TileTexture))

    var pen = Pen.createSolid(Argb.White, 6)
    pen.brush     = Brush.createTexture(g_FillTexture)
    pen.joinStyle = .Round
    painter.drawPath(&g_OutlineText, pen, .Merge)

    painter.setTransform(trs)
    painter.popClippingRect()
    painter.drawString(body.x + 18, body.bottom() - 32, "TypeFace.getStringOutline + fillPath + drawPath", g_HelpFont, Argb.DimGray)
}

func drawTextPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel text rendering", "Page 6 : wrapped strings, textured glyphs and vector outlines without switching away from painter primitives.")
    drawTextFlowCard(painter, {28, 104, 452, 262})
    drawTexturedStringCard(painter, {500, 104, 452, 262})
    drawOutlineTextCard(painter, {28, 392, 924, 272})
}
