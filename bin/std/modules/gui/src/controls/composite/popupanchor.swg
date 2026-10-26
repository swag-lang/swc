using Core, Pixel

// Paints the tab that joins a popup body to the menu-bar entry or icon button that opened it.
//
// `anchorRect` is the opener and `bodyRect` the body, both in the local coordinates of `popup`.
// The body stands above its tab when `opensUp` is true and hangs below it otherwise. The caller
// paints what the tab carries — the bar entry's wording or the button's own content — afterwards.
internal func paintPopupAnchorTab(popup: *Wnd, painter: *Painter, anchorRect, bodyRect: Math.Rectangle, opensUp: bool)
{
    let colors  = popup.themeColors()
    let rects   = popup.themeRects()
    let metrics = popup.themeMetrics()

    // The fill runs past the top of the body, which is what opens the mouth of the anchor: it
    // repaints the stretch of the popup's own outline the two shapes share, so the bar item
    // and the popup read as one form rather than as a box sitting on a lid.
    var anchorBk = anchorRect
    if opensUp
    {
        let bottom = anchorBk.bottom()
        anchorBk.y      = bodyRect.bottom() - metrics.menuPopup_BarItemOverlap
        anchorBk.height = bottom - anchorBk.y
    }
    else
    {
        anchorBk.setBottom(bodyRect.y + metrics.menuPopup_BarItemOverlap)
    }

    drawPopupAnchorRect(popup, painter, anchorBk, &rects.menuPopup_BarAnchorBk, colors.menuPopup_Bk, opensUp)

    // The outline stops on that line instead of following the fill down. Carried the whole
    // way it ended a dozen pixels inside the body, and the two sides of the anchor read as
    // stubs hanging off the shape they were meant to continue.
    var anchorBorder = anchorBk
    if opensUp
    {
        let bottom = anchorBorder.bottom()
        anchorBorder.y      = bodyRect.bottom() - metrics.wnd_BorderSize
        anchorBorder.height = bottom - anchorBorder.y
    }
    else
    {
        anchorBorder.setBottom(bodyRect.y + metrics.wnd_BorderSize)
    }

    drawPopupAnchorRect(popup, painter, anchorBorder, &rects.menuPopup_BarAnchorBorder, colors.menuPopup_Border, opensUp, interpol: .Pixel)

    // The popup body's rounded corner leaves its outside edge transparent until the radius
    // reaches the straight side. Where an anchor continues that exact edge, complete the
    // hairline only across the overlap: this is uncovered space, not a second outline.
    let overlapY = opensUp ? bodyRect.bottom() - metrics.menuPopup_BarItemOverlap : bodyRect.y
    let pen      = Pen.createSolid(colors.menuPopup_Border, metrics.wnd_BorderSize)
    let halfLine = metrics.wnd_BorderSize * 0.5
    if Math.abs(anchorRect.x - bodyRect.x) < metrics.wnd_BorderSize do
        painter.drawLine(bodyRect.x + halfLine, overlapY, bodyRect.x + halfLine, overlapY + metrics.menuPopup_BarItemOverlap, pen)
    if Math.abs(anchorRect.right() - bodyRect.right()) < metrics.wnd_BorderSize do
        painter.drawLine(bodyRect.right() - halfLine, overlapY, bodyRect.right() - halfLine, overlapY + metrics.menuPopup_BarItemOverlap, pen)
}

// The atlas carries the downward-opening tab. Reflecting it around its own center preserves
// the same corners and hairline when the button sits below the popup body.
private func drawPopupAnchorRect(popup: *Wnd, painter: *Painter, rect: Math.Rectangle, subRect: *ThemeImageRect, color: Color, opensUp: bool, interpol = InterpolationMode.Linear)
{
    let theme = popup.theme()
    if not opensUp
    {
        theme.drawSubRect(painter, rect, subRect, color, interpol: interpol)
        return
    }

    let base = painter.transform()
    var flip = Math.Transform2.createScale(1, -1, rect.horzCenter(), rect.vertCenter())
    flip.multiply(base)
    painter.setTransform(flip)
    theme.drawSubRect(painter, rect, subRect, color, interpol: interpol)
    painter.setTransform(base)
}
