#global private

using Swag, Core

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
    var colors: ThemeColors

    colors.setDark()
    @assert(colors.wnd_Border.a == 255)

    colors.setLight()
    @assert(colors.wnd_Border.a == 255)

    colors.setSwagDark()
    @assert(colors.wnd_Border.a == 255)

    colors.setSwagLight()
    @assert(colors.wnd_Border.a == 255)
}

// A Swag palette carries its own geometry, and it takes the surface corner with it: the outline
// of a window is the one piece of chrome the chart softens, so the palette narrows the default
// rather than squaring it.
#test
{
    var theme: Theme
    @assert(theme.metrics.surfaceWnd_CornerRadius == 18)

    theme.setSwagDark()
    @assert(theme.colors.activeRail == 0xFFF7F900)
    @assert(theme.metrics.surfaceWnd_CornerRadius == 8)

    theme.metrics.surfaceWnd_CornerRadius = 18
    theme.setSwagLight()
    @assert(theme.colors.activeRail == 0xFF0B0B0D)
    @assert(theme.metrics.surfaceWnd_CornerRadius == 8)
}
