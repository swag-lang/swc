#global private

using Swag, Core

// The Swag dark palette is the shipped look of every standard application, so the tokens it
// resolves to are pinned rather than described: a change here is a change to Swag Vault and
// Swag Capture, and it should have to be written down.
#test
{
    var colors: ThemeColors
    colors.setSwagDark()

        Swag.assert(colors.bk == 0xFF0B0B0D)
        Swag.assert(colors.text == 0xFFE9E9ED)
        Swag.assert(colors.hilight == 0xFFF7F900)
        Swag.assert(colors.hilightLightContrast == 0xFF0B0B0D)
        Swag.assert(colors.activeRail == 0xFFF7F900)
        Swag.assert(colors.btnPush_StrongBk == 0xFFF7F900)
        Swag.assert(colors.btnPush_StrongText == 0xFF0B0B0D)
        Swag.assert(colors.btnIcon_CheckedBk == 0x00000000)
        Swag.assert(colors.btnIcon_CheckedIcon == 0xFFF7F900)
        Swag.assert(colors.view_Bk == 0xFF15151A)
        Swag.assert(colors.wnd_Bk == 0xFF202026)
        Swag.assert(colors.informationBar_Bk == 0xFF1A1A20)
        Swag.assert(colors.commandBar_Bk == 0xFF25252D)
        Swag.assert(colors.toolBar_Bk == 0xFF2A2A32)
        Swag.assert(colors.dlg_InformationIcon == 0xFFB6D2F2)
        Swag.assert(colors.wnd_CaptionBk == 0xFF2A2A32)
        Swag.assert(colors.wnd_CaptionBkLead == 0xFF46462B)
        Swag.assert(colors.wnd_CaptionBkTrail == 0xFF212127)
        Swag.assert(colors.wnd_Border == 0xFF4A4A57)
        Swag.assert(colors.btnPush_Bk == 0xFF2A2A32)
        Swag.assert(colors.edit_Border == 0xFF575763)
        Swag.assert(colors.frameWnd_Border == 0xFF3D3D48)
        Swag.assert(colors.popupItem_Marker == 0xFFF7F900)
        Swag.assert(colors.popupItem_SubmenuMarker == 0xFF91919D)
        Swag.assert(colors.splitView_Bar == colors.toolBar_Bk)

        // The second tone is a block on ink exactly as the signature is, so nothing about it is
        // deepened here, and it fills the alternate action untouched.
        Swag.assert(colors.btnPush_AlternateBk == 0xFF38BDF8)
        Swag.assert(colors.btnPush_AlternateText == 0xFF0B0B0D)
        Swag.assert(colors.url_Text == 0xFF38BDF8)
        Swag.assert(colors.searchMatch_Bk == 0x3C38BDF8)
        Swag.assert(colors.searchMatch_Border.toHsl().s > 0.5)
        Swag.assert(colors.searchMatch_Glow == 0x7038BDF8)

        // A row, an entry and a tab carry that tone rather than a grey, which is where a theme
        // spends most of its color and where a signature never can.
        Swag.assert(colors.menuBar_SelectedBk == 0xFF2A4658)
        Swag.assert(colors.popupItem_HotBk == 0xFF2A4658)
        Swag.assert(colors.listItem_FocusSelectedBk == 0xFF35617C)

        // A filled action answers the pointer in its own color, so its three states differ.
        // Given one accent for all of them it reported nothing at the moment of the press.
        Swag.assert(colors.btnPushDefault_Bk != colors.btnPushDefault_HotBk)
        Swag.assert(colors.btnPushDefault_Bk != colors.btnPushDefault_PressedBk)
        Swag.assert(colors.btnPushDefault_HotBk != colors.btnPushDefault_PressedBk)
        Swag.assert(colors.btnPush_StrongBk != colors.btnPush_StrongHotBk)
        Swag.assert(colors.btnPush_StrongBk != colors.btnPush_StrongPressedBk)
        Swag.assert(colors.btnPush_AlternateBk != colors.btnPush_AlternateHotBk)
        Swag.assert(colors.btnPush_AlternateBk != colors.btnPush_AlternatePressedBk)

        // And the two filled forms never collapse onto each other: a surface showing both has to
        // say which one is the action it is for.
        Swag.assert(colors.btnPush_StrongBk != colors.btnPush_AlternateBk)
}

