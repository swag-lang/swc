#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// The declared slide list, not ZIP member order, determines the reading sequence.
#test
{
    let presentation = expect Pptx.Presentation.load(scopeTestDataPath("viewer.slides.pptx"))
    Swag.require(presentation.slides.count == 2 and presentation.omittedImages == 1)
    Swag.require(Utf8.contains(presentation.slides[0].readingHtml(), "Opens first"))
    Swag.require(Utf8.contains(presentation.slides[1].readingHtml(), "First &amp; final"))
    Swag.require(Utf8.contains(presentation.slides[0].readingHtml(), "[Image not shown]"))
}

// A presentation opens in its reading viewer before the ZIP fallback.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.pptx"), true)
    Swag.require(window.choices[window.activeChoiceIndex].key == "pptx")
    let view = assume cast(*Pptx.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.view != null and view.presentation.slides.count == 1)
}

// An embedded slide picture appears inline in the declared slide order.
#test
{
    let presentation = expect Pptx.Presentation.load(scopeTestDataPath("viewer.pictures.pptx"))
    Swag.require(presentation.slides.count == 2 and presentation.omittedImages == 0)
    let first = presentation.slides[0].readingHtml()
    Swag.require(Utf8.indexOf(first, "Opens first") < Utf8.indexOf(first, "data:image/jpeg;base64,"))
    Swag.require(Utf8.contains(presentation.slides[1].readingHtml(), "First &amp; final"))
    Swag.require(Utf8.contains(first, "width=\"320\" height=\"240\""))
    Swag.require(Utf8.contains(first, "alt=\"Grey &amp; silver arcs\""))
}

// Direct run styling and paragraph alignment survive the slide reading projection.
#test
{
    let presentation = expect Pptx.Presentation.load(scopeTestDataPath("viewer.formatted.pptx"))
    Swag.require(presentation.slides.count == 2 and presentation.omittedImages == 0)
    Swag.require(Utf8.contains(presentation.slides[0].readingHtml(),
                               "<p style=\"text-align:center\"><b>Opens first</b><i> styled</i></p>"))
    Swag.require(Utf8.contains(presentation.slides[1].readingHtml(),
                               "<p style=\"text-align:right\">First &amp; final</p>"))
}

// A PowerPoint deck from the Apache POI corpus keeps the slide sequence and text.
#test
{
    let presentation = expect Pptx.Presentation.load(scopeTestDataPath("viewer.poi-sample.pptx"))
    Swag.require(presentation.slides.count == 2)
    Swag.require(Utf8.contains(presentation.slides[0].readingHtml(), "Title of the first slide"))
    Swag.require(Utf8.contains(presentation.slides[1].readingHtml(), "This is the second slide"))
}

// Missing presentation relationships cannot silently become an empty deck.
#test
{
    var loadError: Swag.Error
    discard catch Pptx.Presentation.load(scopeTestDataPath("viewer.damaged.pptx")) as loadError
    Swag.require(loadError.value() is Errors.InvalidFormatError)
}
