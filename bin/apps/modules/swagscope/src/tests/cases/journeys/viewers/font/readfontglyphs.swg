#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Viewers

// Write a font specimen, browse its glyphs, and return to the first page.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    let file = journey.copyData("segoeui.ttf", "reading.ttf")
    let window = journey.window

    window.openFile(file)
    journey.waitForFile(file)
    Swag.require(window.choices[window.activeChoiceIndex].key == "font")
    let font = assume cast(*Typeface.Panel, window.currentView)
    font.sampleEdit.setText("Swag 123")
    Swag.require(font.sampleEdit.text() == "Swag 123" and font.nextButton.isEnabled())

    let first = font.document.pageStart
    font.nextButton.sigPressed.call(font.nextButton)
    journey.waitFor("next glyph page", func|font, first|()->bool => font.document.pageStart > first and
                                                               font.previousButton.isEnabled())
    font.previousButton.sigPressed.call(font.previousButton)
    journey.waitFor("first glyph page", func|font, first|()->bool => font.document.pageStart == first)

    font.document.goToCharacterPage(0x370)
    journey.waitFor("Greek glyphs", func|font|()->bool => font.document.pageStart >= 0x370)
    Swag.require(font.sampleEdit.text() == "Swag 123")
}
