#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Pixel, Viewers

// A cached positive single-series pie renders sectors and keeps the exact labels and values.
#test
{
    let deck = expect Pptx.Presentation.load(scopeTestDataPath("viewer.pie-chart.pptx"))
    let page = &deck.slides[0]
    Swag.require(not page.simplified and page.title == "Budget shares")
    let reading = page.readingHtml()
    Swag.require(Utf8.contains(reading, "Fieldwork: 40 (40.0%)"))
    Swag.require(Utf8.contains(reading, "Samples: 30 (30.0%)"))
    Swag.require(Utf8.contains(reading, "Travel: 20 (20.0%)"))
    Swag.require(Utf8.contains(page.canvasHtml(deck.width, deck.height), "data:image/png;base64,"))
}

// Multiple series, negative values, and mixed chart families retain the simplified fallback.
#test
{
    for file in ["viewer.pie-multiple-chart.pptx", "viewer.pie-negative-chart.pptx", "viewer.pie-combo-chart.pptx"]
    {
        let deck = expect Pptx.Presentation.load(scopeTestDataPath(file))
        Swag.require(deck.slides[0].simplified, file)
        Swag.require(not Utf8.contains(deck.slides[0].canvasHtml(deck.width, deck.height), "data:image/png;base64,"), file)
    }
}
