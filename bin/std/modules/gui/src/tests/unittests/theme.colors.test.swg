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
    @assert(colors.wnd_Border == 0xFF6B6B77)
    @assert(colors.btnPush_Bk == 0xFF2A2A32)
    @assert(colors.edit_Border == 0xFF6B6B77)
    @assert(colors.menuBar_SelectedBk == 0xFF33333C)
    @assert(colors.popupItem_HotBk == 0xFF33333C)
    @assert(colors.listItem_FocusSelectedBk == 0xFF3B3B46)
    @assert(colors.frameWnd_Border == 0xFF3D3D48)
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

#test
{
    var theme: Theme
    @assert(theme.metrics.surfaceWnd_CornerRadius != 0)

    theme.setSwagDark()
    @assert(theme.colors.activeRail == 0xFFF7F900)
    @assert(theme.metrics.surfaceWnd_CornerRadius == 0)

    theme.metrics.surfaceWnd_CornerRadius = 18
    theme.setSwagLight()
    @assert(theme.colors.activeRail == 0xFF0B0B0D)
    @assert(theme.metrics.surfaceWnd_CornerRadius == 0)
}
