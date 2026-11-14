#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// The declared slide list, not ZIP member order, determines the reading sequence.
#test
{
    let presentation = expect Pptx.Presentation.load(scopeTestDataPath("viewer.slides.pptx"))
    Swag.require(presentation.slides == 2 and presentation.omittedImages == 1)
    let first = Utf8.indexOf(presentation.html, "Opens first")
    let second = Utf8.indexOf(presentation.html, "First &amp; final")
    Swag.require(first != Swag.U64.Max and second != Swag.U64.Max and first < second)
    Swag.require(Utf8.contains(presentation.html, "[Image not shown]"))
}

// A presentation opens in its reading viewer before the ZIP fallback.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.pptx"), true)
    Swag.require(window.choices[window.activeChoiceIndex].key == "pptx")
    let view = assume cast(*Pptx.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.view != null and view.presentation.slides == 1)
}

// An embedded slide picture appears inline in the declared slide order.
#test
{
    let presentation = expect Pptx.Presentation.load(scopeTestDataPath("viewer.pictures.pptx"))
    Swag.require(presentation.slides == 2 and presentation.omittedImages == 0)
    let first = Utf8.indexOf(presentation.html, "Opens first")
    let image = Utf8.indexOf(presentation.html, "data:image/jpeg;base64,")
    let second = Utf8.indexOf(presentation.html, "First &amp; final")
    Swag.require(first < image and image < second)
    Swag.require(Utf8.contains(presentation.html, "width=\"320\" height=\"240\""))
    Swag.require(Utf8.contains(presentation.html, "alt=\"Grey &amp; silver arcs\""))
}

// A PowerPoint deck from the Apache POI corpus keeps the slide sequence and text.
#test
{
    let presentation = expect Pptx.Presentation.load(scopeTestDataPath("viewer.poi-sample.pptx"))
    Swag.require(presentation.slides == 2)
    let first = Utf8.indexOf(presentation.html, "Title of the first slide")
    let second = Utf8.indexOf(presentation.html, "This is the second slide")
    Swag.require(first != Swag.U64.Max and second != Swag.U64.Max and first < second)
}

// Missing presentation relationships cannot silently become an empty deck.
#test
{
    var loadError: Swag.Error
    discard catch Pptx.Presentation.load(scopeTestDataPath("viewer.damaged.pptx")) as loadError
    Swag.require(loadError.value() is Errors.InvalidFormatError)
}
