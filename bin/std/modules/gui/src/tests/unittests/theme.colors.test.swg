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

#test
{
    var colors: ThemeColors
    colors.setSwagLight()

    @assert(colors.bk == 0xFFF2F2F7)
    @assert(colors.view_Bk == 0xFFFFFFFF)
    @assert(colors.text == 0xFF1B1B1D)
    @assert(colors.btnIcon_CheckedBk == 0x00000000)
    @assert(colors.dlg_InformationIcon == 0xFF2E4270)
    @assert(colors.frameWnd_Border == 0xFFE3E3EC)

    // The two blocks come through the mode unchanged — that invariance is the identity — and
    // only the marks are deepened, in the family hue rather than in ink. Pointed in ink, the
    // theme drew every rail, ring and hovered border black and read as a black-and-white theme
    // with a yellow button in it.
    @assert(colors.btnPush_StrongBk == 0xFFF7F900)
    @assert(colors.btnPush_StrongText == 0xFF0B0B0D)
    @assert(colors.btnToggle_OnBk == 0xFFF7F900)
    @assert(colors.progressBar_Mark == 0xFFF7F900)
    @assert(colors.btnPush_AlternateBk == 0xFF38BDF8)
    @assert(colors.btnPush_AlternateText == 0xFF0B0B0D)
    @assert(colors.hilightLightContrast == 0xFF0B0B0D)

    @assert(colors.hilight == 0xFF7E8000)
    @assert(colors.activeRail == 0xFF7E8000)
    @assert(colors.btnPush_StrongBorder == 0xFF7E8000)
    @assert(colors.btnIcon_CheckedIcon == 0xFF7E8000)

    // Every deepened mark keeps the hue it was written with. A mark that fell back to ink is
    // the defect this pins, and it is one comparison rather than a list of values.
    for mark in [colors.hilight, colors.url_Text]
    {
        let hsl = mark.toHsl()
        @assert(hsl.s > 0.5)
        @assert(mark != 0xFF0B0B0D)
    }

    // A link reads on the page it is read on, which is a stricter bar than a rail has to meet.
    @assert(colors.url_Text.contrastRatio(colors.view_Bk) >= 4.5)

    // The rows carry the alternate tone here too, at the weight the neutral hover had.
    @assert(colors.menuBar_SelectedBk == 0xFFE2EEFA)
    @assert(colors.popupItem_HotBk == 0xFFE2EEFA)
    @assert(colors.listItem_FocusSelectedBk == 0xFFCBE2F6)

    // And the caption band is washed in the signature block rather than in its mark, for the
    // same reason: the block is what a light surface carries the identity with. It costs three
    // times the mix the dark band asks for, because white and Voltage part by chroma alone —
    // and at the dark amount the band was a cream nobody could name.
    @assert(colors.wnd_CaptionBkLead == 0xFFFBFC93)
    @assert(colors.wnd_CaptionBkTrail == 0xFFF4F4F8)
}

// Every mark of every shipped palette reads on the hardest ground that palette paints. This is
// the property that lets one written color answer in both modes, and the one a hand-written
// light palette kept getting wrong in one direction only.
#test
{
    for palette in [ThemeColors.darkPalette(), ThemeColors.lightPalette(), ThemeColors.swagDarkPalette(), ThemeColors.swagLightPalette()]
    {
        var colors: ThemeColors
        colors.apply(palette)

        for ground in [palette.ground, palette.view, palette.panel, palette.raised]
        {
            @assert(colors.hilight.contrastRatio(ground) >= 3.5)
            @assert(colors.error.contrastRatio(ground) >= 3.5)
        }
    }
}

