#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Real Impress pages preserve their aspect, positioned text, solid shape and raster image.
#test
{
    let presentation = expect Odp.load(scopeTestDataPath("viewer.odp"))
    Swag.require(presentation.slides.count == 2)
    Swag.require(Math.abs(presentation.width - 960) < 1 and Math.abs(presentation.height - 540) < 1)
    let first = &presentation.slides[0]
    Swag.require(not first.simplified and first.shapes.count == 3)
    Swag.require(Utf8.contains(first.readingHtml(), "A little room to share"))
    Swag.require(first.shapes[2].fill == "216a56")
    let second = &presentation.slides[1]
    Swag.require(not second.simplified and second.shapes[1].picture)
    Swag.require(Utf8.contains(second.shapes[1].html, "data:image/jpeg;base64,"))
    Swag.require(not Utf8.contains(second.readingHtml(), "Speaker-only"))
}

// Converted producer placeholder styles still expose authored slide text, excluding speaker notes.
#test
{
    let presentation = expect Odp.load(scopeTestDataPath("viewer.poi-sample.odp"))
    Swag.require(presentation.slides.count == 2)
    Swag.require(Utf8.contains(presentation.slides[1].readingHtml(), "bullet points"))
    Swag.require(not Utf8.contains(presentation.slides[1].readingHtml(), "These are the notes"))
}

// The shared presentation lifecycle provides slide turns, an outline and readable text mode.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.odp"), false)
    Swag.require(window.choices[window.activeChoiceIndex].key == "odp")
    let panel = assume cast(*Pptx.Panel, window.currentView)
    Swag.require(panel.view != null and panel.outline.headings.count == 2)
    panel.turn(1)
    Swag.require(panel.slide == 1)
    panel.setTextMode(true)
    Swag.require(panel.textMode and panel.view != null)
}
