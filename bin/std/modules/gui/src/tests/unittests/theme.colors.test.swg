#global private

using Swag, Core

// The Swag dark palette is the shipped look of every standard application, so the tokens it
// resolves to are pinned rather than described: a change here is a change to sCrypt and
// sCapture, and it should have to be written down.
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
    @assert(colors.wnd_CaptionBk == 0xFF2A2A32)
    @assert(colors.wnd_Border == 0xFF5A5A66)
    @assert(colors.btnPush_Bk == 0xFF2A2A32)
    @assert(colors.edit_Border == 0xFF6B6B77)
    @assert(colors.menuBar_SelectedBk == 0xFF41414E)
    @assert(colors.popupItem_HotBk == 0xFF41414E)
    @assert(colors.listItem_FocusSelectedBk == 0xFF52525F)
    @assert(colors.frameWnd_Border == 0xFF3D3D48)

    // A filled action answers the pointer in its own color, so its three states differ.
    // Given one accent for all of them it reported nothing at the moment of the press.
    @assert(colors.btnPushDefault_Bk != colors.btnPushDefault_HotBk)
    @assert(colors.btnPushDefault_Bk != colors.btnPushDefault_PressedBk)
    @assert(colors.btnPushDefault_HotBk != colors.btnPushDefault_PressedBk)
    @assert(colors.btnPush_StrongBk != colors.btnPush_StrongHotBk)
    @assert(colors.btnPush_StrongBk != colors.btnPush_StrongPressedBk)
}

#test
{
    var colors: ThemeColors
    colors.setSwagLight()

    @assert(colors.bk == 0xFFFFFFFF)
    @assert(colors.text == 0xFF1B1B1D)
    @assert(colors.hilight == 0xFF0B0B0D)
    @assert(colors.hilightLightContrast == 0xFFFFFFFF)
    @assert(colors.activeRail == 0xFF0B0B0D)
    @assert(colors.btnPush_StrongBk == 0xFF0B0B0D)
    @assert(colors.btnPush_StrongText == 0xFFFFFFFF)
    @assert(colors.btnIcon_CheckedBk == 0x00000000)
    @assert(colors.btnIcon_CheckedIcon == 0xFF0B0B0D)
    @assert(colors.menuBar_SelectedBk == 0xFFF0F0ED)
    @assert(colors.popupItem_HotBk == 0xFFF0F0ED)
    @assert(colors.listItem_FocusSelectedBk == 0xFFE7E7E3)
    @assert(colors.frameWnd_Border == 0xFFE2E2DF)
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
#test
{
    var dark, light: ThemeColors
    dark.setSwagDark()
    light.setSwagLight()

    let darkStruct  = cast(const *TypeInfoStruct) #typeof(ThemeColors)
    var shared      = 0'u32
    var opaquePairs = 0'u32

    for field in darkStruct.fields
    {
        let a = dref cast(const *Pixel.Color) (cast(const [*] u8) &dark + field.offset)
        let b = dref cast(const *Pixel.Color) (cast(const [*] u8) &light + field.offset)
        if a.a == 0 or b.a == 0 do
            continue

        opaquePairs += 1
        if a == b do
            shared += 1
    }

    // What legitimately survives a mode change is the handful of colors that mean the same
    // thing on any ground: the four of the close button, and the white an image is tinted
    // with. Five today; the bound leaves room for one or two more of the same kind, and
    // nothing like the twenty-two the delta-based palettes used to share by accident.
    @assert(opaquePairs > 200)
    @assert(shared <= 8)
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
    @assert(theme.metrics.surfaceWnd_CornerRadius == 8)
    @assert(theme.rects.btnPush_Normal.rect == theme.rects.edit_SquareBk.rect)

    theme.setSwagLight()
    @assert(theme.colors.activeRail == 0xFF0B0B0D)
    @assert(theme.metrics.surfaceWnd_CornerRadius == 8)

    theme.setDark()
    @assert(theme.colors.activeRail.a == 0)
    @assert(theme.metrics.surfaceWnd_CornerRadius == 18)
    @assert(theme.rects.btnPush_Normal.rect != theme.rects.edit_SquareBk.rect)

    theme.setSwagLight()
    theme.setLight()
    @assert(theme.metrics.surfaceWnd_CornerRadius == 18)
}