// The caption band is the one surface of a window with no content to carry, so it carries the
// focus instead: an active window is lit from its mark and falls away toward its buttons, and an
// inactive one is flat. Two ends that resolved to the band itself would report nothing, which is
// exactly what the two caption grounds — ten levels apart — already failed to report.
#test
{
    for palette in [ThemeColors.swagDarkPalette(), ThemeColors.swagLightPalette()]
    {
        var colors: ThemeColors
        colors.apply(palette)
        @assert(colors.wnd_CaptionBkLead != colors.wnd_CaptionBk)
        @assert(colors.wnd_CaptionBkTrail != colors.wnd_CaptionBk)
        @assert(colors.wnd_CaptionBkLead != colors.wnd_CaptionBkTrail)
    }

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
// out in both, the mark simply vanished from the title bar of every application in the light
// theme.
#test
{
    var dark, light: ThemeColors
    dark.setSwagDark()
    light.setSwagLight()

    @assert(markReadsOn(dark.wnd_CaptionBk))
    @assert(!markReadsOn(light.wnd_CaptionBk))

    // The band is a wash, so the decision has to hold at the lit end too, which is the end the
    // mark is actually drawn on.
    @assert(markReadsOn(dark.wnd_CaptionBkLead))
    @assert(!markReadsOn(light.wnd_CaptionBkLead))
}

// A surface outline is one stroke crossing two grounds: the caption ground down to the caption
// seam, the body ground below it. A translucent value therefore reports a different tone above
// and below that seam, which is what the shipped dark palette used to do (0x40FFFFFF read as
// #7C7C7C over the caption and #707070 over the body). Every palette owes an opaque outline.
#test
{
    for palette in [ThemeColors.darkPalette(), ThemeColors.lightPalette(), ThemeColors.swagDarkPalette(), ThemeColors.swagLightPalette()]
    {
        var colors: ThemeColors
        colors.apply(palette)
        @assert(colors.wnd_Border.a == 255)
    }
}

// Every palette answers for every part. The defect this rules out is the one a reader
// actually meets: a theme derived from another one keeps the hover, the border or the ink of
// the theme it was derived from, and a black-and-white interface grows a blue button. Since
// every color comes from `apply`, the check is that no two palettes agree on a value that
// their tokens disagree about — which is what a shared ground would produce.
//
// The blocks of the two identity tones are the thing both Swag modes deliberately agree on:
// Voltage and Arc fill the same shapes under the same ink whichever way up the theme is read,
// and that is what makes the two modes one identity. Those parts are found rather than listed —
// move the blocks and their inks, and whatever follows is what they answer for — so the check
// keeps its full strength over everything else.
#test
{
    var brandA, brandB: ThemeColors
    var probe = ThemeColors.swagDarkPalette()
    brandA.apply(probe)
    probe.signature.ground   = 0xFF010203
    probe.signature.onGround = 0xFF040506
    probe.alternate.ground   = 0xFF070809
    probe.alternate.onGround = 0xFF0A0B0C
    brandB.apply(probe)

    var dark, light: ThemeColors
    dark.setSwagDark()
    light.setSwagLight()

    let darkStruct  = cast(const *TypeInfoStruct) #typeof(ThemeColors)
    var shared      = 0'u32
    var opaquePairs = 0'u32
    var brandParts  = 0'u32

    for field in darkStruct.fields
    {
        let a = (cast(const [*] u8) &dark + field.offset)[as Pixel.Color]
        let b = (cast(const [*] u8) &light + field.offset)[as Pixel.Color]
        if a.a == 0 or b.a == 0 do
            continue

        let ba = (cast(const [*] u8) &brandA + field.offset)[as Pixel.Color]
        let bb = (cast(const [*] u8) &brandB + field.offset)[as Pixel.Color]
        if ba != bb
        {
            brandParts += 1
            continue
        }

        opaquePairs += 1
        if a == b do
            shared += 1
    }

    // What legitimately survives a mode change, once the brand parts are set aside, is the
    // handful of colors that mean the same thing on any ground: the four of the close button,
    // and the white an image is tinted with. Five today; the bound leaves room for one or two
    // more of the same kind, and nothing like the twenty-two the delta-based palettes used to
    // share by accident.
    @assert(opaquePairs > 200)
    @assert(shared <= 8)

    // And the two tones really do reach a set of parts rather than one button each.
    @assert(brandParts > 20)
}

// A Swag palette carries its own geometry, and it takes the surface corner with it: the outline
// of a window is the one piece of chrome the chart softens, so the palette narrows the default
// rather than squaring it. Leaving a Swag palette has to give that geometry back, or a surface
// that switches to a neutral theme keeps square buttons under a blue accent.
#test
{
    var theme: Theme
    @assert(theme.metrics.surfaceWnd_CornerRadius == 18)

    theme.setSwagDark()
    @assert(theme.colors.activeRail == 0xFFF7F900)
    @assert(theme.metrics.surfaceWnd_CornerRadius == 12)
    @assert(theme.rects.btnPush_Normal.rect == theme.rects.edit_SquareBk.rect)

    theme.setSwagLight()
    @assert(theme.colors.activeRail == 0xFF7E8000)
    @assert(theme.metrics.surfaceWnd_CornerRadius == 12)

    theme.setDark()
    @assert(theme.colors.activeRail.a == 0)
    @assert(theme.metrics.surfaceWnd_CornerRadius == 18)
    @assert(theme.rects.btnPush_Normal.rect != theme.rects.edit_SquareBk.rect)

    theme.setSwagLight()
    theme.setLight()
    @assert(theme.metrics.surfaceWnd_CornerRadius == 18)
}
