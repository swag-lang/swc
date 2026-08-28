#global private

using Swag, Core

// The Swag dark palette is the shipped look of every standard application, so the tokens it
// resolves to are pinned rather than described: a change here is a change to sVaultDrive and
// sSnapForge, and it should have to be written down.
#test
{
    var colors: ThemeColors
    colors.setSwagDark()

    @assert(colors.bk == 0xFF0B0B0D)
    @assert(colors.text == 0xFFE9E9ED)
    @assert(colors.hilight == 0xFFF7F900)
    @assert(colors.hilightLightContrast == 0xFF0B0B0D)
    @assert(colors.activeRail == 0xFFF7F900)
    @assert(colors.btnPush_StrongBk == 0xFFF7F900)
    @assert(colors.btnPush_StrongText == 0xFF0B0B0D)
    @assert(colors.btnIcon_CheckedBk == 0x00000000)
    @assert(colors.btnIcon_CheckedIcon == 0xFFF7F900)
    @assert(colors.view_Bk == 0xFF15151A)
    @assert(colors.wnd_Bk == 0xFF202026)
    @assert(colors.band_Bk == 0xFF2A2A32)
    @assert(colors.dlg_InformationIcon == 0xFFB6D2F2)
    @assert(colors.wnd_CaptionBk == 0xFF2A2A32)
    @assert(colors.wnd_CaptionBkLead == 0xFF46462B)
    @assert(colors.wnd_CaptionBkTrail == 0xFF212127)
    @assert(colors.wnd_Border == 0xFF4A4A57)
    @assert(colors.btnPush_Bk == 0xFF2A2A32)
    @assert(colors.edit_Border == 0xFF575763)
    @assert(colors.frameWnd_Border == 0xFF3D3D48)

    // The second tone is a block on ink exactly as the signature is, so nothing about it is
    // deepened here, and it fills the alternate action untouched.
    @assert(colors.btnPush_AlternateBk == 0xFF38BDF8)
    @assert(colors.btnPush_AlternateText == 0xFF0B0B0D)
    @assert(colors.url_Text == 0xFF38BDF8)
    @assert(colors.searchMatch_Bk == 0x3C38BDF8)
    @assert(colors.searchMatch_Border.toHsl().s > 0.5)
    @assert(colors.searchMatch_Glow == 0x7038BDF8)

    // A row, an entry and a tab carry that tone rather than a grey, which is where a theme
    // spends most of its color and where a signature never can.
    @assert(colors.menuBar_SelectedBk == 0xFF2A4658)
    @assert(colors.popupItem_HotBk == 0xFF2A4658)
    @assert(colors.listItem_FocusSelectedBk == 0xFF35617C)

    // A filled action answers the pointer in its own color, so its three states differ.
    // Given one accent for all of them it reported nothing at the moment of the press.
    @assert(colors.btnPushDefault_Bk != colors.btnPushDefault_HotBk)
    @assert(colors.btnPushDefault_Bk != colors.btnPushDefault_PressedBk)
    @assert(colors.btnPushDefault_HotBk != colors.btnPushDefault_PressedBk)
    @assert(colors.btnPush_StrongBk != colors.btnPush_StrongHotBk)
    @assert(colors.btnPush_StrongBk != colors.btnPush_StrongPressedBk)
    @assert(colors.btnPush_AlternateBk != colors.btnPush_AlternateHotBk)
    @assert(colors.btnPush_AlternateBk != colors.btnPush_AlternatePressedBk)

    // And the two filled forms never collapse onto each other: a surface showing both has to
    // say which one is the action it is for.
    @assert(colors.btnPush_StrongBk != colors.btnPush_AlternateBk)
}

// Every mark of every shipped palette reads on the hardest ground that palette paints.
#test
{
    for palette in [ThemeColors.darkPalette(), ThemeColors.lightPalette(), ThemeColors.swagDarkPalette()]
    {
        var colors: ThemeColors
        colors.apply(palette)

        for ground in [palette.ground, palette.view, palette.panel, palette.band, palette.raised]
        {
            @assert(colors.hilight.contrastRatio(ground) >= 3.5)
            @assert(colors.error.contrastRatio(ground) >= 3.5)
            @assert(colors.searchMatch_Border.contrastRatio(ground) >= 3.5)
        }
    }
}