// Every mark of every shipped palette reads on the hardest ground that palette paints.
#test
{
    for palette in [ThemeColors.darkPalette(), ThemeColors.lightPalette(), ThemeColors.swagDarkPalette()]
    {
        var colors: ThemeColors
        colors.apply(palette)

        for ground in [palette.ground, palette.view, palette.panel, palette.informationBar, palette.commandBar, palette.toolBar, palette.raised]
        {
            Swag.assert(colors.hilight.contrastRatio(ground) >= 3.5)
            Swag.assert(colors.error.contrastRatio(ground) >= 3.5)
            Swag.assert(colors.searchMatch_Border.contrastRatio(ground) >= 3.5)
        }

            // A popup is raised over the structural panel ground. Its outline is the only persistent
            // edge once the shadow falls over dark content, so both popup families use stronger ink
            // than an internal divider.
            Swag.assert(colors.menuPopup_Border == Color.lerpRgb(palette.faintText, palette.line, 0.15))
            Swag.assert(colors.menuPopup_Border.contrastRatio(palette.panel) >= 2.5)
            Swag.assert(colors.frameWnd_PopupBorder.contrastRatio(palette.panel) >= 2.5)

            // Selection markers spend the signature because they report the chosen value. A submenu
            // chevron only reports continuation, so it stays below the wording in the ink hierarchy.
            Swag.assert(colors.popupItem_Marker == colors.hilight)
            Swag.assert(colors.popupItem_Marker.contrastRatio(palette.panel) >= 3.5)
            Swag.assert(colors.popupItem_SubmenuMarker == palette.faintText)
            Swag.assert(colors.popupItem_SubmenuMarker != colors.popupItem_Marker)
            Swag.assert(colors.splitView_Bar == colors.toolBar_Bk)
    }
}

// Adjacent application regions have six distinct grounds in every shipped palette. Controls may
// still share one of those values, but a view, an application rail, a structural panel, an
// information bar, a command bar and a tool bar never merge into one another.
#test
{
    for palette in [ThemeColors.darkPalette(), ThemeColors.lightPalette(), ThemeColors.swagDarkPalette()]
    {
        let grounds = [palette.ground, palette.view, palette.panel, palette.informationBar, palette.commandBar, palette.toolBar]
        for value, idx in grounds
        {
            for other, otherIdx in grounds where otherIdx > idx do
                Swag.assert(value != other)
        }
    }
}

// The caption band is the one surface of a window with no content to carry, so it carries the
// focus instead: an active window is lit from its mark and falls away toward its buttons, and an
// inactive one is flat. Two ends that resolved to the band itself would report nothing, which is
// exactly what the two caption grounds — ten levels apart — already failed to report.
#test
{
    var swag: ThemeColors
    swag.setSwagDark()
        Swag.assert(swag.wnd_CaptionBkLead != swag.wnd_CaptionBk)
        Swag.assert(swag.wnd_CaptionBkTrail != swag.wnd_CaptionBk)
        Swag.assert(swag.wnd_CaptionBkLead != swag.wnd_CaptionBkTrail)

    // A theme that asks for no glow keeps a flat band. The painter compares the two ends against
    // the band to skip the gradient entirely, so a ramp of nothing here would cost every neutral
    // window a brush it cannot see.
    for palette in [ThemeColors.darkPalette(), ThemeColors.lightPalette()]
    {
        var colors: ThemeColors
        colors.apply(palette)
            Swag.assert(colors.wnd_CaptionBkLead == colors.wnd_CaptionBk)
            Swag.assert(colors.wnd_CaptionBkTrail == colors.wnd_CaptionBk)
    }

    // Flat does not mean merged. Without the accent rule applications used to draw below the
    // caption, the neutral dark band still needs its own step between the application ground and
    // the raised body of a dialog.
    var dark: ThemeColors
    dark.setDark()
        Swag.assert(dark.wnd_CaptionBk == 0xFF242424)
        Swag.assert(dark.wnd_CaptionBkNotActived == 0xFF2C2C2C)
        Swag.assert(dark.wnd_CaptionBk != dark.view_Bk)
        Swag.assert(dark.wnd_CaptionBk != dark.dlg_Bk)

    var light: ThemeColors
    light.setLight()
        Swag.assert(light.wnd_CaptionBk == 0xFFFAFAFA)
        Swag.assert(light.wnd_CaptionBkNotActived == 0xFFF4F4F4)
        Swag.assert(light.wnd_CaptionBk != light.view_Bk)
        Swag.assert(light.wnd_CaptionBk != light.dlg_Bk)
}

