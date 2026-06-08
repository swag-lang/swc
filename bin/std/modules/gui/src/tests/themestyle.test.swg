#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    var style: ThemeStyle
    @assert(!style.dirty)
    @assert(style.styleSheetColors.length == 0)
    @assert(style.styleSheetMetrics.length == 0)

    style.setStyleSheetColors("btn_Text $white")
    @assert(style.dirty)
    @assert(style.styleSheetColors == "btn_Text $white")

    style.addStyleSheetColors("btn_Bk $black")
    @assert(style.styleSheetColors == "btn_Text $white\nbtn_Bk $black")

    style.clearStyleSheetColors()
    @assert(style.styleSheetColors.length == 0)
    @assert(style.dirty)

    style.dirty = false
    style.setStyleSheetMetrics("button_Height 24")
    @assert(style.dirty)
    @assert(style.styleSheetMetrics == "button_Height 24")

    style.addStyleSheetMetrics("button_Margin 2")
    @assert(style.styleSheetMetrics == "button_Height 24\nbutton_Margin 2")
}