// Adjacent application regions have four distinct grounds in every shipped palette. Controls may
// still share one of those values, but a view, an application rail, a structural panel and a plain
// information band never merge into one another.
#test
{
    for palette in [ThemeColors.darkPalette(), ThemeColors.lightPalette(), ThemeColors.swagDarkPalette()]
    {
        @assert(palette.ground != palette.view and palette.ground != palette.panel and palette.ground != palette.band)
        @assert(palette.view != palette.panel and palette.view != palette.band)
        @assert(palette.panel != palette.band)
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
    @assert(swag.wnd_CaptionBkLead != swag.wnd_CaptionBk)
    @assert(swag.wnd_CaptionBkTrail != swag.wnd_CaptionBk)
    @assert(swag.wnd_CaptionBkLead != swag.wnd_CaptionBkTrail)

    // A theme that asks for no glow keeps a flat band. The painter compares the two ends against
    // the band to skip the gradient entirely, so a ramp of nothing here would cost every neutral
    // window a brush it cannot see.
    for palette in [ThemeColors.darkPalette(), ThemeColors.lightPalette()]
    {
        var colors: ThemeColors
        colors.apply(palette)
        @assert(colors.wnd_CaptionBkLead == colors.wnd_CaptionBk)
        @assert(colors.wnd_CaptionBkTrail == colors.wnd_CaptionBk)
    }

    // Flat does not mean merged. Without the accent rule applications used to draw below the
    // caption, the neutral dark band still needs its own step between the application ground and
    // the raised body of a dialog.
    var dark: ThemeColors
    dark.setDark()
    @assert(dark.wnd_CaptionBk == 0xFF2C2C2C)
    @assert(dark.wnd_CaptionBk != dark.view_Bk)
    @assert(dark.wnd_CaptionBk != dark.dlg_Bk)
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

    @assert(markReadsOn(dark.wnd_CaptionBk))
    @assert(!markReadsOn(light.wnd_CaptionBk))

    @assert(markReadsOn(dark.wnd_CaptionBkLead))
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
        @assert(colors.wnd_Border.a == 255)
    }
}

// A Swag palette carries its own geometry: the window takes the large corner, while actions,
// rectangular tool cells and standalone panels share the slight interface corner. Leaving a Swag
// palette has to give that geometry back, or a surface switching to a neutral theme keeps the
// previous palette's shapes under its new accent.
#test
{
    var theme: Theme
    @assert(theme.metrics.surfaceWnd_CornerRadius == 18)
    @assert(theme.rects.panel_Bk.radius == 0)
    @assert(theme.rects.btnIcon_SquareBk.radius == 0)

    theme.setSwagDark()
    @assert(theme.colors.activeRail == 0xFFF7F900)
    @assert(theme.metrics.surfaceWnd_CornerRadius == 12)
    @assert(theme.rects.btnPush_Normal.rect == theme.rects.edit_SquareBk.rect)
    @assert(theme.rects.panel_Bk.rect == theme.rects.edit_SquareBk.rect)
    @assert(theme.rects.btnIcon_SquareBk.rect == theme.rects.btnIcon_RoundSquareBk.rect)
    @assert(theme.rects.btnIcon_CheckedSquare.rect == theme.rects.btnIcon_CheckedRoundSquare.rect)
    @assert(theme.rects.btnIcon_SquareBk.radius == 4)

    theme.setDark()
    @assert(theme.colors.activeRail.a == 0)
    @assert(theme.metrics.surfaceWnd_CornerRadius == 18)
    @assert(theme.rects.btnPush_Normal.rect != theme.rects.edit_SquareBk.rect)
    @assert(theme.rects.panel_Bk.radius == 0)
    @assert(theme.rects.btnIcon_SquareBk.radius == 0)

    theme.setSwagDark()
    theme.setLight()
    @assert(theme.metrics.surfaceWnd_CornerRadius == 18)
}