// A caption shows the product mark, and which cut of it depends on the band underneath. The
// glyph is Voltage: on ink it floats free with its tile keyed out, and on paper it is a mark
// nobody sees, so the tile stays and the window carries the identity as a block instead. Keyed
// out on a light band, the mark simply vanishes from the title bar.
#test
{
    var dark, light: ThemeColors
    dark.setSwagDark()
    light.setLight()

        Swag.assert(markReadsOn(dark.wnd_CaptionBk))
        Swag.assert(!markReadsOn(light.wnd_CaptionBk))

        Swag.assert(markReadsOn(dark.wnd_CaptionBkLead))
}

// A surface outline is one stroke crossing two grounds: the caption ground down to the caption
// seam, the body ground below it. A translucent value therefore reports a different tone above
// and below that seam, which is what the shipped dark palette used to do (0x40FFFFFF read as
// #7C7C7C over the caption and #707070 over the body). Every palette owes an opaque outline.
#test
{
    for palette in [ThemeColors.darkPalette(), ThemeColors.lightPalette(), ThemeColors.swagDarkPalette()]
    {
        var colors: ThemeColors
        colors.apply(palette)
            Swag.assert(colors.wnd_Border.a == 255)
    }
}

// Every palette rounds standalone panels and compact tool cells, while the Swag palette
// additionally gives actions its interface corner. Leaving it has to give the remaining
// geometry back without turning either family into hard squares.
#test
{
    var theme: Theme
        Swag.assert(theme.metrics.surfaceWnd_CornerRadius == 18)
        Swag.assert(theme.metrics.panel_GutterSize == 4)
        Swag.assert(theme.metrics.splitView_BarSize == theme.metrics.panel_GutterSize + 1)
        Swag.assert(themeActionIconSize(&theme.metrics) == 20)
        Swag.assert(themeRowIconSize(&theme.metrics) == 16)
        Swag.assert(themeActionButtonSize(&theme.metrics) == 36)
        Swag.assert(themeCompactButtonSize(&theme.metrics) == 32)
        Swag.assert(themeDropDownButtonWidth(&theme.metrics) == 52)
        Swag.assert(theme.rects.panel_Bk.radius == 7)
        Swag.assert(theme.rects.btnIcon_SquareBk.radius == 4)

    theme.setSwagDark()
        Swag.assert(theme.colors.activeRail == 0xFFF7F900)
        Swag.assert(theme.metrics.surfaceWnd_CornerRadius == 12)
        Swag.assert(theme.rects.btnPush_Normal.rect == theme.rects.edit_SquareBk.rect)
        Swag.assert(theme.rects.panel_Bk.rect == theme.rects.edit_SquareBk.rect)
        Swag.assert(theme.rects.btnIcon_SquareBk.rect == theme.rects.btnIcon_RoundSquareBk.rect)
        Swag.assert(theme.rects.btnIcon_CheckedSquare.rect == theme.rects.btnIcon_CheckedRoundSquare.rect)
        Swag.assert(theme.rects.btnIcon_SquareBk.radius == 4)

    theme.setDark()
        Swag.assert(theme.colors.activeRail.a == 0)
        Swag.assert(theme.metrics.surfaceWnd_CornerRadius == 18)
        Swag.assert(theme.rects.btnPush_Normal.rect != theme.rects.edit_SquareBk.rect)
        Swag.assert(theme.rects.panel_Bk.radius == 7)
        Swag.assert(theme.rects.btnIcon_SquareBk.rect == theme.rects.btnIcon_RoundSquareBk.rect)
        Swag.assert(theme.rects.btnIcon_CheckedSquare.rect == theme.rects.btnIcon_CheckedRoundSquare.rect)
        Swag.assert(theme.rects.btnIcon_SquareBk.radius == 4)

    theme.setSwagDark()
    theme.setLight()
        Swag.assert(theme.metrics.surfaceWnd_CornerRadius == 18)
}
