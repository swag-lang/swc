using Core, Pixel

func drawTextCardSurface(painter: *Pixel.Painter, rect: Math.Rectangle, color: Color)
{
    painter.fillRoundRect(rect, 14, 14, color)
    painter.drawRoundRect(rect, 14, 14, Color.fromArgb(34, Argb.SlateGray), 1)
}

func drawTextFlowCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Rich layout", "Styled runs, tabs, URL spans, alignment and clipping are resolved through drawRichString.")
    let gap = 14.0
    let left = Math.Rectangle{body.x, body.y + 2, (body.width - gap) * 0.54, body.height - 4}
    let right = Math.Rectangle{left.right() + gap, body.y + 2, body.width - left.width - gap, body.height - 4}

    drawTextCardSurface(painter, left, Color.fromArgb(255, 247, 249, 251))
    drawTextCardSurface(painter, right, Color.fromArgb(255, 244, 247, 252))

    var story:    RichString = "<b>Text layout</b> keeps styled chunks on the same baseline, wraps by shaped run width, and gives <p1>justified</p> paragraphs predictable bounds.\nParagraph gaps, min line height and max-line clipping keep dense UI text stable."
    var storyFmt: RichStringFormat
    storyFmt.flags         = .WordWrap | .Clip
    storyFmt.horzAlignment = .Justify
    storyFmt.lineGap       = 3
    storyFmt.paragraphGap  = 5
    storyFmt.minLineHeight = 17
    storyFmt.maxLines      = 6
    storyFmt.font.regular  = g_HelpFont
    storyFmt.font.bold     = g_LabelFont
    storyFmt.palette[0]    = Argb.DarkSlateGray
    storyFmt.palette[1]    = Argb.Crimson
    painter.drawRichString(insetRect(left, 16, 14, 16, 14), &story, storyFmt)

    var labels:   RichString = "<u>Centered panel</u>\n<p1>palette run</p>\n<url><b>styled URL</b></url>\ntab\tstop"
    var labelFmt: RichStringFormat
    labelFmt.flags         = .WordWrap | .Clip
    labelFmt.horzAlignment = .Center
    labelFmt.vertAlignment = .Center
    labelFmt.lineGap       = 3
    labelFmt.font.regular  = g_HelpFont
    labelFmt.font.bold     = g_LabelFont
    labelFmt.palette[0]    = Argb.MidnightBlue
    labelFmt.palette[1]    = Argb.SeaGreen
    labelFmt.colorUrl      = Argb.DeepSkyBlue
    labelFmt.colorHotUrl   = Argb.Crimson
    labelFmt.tabSize       = 6
    labelFmt.letterSpacing = 0.4
    painter.drawRichString(insetRect(right, 12, 12, 12, 12), &labels, labelFmt)
}

func drawPaintedGlyphCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Painted glyphs", "Gradient, sweep and texture brushes bind to shaped text just like regular vector fills.")
    let sample = insetRect(body, 20, 12, 20, 18)
    drawTextCardSurface(painter, sample, Color.fromArgb(255, 246, 248, 250))

    let headline = "SHAPED"
    let headlineSize = Painter.measureString(headline, notnull g_TitleFont)
    let headlineX = sample.horzCenter() - headlineSize.width * 0.5
    let headlineY = sample.y + 24
    let headlineBoundsY = headlineY + (notnull g_TitleFont).height - headlineSize.height

    var headlineBrush = Brush.createLinearGradient(headlineX, headlineY, headlineX + headlineSize.width, headlineY + headlineSize.height, Argb.DeepSkyBlue, Argb.Crimson)
    headlineBrush.addGradientStop(0.48, Argb.Goldenrod)
    painter.fillRect(headlineX, headlineBoundsY, headlineSize.width, headlineSize.height, Color.fromArgb(22, Argb.DeepSkyBlue))
    painter.drawString(headlineX, headlineY, headline, notnull g_TitleFont, headlineBrush)

    let sweepText = "subpixel MSDF"
    let sweepSize = Painter.measureString(sweepText, notnull g_LabelFont)
    let sweepX = sample.horzCenter() - sweepSize.width * 0.5
    let sweepY = headlineY + (notnull g_TitleFont).height + 12
    var sweepBrush = Brush.createSweepGradient(Math.Vector2{sweepX + sweepSize.width * 0.5, sweepY + sweepSize.height * 0.5}, Argb.DeepSkyBlue, Argb.Crimson, .Repeat)
    sweepBrush.addGradientStop(0.4, Argb.SeaGreen)
    painter.drawString(sweepX, sweepY, sweepText, notnull g_LabelFont, sweepBrush)

    let textureText = "texture brush + underline"
    let textureSize = Painter.measureString(textureText, notnull g_HelpFont)
    let textureX = sample.horzCenter() - textureSize.width * 0.5
    let textureY = sample.bottom() - (notnull g_HelpFont).height - 12
    painter.drawString(textureX, textureY, textureText, notnull g_HelpFont, Brush.createTiled(g_TileTexture), UnderlineStyle.Underline)
}

func drawBaselineCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Metrics and baselines", "Mixed sizes share a baseline, with measured ink boxes shown against the font box.")
    let sample = insetRect(body, 20, 14, 20, 18)
    drawTextCardSurface(painter, sample, Color.fromArgb(255, 248, 249, 251))

    let baseline = sample.y + sample.height * 0.58
    painter.drawLine(sample.x + 16, baseline, sample.right() - 16, baseline, Color.fromArgb(140, Argb.Crimson), 1)

    let big = "Ag"
    let small = "aligned text"
    let bigMs = Painter.measureString(big, notnull g_TitleFont)
    let smallMs = Painter.measureString(small, notnull g_HelpFont)
    let bigX = sample.x + 34
    let bigTop = baseline - (notnull g_TitleFont).ascent
    let smallX = bigX + bigMs.width + 18
    let smallTop = baseline - (notnull g_HelpFont).ascent

    painter.fillRect(bigX, baseline - bigMs.ascent, bigMs.width, bigMs.height, Color.fromArgb(24, Argb.DeepSkyBlue))
    painter.fillRect(smallX, baseline - smallMs.ascent, smallMs.width, smallMs.height, Color.fromArgb(24, Argb.Goldenrod))
    painter.drawString(bigX, bigTop, big, notnull g_TitleFont, Argb.MidnightBlue)
    painter.drawString(smallX, smallTop, small, notnull g_HelpFont, Argb.DarkSlateGray)

    var paragraph: RichString = "<b>Large</b> and regular spans\nadvance by per-line height.\nThis third line is intentionally clipped."
    var fmt:       RichStringFormat
    fmt.flags         = .WordWrap | .Clip
    fmt.font.regular  = g_HelpFont
    fmt.font.bold     = g_LabelFont
    fmt.palette[0]    = Argb.DimGray
    fmt.lineGap       = 3
    fmt.minLineHeight = 18
    fmt.maxLines      = 2
    fmt.letterSpacing = 0.3
    painter.drawRichString({sample.x + 24, sample.bottom() - 64, sample.width - 48, 52}, &paragraph, fmt)
}

func drawOutlineTextCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Vector outlines", "Typeface outlines become paths, so fills, strokes, clipping and textured pens all still apply.")
    let preview = insetRect(body, 20, 14, 20, 40)
    let outlineSize = Painter.measureString("PIXEL", notnull g_OutlineFont)
    let outlineX = preview.horzCenter() - outlineSize.width * 0.5
    let outlineTop = preview.y + (preview.height - outlineSize.height) * 0.5
    let outlineY = outlineTop + (notnull g_OutlineFont).ascent

    drawTextCardSurface(painter, preview, Color.fromArgb(255, 246, 248, 250))

    painter.pushClippingSurfaceRect(preview)
    painter.pushTransform()
    painter.translateTransform(outlineX, outlineY)

    var fill = Brush.createLinearGradient(preview.x, preview.y, preview.right(), preview.bottom(), Argb.DeepSkyBlue, Argb.Goldenrod)
    fill.addGradientStop(0.56, Argb.Crimson)
    painter.fillPath(&g_OutlineText, fill)

    var pen = Pen.createSolid(Argb.White, 5)
    pen.brush     = Brush.createTexture(g_FillTexture)
    pen.joinStyle = .Round
    painter.drawPath(&g_OutlineText, pen, .Merge)

    painter.popTransform()
    painter.popClippingRect()
    drawWrappedText(painter, {body.x + 18, body.bottom() - 32, body.width - 36, 22}, "TypeFace.getStringOutline + gradient fill + textured outline", notnull g_HelpFont, Argb.DimGray)
}

func drawTextPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel text rendering", "Page 7 : shaped runs, rich layout, painted glyphs, baseline metrics and vector outlines in one painter pass.")
    drawTextFlowCard(painter, {28, 104, 452, 280})
    drawPaintedGlyphCard(painter, {500, 104, 452, 280})
    drawBaselineCard(painter, {28, 406, 452, 258})
    drawOutlineTextCard(painter, {500, 406, 452, 258})
}
