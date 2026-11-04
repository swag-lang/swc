using Core, Pixel

// The opener stays on its own surface. A quiet selected ground identifies it without
// extending its border into the popup or casting a second shadow.
internal func paintPopupOpener(popup: *Wnd, painter: *Painter, anchorRect: Math.Rectangle, button: *IconButton? = null)
{
    var ground = anchorRect

    // An underlined choice can live inside a paragraph: its hit target is taller than its
    // line, but its selected ground must not cover the preceding line of explanation.
    if button and button.flags.has(.Underline)
    {
        ground.height = Math.min(ground.height, button.font().regular!.height)
        ground.y      = anchorRect.vertCenter() - ground.height * 0.5
    }

    popup.theme().drawSubRect(painter, ground, &popup.themeRects().btnIcon_RoundSquareBk, popup.themeColors().menuPopup_Bk)
}
