#global private

using Swag, Core

#test
{
    var colors: ThemeColors
    colors.setSwagDark()

    @assert(colors.bk == 0xFF0B0B0D)
    @assert(colors.text == 0xFFE6E6EA)
    @assert(colors.hilight == 0xFFF7F900)
    @assert(colors.hilightLightContrast == 0xFF0B0B0D)
    @assert(colors.btnPush_StrongBk == 0xFFF7F900)
    @assert(colors.btnPush_StrongText == 0xFF0B0B0D)
    @assert(colors.btnIcon_CheckedBk == 0xFFF7F900)
    @assert(colors.btnIcon_CheckedIcon == 0xFF0B0B0D)
    @assert(colors.frameWnd_Border == 0xFF26262E)
}

#test
{
    var colors: ThemeColors
    colors.setSwagLight()

    @assert(colors.bk == 0xFFFFFFFF)
    @assert(colors.text == 0xFF1B1B1D)
    @assert(colors.hilight == 0xFF0B0B0D)
    @assert(colors.hilightLightContrast == 0xFFFFFFFF)
    @assert(colors.btnPush_StrongBk == 0xFF0B0B0D)
    @assert(colors.btnPush_StrongText == 0xFFFFFFFF)
    @assert(colors.btnIcon_CheckedBk == 0xFF0B0B0D)
    @assert(colors.btnIcon_CheckedIcon == 0xFFFFFFFF)
    @assert(colors.frameWnd_Border == 0xFFE2E2DF)
}
