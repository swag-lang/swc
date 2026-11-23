#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Pixel, Viewers

// Cached non-smoothed line series render as an image and retain their exact text values.
#test
{
    let deck = expect Pptx.Presentation.load(scopeTestDataPath("viewer.line-chart.pptx"))
    let page = &deck.slides[0]
    Swag.require(not page.simplified and page.title == "Quarterly trend")
    let reading = page.readingHtml()
    Swag.require(Utf8.contains(reading, "Observed"))
    Swag.require(Utf8.contains(reading, "Q1: -3") and Utf8.contains(reading, "Q4: 2"))
    Swag.require(Utf8.contains(reading, "Target") and Utf8.contains(reading, "Q3: -2"))
    Swag.require(Utf8.contains(page.canvasHtml(deck.width, deck.height), "data:image/png;base64,"))
}

// Smoothed line interpolation remains on the viewer's simplified fallback.
#test
{
    let deck = expect Pptx.Presentation.load(scopeTestDataPath("viewer.smooth-line-chart.pptx"))
    Swag.require(deck.slides[0].simplified)
    Swag.require(Utf8.contains(deck.slides[0].readingHtml(), "Quarterly trend"))
    Swag.require(not Utf8.contains(deck.slides[0].canvasHtml(deck.width, deck.height), "data:image/png;base64,"))
}

// Standard cached area series render with their values retained for text reading.
#test
{
    let deck = expect Pptx.Presentation.load(scopeTestDataPath("viewer.area-chart.pptx"))
    let page = &deck.slides[0]
    Swag.require(not page.simplified and page.title == "Quarterly trend")
    Swag.require(Utf8.contains(page.readingHtml(), "Observed") and Utf8.contains(page.readingHtml(), "Q3: 8"))
    Swag.require(Utf8.contains(page.canvasHtml(deck.width, deck.height), "data:image/png;base64,"))
}

// Stacked area charts stay on the explicit simplified fallback.
#test
{
    let deck = expect Pptx.Presentation.load(scopeTestDataPath("viewer.stacked-area-chart.pptx"))
    Swag.require(deck.slides[0].simplified)
    Swag.require(Utf8.contains(deck.slides[0].readingHtml(), "Quarterly trend"))
    Swag.require(not Utf8.contains(deck.slides[0].canvasHtml(deck.width, deck.height), "data:image/png;base64,"))
}
