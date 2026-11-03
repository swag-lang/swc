#global if #command == Swag.CompilerCommand.Test

using Swag, Core, Pixel

// Local metric overrides take effect during measurement, before the first paint.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 100)

    let combo = ComboBox.create(&host.root)
    combo.addItem("MiB")
    combo.style.setStyleSheetMetrics("comboBox_Width 0")
    let compact = combo.measure({})
    Swag.require(compact.preferred.x < host.theme.metrics.comboBox_Width)
    Swag.require(compact.preferred.x >= Painter.measureString("MiB", nnFont(combo.font().regular)).width)

    combo.style.setStyleSheetMetrics("comboBox_Width 180")
    let wider = combo.measure({})
    Swag.require(wider.preferred.x == 180)
}

// Style-sheet overrides accumulate one line at a time, and every change marks the style dirty.
#test
{
    var style: ThemeStyle
    Swag.require(not style.dirty)
    Swag.require(style.styleSheetColors.isEmpty())
    Swag.require(style.styleSheetMetrics.isEmpty())

    style.setStyleSheetColors("btn_Text $white")
    Swag.require(style.dirty)
    Swag.require(style.styleSheetColors == "btn_Text $white")

    style.addStyleSheetColors("btn_Bk $black")
    Swag.require(style.styleSheetColors == "btn_Text $white\nbtn_Bk $black")

    style.clearStyleSheetColors()
    Swag.require(style.styleSheetColors.isEmpty())
    Swag.require(style.dirty)

    style.dirty = false
    style.setStyleSheetMetrics("button_Height 24")
    Swag.require(style.dirty)
    Swag.require(style.styleSheetMetrics == "button_Height 24")

    style.addStyleSheetMetrics("button_Margin 2")
    Swag.require(style.styleSheetMetrics == "button_Height 24\nbutton_Margin 2")
}

// Unset font slots fall back to an assigned face, and clearing the fonts empties every slot.
#test
{
    var regular: Font
    var bold:    Font
    var italic:  Font
    var style:   ThemeStyle

    style.setFont(&regular, .Regular)
    Swag.require(style.dirty)
    Swag.require(style.font.regular == &regular)
    Swag.require(style.font.getFont(.Regular) == &regular)
    Swag.require(style.font.getFont(.Bold) == &regular)

    style.dirty = false
    style.setFont(&bold, .Bold)
    style.setFont(&italic, .Italic)
    Swag.require(style.dirty)
    Swag.require(style.font.bold == &bold)
    Swag.require(style.font.italic == &italic)
    Swag.require(style.font.getFont(.BoldItalic) == &italic)

    style.clearFont()
    Swag.require(style.dirty)
    Swag.require(style.font.regular == null)
    Swag.require(style.font.bold == null)
    Swag.require(style.font.italic == null)
    Swag.require(style.font.boldItalic == null)
}
