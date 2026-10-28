// Shared drawing of the floating components of the charter: the ground they stand on, the
// section labels that group what they hold, and the keycaps that teach a key.

using Core, Pixel

// Lets a floating component cast its shadow outside its own rectangle.
//
// The window is its visible body and nothing more, so the pointer reaches the work right beside
// it: the shadow is painted before its children, in the room its parent clips to, and the
// window's invalidation padding grows by the reach of that shadow so a repaint takes it along.
// Call it again whenever the theme can have changed, which a layout pass covers.
internal func liftFloating(wnd: *Wnd)
{
    wnd.wndFlags.add(.BeforeChildrenPaint)
    let reach = wnd.theme().floatingShadowReach()
    wnd.invalidatePadding = {-reach.x, -reach.y, -reach.z, -reach.w}
}

// Draws the shadow a floating component casts under `body`, in the local coordinates of `wnd`.
internal func paintFloatingShadow(wnd: *Wnd, painter: *Painter, body: Math.Rectangle, radius: f32)
{
    painter.setParams(.Antialiased)
    wnd.theme().drawFloatingShadow(painter, body, radius)
}

// Draws the ground of a floating component: the surface ground and a hairline ring.
//
// `body` is the visible part, in the local coordinates of `wnd`. Its shadow is drawn first, by
// `paintFloatingShadow`.
internal func paintFloatingGround(wnd: *Wnd, painter: *Painter, body: Math.Rectangle, radius: f32)
{
    let colors  = wnd.themeColors()
    let metrics = wnd.themeMetrics()

    // The painter strokes a hairline on the half pixel inside the edges it is given, so the ring
    // traces the body itself: inset by hand as well, it lands a whole pixel in on the left and top
    // and leaves a band of ground outside it there.
    painter.setParams(.Antialiased)
    painter.fillRoundRect(body, radius, radius, colors.surface)
    painter.drawRoundRect(body, radius, radius, colors.line, metrics.separator_HairlineSize)
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
