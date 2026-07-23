using Core, Pixel

// Center a string (with optional MSDF text effects) inside 'area', mirroring the
// baseline math of drawStringCenter.
func drawEffectSample(painter: *Pixel.Painter, area: Math.Rectangle, text: string, font: *Pixel.Font, color: Color, fx: TextEffect)
{
    let ms  = Painter.measureString(text, font)
    let top = area.vertCenter() - ms.height * 0.5 - (font.ascent - ms.ascent)
    let left = area.horzCenter() - ms.width * 0.5
    painter.drawString(left, top, text, font, color, fx)
}

func drawEffectSurface(painter: *Pixel.Painter, rect: Math.Rectangle, color: Color)
{
    painter.fillRoundRect(rect, 14, 14, color)
    painter.drawRoundRect(rect, 14, 14, Color.fromArgb(34, Argb.SlateGray), 1)
}

func drawOutlineEffectCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Outline", "A second distance threshold draws a crisp border under the glyph face. Its width scales with the text size.")
    let sample = insetRect(body, 20, 12, 20, 30)
    drawEffectSurface(painter, sample, Color.fromArgb(255, 246, 248, 250))

    var fx: TextEffect
    fx.outlineWidth = 0.26
    fx.outlineColor = Argb.MidnightBlue
    drawEffectSample(painter, sample, "Outline", notnull g_OutlineFont, Argb.White, fx)

    drawWrappedText(painter, {body.x + 18, body.bottom() - 24, body.width - 36, 22}, "outlineWidth 0.26, white face over a midnight-blue border", notnull g_HelpFont, Argb.DimGray)
}

func drawGlowEffectCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Glow / neon", "A soft halo derived from the distance to the edge, composited under the face. A thin outline keeps the core sharp.")
    let sample = insetRect(body, 20, 12, 20, 30)
    drawEffectSurface(painter, sample, Color.fromArgb(255, 16, 18, 30))

    var fx: TextEffect
    fx.glowColor    = Color.fromArgb(255, 64, 224, 255)
    fx.glowOffset   = 0.05
    fx.glowOuter    = 0.55
    fx.glowPower    = 1.4
    fx.outlineWidth = 0.06
    fx.outlineColor = Color.fromArgb(255, 12, 90, 130)
    drawEffectSample(painter, sample, "Glow", notnull g_OutlineFont, Color.fromArgb(255, 235, 252, 255), fx)

    drawWrappedText(painter, {body.x + 18, body.bottom() - 24, body.width - 36, 22}, "glowColor + glowPower 1.4 over a dark surface", notnull g_HelpFont, Argb.DimGray)
}

func drawBevelEffectCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Bevel", "The distance-field gradient is lit from the upper-left, embossing the face for a raised, metallic look.")
    let sample = insetRect(body, 20, 12, 20, 30)
    drawEffectSurface(painter, sample, Color.fromArgb(255, 238, 240, 244))

    var fx: TextEffect
    fx.bevel        = 0.9
    fx.outlineWidth = 0.05
    fx.outlineColor = Color.fromArgb(160, Argb.Black)
    drawEffectSample(painter, sample, "Bevel", notnull g_OutlineFont, Color.fromArgb(255, 196, 170, 96), fx)

    drawWrappedText(painter, {body.x + 18, body.bottom() - 24, body.width - 36, 22}, "bevel 0.9 emboss + faint outline on a gold face", notnull g_HelpFont, Argb.DimGray)
}

func drawShadowEffectCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Drop shadow", "A softened, offset second pass behind the text. Combined here with an outline in a single drawString call.")
    let sample = insetRect(body, 20, 12, 20, 30)
    drawEffectSurface(painter, sample, Color.fromArgb(255, 248, 249, 251))

    var fx: TextEffect
    fx.shadowColor    = Color.fromArgb(150, Argb.Black)
    fx.shadowOffset   = {5, 6}
    fx.shadowSoftness = 0.45
    fx.outlineWidth   = 0.16
    fx.outlineColor   = Argb.Crimson
    drawEffectSample(painter, sample, "Shadow", notnull g_OutlineFont, Argb.White, fx)

    drawWrappedText(painter, {body.x + 18, body.bottom() - 24, body.width - 36, 22}, "shadowOffset (5,6) + softness 0.45, outline + face in one pass", notnull g_HelpFont, Argb.DimGray)
}

func drawTextEffectsPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "MSDF text effects", "Page 10 : outline, glow, bevel and soft drop shadow, derived from the glyph distance field (TextMeshPro-style).")
    drawOutlineEffectCard(painter, {28, 104, 452, 280})
    drawGlowEffectCard(painter, {500, 104, 452, 280})
    drawBevelEffectCard(painter, {28, 406, 452, 258})
    drawShadowEffectCard(painter, {500, 406, 452, 258})
}
