// Shared drawing of the floating components of the charter: the ground they stand on, the
// section labels that group what they hold, and the keycaps that teach a key.

using Core, Pixel

// Draws the ground of a floating component: its shadow, the surface ground and a hairline ring.
//
// `body` is the visible part, in the local coordinates of `wnd`. The shadow spreads
// [[Gui.ThemeMetrics.floating_ShadowSize]] around it, so the window keeps that much room on
// every side of its body.
internal func paintFloatingGround(wnd: *Wnd, painter: *Painter, body: Math.Rectangle, radius: f32)
{
    let colors  = wnd.themeColors()
    let metrics = wnd.themeMetrics()

    var shadow = body
    shadow.inflate(metrics.floating_ShadowSize)
    wnd.theme().drawSubRect(painter, shadow, &wnd.themeRects().menuPopup_Shadow, colors.floating_Shadow)

    // The ring is stroked on its own centre line, half a pixel inside the body, so its edge is
    // crisp and it never widens the shape it outlines.
    var ring = body
    ring.inflate(-0.5)
    painter.setParams(.Antialiased)
    painter.fillRoundRect(body, radius, radius, colors.surface)
    painter.drawRoundRect(ring, radius - 0.5, radius - 0.5, colors.line, metrics.separator_HairlineSize)
}

// Draws a section label: small spaced capitals in the faint ink, from the left of `rect` and
// centred on its height.
internal func paintSectionLabel(wnd: *Wnd, painter: *Painter, rect: Math.Rectangle, label: string)
{
    let metrics = wnd.themeMetrics()
    let font    = wnd.theme().createDefaultFont(metrics.sectionLabel_FontSize, .Bold)
    let text    = String.toUpper(label, .Unicode)

    // The tracking belongs to the shaped run: a rich-text layout with letter spacing drops the
    // spaces between words (see std.pixel.033).
    var shaped = Painter.shapeRun(text, font, letterSpacing: metrics.sectionLabel_LetterSpacing)
    painter.pushClippingRect(rect)
    painter.drawShapedRun(rect.x, font.opticalLineTop(rect.vertCenter()), &shaped, font, Brush.createSolid(wnd.themeColors().faintText))
    painter.popClippingRect()
}

// Returns the face a keycap names its key in.
internal func keycapFont(wnd: *Wnd)->*Font => wnd.theme().createDefaultFont(wnd.themeMetrics().keycap_FontSize)

// Returns the width of a keycap naming `key`.
internal func keycapWidth(wnd: *Wnd, key: string)->f32
{
    let metrics = wnd.themeMetrics()
    let width   = Painter.measureString(key, keycapFont(wnd)).width + 2 * metrics.keycap_Padding
    return Math.ceil(Math.max(width, metrics.keycap_Height))
}

// Draws a keycap naming `key` from `x`, centred on `centerY`, and returns its width.
//
// A keycap is a key written in a chip: the soft ink inside a hairline ring on the chip corner,
// with no ground of its own, so it reads as part of the line it sits in.
internal func paintKeycap(wnd: *Wnd, painter: *Painter, x, centerY: f32, key: string)->f32
{
    let metrics = wnd.themeMetrics()
    let colors  = wnd.themeColors()
    let font    = keycapFont(wnd)
    let width   = keycapWidth(wnd, key)
    let top     = Math.round(centerY - metrics.keycap_Height * 0.5)
    let cap     = Math.Rectangle{x + 0.5, top + 0.5, width - 1, metrics.keycap_Height - 1}

    painter.setParams(.Antialiased)
    painter.drawRoundRect(cap, metrics.corner_Chip, metrics.corner_Chip, colors.strongLine, metrics.separator_HairlineSize)

    let textWidth = Painter.measureString(key, font).width
    painter.drawString(Math.round(x + (width - textWidth) * 0.5), font.opticalLineTop(centerY), key, font, colors.softText)
    return width
}

// Draws one line of `text` from `x`, its capitals centred on `centerY`, and returns its width.
internal func paintTextLine(painter: *Painter, x, centerY: f32, text: string, font: *Font, color: Color)->f32
{
    if text.count == 0 do
        return 0
    painter.drawString(x, font.opticalLineTop(centerY), text, font, color)
    return Painter.measureString(text, font).width
}
