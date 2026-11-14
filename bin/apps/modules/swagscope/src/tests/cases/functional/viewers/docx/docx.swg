#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// Basic Word content becomes a reading page with escaped text, tables, and named omissions.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.docx"))
    Swag.require(document.paragraphs == 4 and document.tables == 1 and document.omittedImages == 1)
    Swag.require(Utf8.contains(document.html, "Hello &amp; welcome"))
    Swag.require(Utf8.contains(document.html, "<table><tr><td><p>One</p></td><td><p>Two</p></td></tr></table>"))
    Swag.require(Utf8.contains(document.html, "[Image not shown]"))
}

// The document opens through the registered reading viewer, before the ZIP fallback.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.docx"), false)
    Swag.require(window.choices[window.activeChoiceIndex].key == "docx")
    let view = assume cast(*Docx.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.view != null and view.document.paragraphs == 4)
}

// A Word document from the Apache POI corpus retains its prose across formatted runs.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.poi-sample.docx"))
    Swag.require(document.paragraphs >= 3)
    Swag.require(Utf8.contains(document.html, "I am a test document"))
    Swag.require(Utf8.contains(document.html, "This is page two"))
    Swag.require(Utf8.contains(document.html, "<hr>"))
}

// Split text runs, tabs, line breaks and escaped characters retain a readable order.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.runs.docx"))
    Swag.require(document.paragraphs == 2)
    Swag.require(Utf8.contains(document.html, "First run &amp; second&emsp;tab<br>line"))
    Swag.require(Utf8.contains(document.html, "&lt;escaped&gt;"))
}

// Direct run formatting and paragraph properties become visible without changing text order.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.formatted.docx"))
    Swag.require(document.paragraphs == 3)
    Swag.require(Utf8.contains(document.html, "<h1 style=\"text-align:center\"><b>Styled title</b></h1>"))
    Swag.require(Utf8.contains(document.html, "<p>Plain &amp; <i>italic</i> and <u><s>marked</s></u> text.</p>"))
    Swag.require(Utf8.contains(document.html, "<h2 style=\"text-align:right\">Second heading</h2>"))
}

// An authored page break remains visible between text runs.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.pagebreak.docx"))
    Swag.require(Utf8.contains(document.html, "line<hr>Page two"))
}

// Local image relationships render inline; an external relationship stays an explicit omission.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.image.docx"))
    Swag.require(document.paragraphs == 3 and document.omittedImages == 1)
    Swag.require(Utf8.contains(document.html, "data:image/jpeg;base64,"))
    Swag.require(Utf8.contains(document.html, "width=\"320\" height=\"240\""))
    Swag.require(Utf8.contains(document.html, "[Image not shown]"))
    Swag.require(not Utf8.contains(document.html, "example.invalid"))
}

// A published document mixes readable PNG/JPEG drawings with unsupported metafiles.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.poi-pictures.docx"))
    Swag.require(document.paragraphs > 0 and document.omittedImages > 0)
    Swag.require(Utf8.contains(document.html, "data:image/png;base64,"))
    Swag.require(Utf8.contains(document.html, "data:image/jpeg;base64,"))
    Swag.require(Utf8.contains(document.html, "[Image not shown]"))
}

// A ZIP with no document body is rejected as a damaged Word document.
#test
{
    var loadError: Swag.Error
    discard catch Docx.Document.load(scopeTestDataPath("viewer.damaged.docx")) as loadError
    Swag.require(loadError.value() is Errors.InvalidFormatError)
}
