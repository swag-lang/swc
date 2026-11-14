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
}

// Split text runs, tabs, line breaks and escaped characters retain a readable order.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.runs.docx"))
    Swag.require(document.paragraphs == 2)
    Swag.require(Utf8.contains(document.html, "First run &amp; second&emsp;tab<br>line"))
    Swag.require(Utf8.contains(document.html, "&lt;escaped&gt;"))
}

// A ZIP with no document body is rejected as a damaged Word document.
#test
{
    var loadError: Swag.Error
    discard catch Docx.Document.load(scopeTestDataPath("viewer.damaged.docx")) as loadError
    Swag.require(loadError.value() is Errors.InvalidFormatError)
}
