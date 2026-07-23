#global #if #command == Swag.CompilerCommand.Test

using Swag, Core, Pixel

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

#test
{
    var style:   ThemeStyle
    var regular: Font
    var bold:    Font
    var italic:  Font

    style.setFont(&regular, .Regular)
    @assert(style.dirty)
    @assert(style.font.regular == &regular)
    @assert(style.font.getFont(.Regular) == &regular)
    @assert(style.font.getFont(.Bold) == &regular)

    style.dirty = false
    style.setFont(&bold, .Bold)
    style.setFont(&italic, .Italic)
    @assert(style.dirty)
    @assert(style.font.bold == &bold)
    @assert(style.font.italic == &italic)
    @assert(style.font.getFont(.BoldItalic) == &italic)

    style.clearFont()
    @assert(style.dirty)
    @assert(style.font.regular == null)
    @assert(style.font.bold == null)
    @assert(style.font.italic == null)
    @assert(style.font.boldItalic == null)
}
