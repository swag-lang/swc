#global if #command == Swag.CompilerCommand.Test

using Swag, Core, Pixel

// Style-sheet overrides accumulate one line at a time, and every change marks the style dirty.
#test
{
    var style: ThemeStyle
    Swag.assert(not style.dirty)
    Swag.assert(style.styleSheetColors.isEmpty())
    Swag.assert(style.styleSheetMetrics.isEmpty())

    style.setStyleSheetColors("btn_Text $white")
    Swag.assert(style.dirty)
    Swag.assert(style.styleSheetColors == "btn_Text $white")

    style.addStyleSheetColors("btn_Bk $black")
    Swag.assert(style.styleSheetColors == "btn_Text $white\nbtn_Bk $black")

    style.clearStyleSheetColors()
    Swag.assert(style.styleSheetColors.isEmpty())
    Swag.assert(style.dirty)

    style.dirty = false
    style.setStyleSheetMetrics("button_Height 24")
    Swag.assert(style.dirty)
    Swag.assert(style.styleSheetMetrics == "button_Height 24")

    style.addStyleSheetMetrics("button_Margin 2")
    Swag.assert(style.styleSheetMetrics == "button_Height 24\nbutton_Margin 2")
}

// Unset font slots fall back to an assigned face, and clearing the fonts empties every slot.
#test
{
    var regular: Font
    var bold:    Font
    var italic:  Font
    var style:   ThemeStyle

    style.setFont(&regular, .Regular)
    Swag.assert(style.dirty)
    Swag.assert(style.font.regular == &regular)
    Swag.assert(style.font.getFont(.Regular) == &regular)
    Swag.assert(style.font.getFont(.Bold) == &regular)

    style.dirty = false
    style.setFont(&bold, .Bold)
    style.setFont(&italic, .Italic)
    Swag.assert(style.dirty)
    Swag.assert(style.font.bold == &bold)
    Swag.assert(style.font.italic == &italic)
    Swag.assert(style.font.getFont(.BoldItalic) == &italic)

    style.clearFont()
    Swag.assert(style.dirty)
    Swag.assert(style.font.regular == null)
    Swag.assert(style.font.bold == null)
    Swag.assert(style.font.italic == null)
    Swag.assert(style.font.boldItalic == null)
}
