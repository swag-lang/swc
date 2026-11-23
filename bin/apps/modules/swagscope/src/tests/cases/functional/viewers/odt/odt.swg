#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// A Writer-produced OpenDocument opens its actual text, headings and table before the archive.
#test
{
    let document = expect Odt.Document.load(scopeTestDataPath("viewer.odt"))
    Swag.require(document.paragraphs >= 12 and document.tables == 1)
    Swag.require(Utf8.contains(document.html, "A quieter reading room"))
    Swag.require(Utf8.contains(document.html, "<h1") and Utf8.contains(document.html, "<h2"))
    Swag.require(Utf8.contains(document.html, "font-size:24") and Utf8.contains(document.html, "216a56"))
    Swag.require(Utf8.contains(document.html, "<table") and Utf8.contains(document.html, "A place to begin"))
}

// Embedded pictures keep their location in the reading order and their authored raster dimensions.
#test
{
    let document = expect Odt.Document.load(scopeTestDataPath("viewer.image.odt"))
    Swag.require(document.images == 1 and document.omitted == 0)
    Swag.require(Utf8.contains(document.html, "data:image/jpeg;base64,"))
    Swag.require(Utf8.contains(document.html, "width=\"320\" height=\"240\""))
    Swag.require(Utf8.contains(document.html, "Grey and silver arcs"))
    Swag.require(Utf8.indexOf(document.html, "The image keeps") < Utf8.indexOf(document.html, "<img"))
    Swag.require(Utf8.indexOf(document.html, "<img") < Utf8.indexOf(document.html, "The words continue"))
}

// The reader owns the usual asynchronous lifecycle and filterable heading outline.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.odt"), false)
    Swag.require(window.choices[window.activeChoiceIndex].key == "odt")
    let panel = assume cast(*Odt.Panel, window.currentView)
    Swag.require(panel.view != null and panel.outline!.headings.count == 4)
}
