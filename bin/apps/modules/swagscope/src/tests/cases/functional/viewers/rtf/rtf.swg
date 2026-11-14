#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// Formatted body text becomes a reading page; metadata and styles stay out of its prose.
#test
{
    let document = expect Rtf.Document.load(scopeTestDataPath("viewer.rtf"))
    Swag.require(document.paragraphs == 3 and document.omittedObjects == 0)
    Swag.require(Utf8.contains(document.html, "<p style=\"text-align:center\"><b>Rich text reading</b></p>"))
    Swag.require(Utf8.contains(document.html, "This is <i>formatted</i> and <u>searchable</u> text."))
    Swag.require(Utf8.contains(document.html, "First&emsp;second<br>next line."))
    Swag.require(not Utf8.contains(document.html, "Arial"))
}

// The registered reader opens an RTF page before generic text and hex alternatives.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.rtf"), false)
    Swag.require(window.choices[window.activeChoiceIndex].key == "rtf")
    let view = assume cast(*Rtf.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.view != null and view.document.paragraphs == 3)
}

// ANSI escaped bytes, Unicode fallback text and surrogate pairs each produce one visible character.
#test
{
    let document = expect Rtf.Document.load(scopeTestDataPath("viewer.unicode.rtf"))
    Swag.require(Utf8.contains(document.html, "Café, € and 😀 survive."))
    Swag.require(not Utf8.contains(document.html, "?"))
}

// Cells retain reading order and prose resumes after a simple row.
#test
{
    let document = expect Rtf.Document.load(scopeTestDataPath("viewer.table.rtf"))
    Swag.require(Utf8.contains(document.html, "<table><tr><td>One</td><td>Two</td></tr></table>"))
    Swag.require(Utf8.contains(document.html, "<p>After the table.</p>"))
}

// A document written outside this repository keeps its repeated prose and paragraph structure.
#test
{
    let document = expect Rtf.Document.load(scopeTestDataPath("viewer.libreoffice.rtf"))
    Swag.require(document.paragraphs >= 2)
    Swag.require(Utf8.contains(document.html, "This text should have single line spacing"))
    Swag.require(not Utf8.contains(document.html, "Normal Table Copy"))
}

// Ignorable destinations and binary image bytes never leak into the visible page.
#test
{
    let document = expect Rtf.Document.load(scopeTestDataPath("viewer.destinations.rtf"))
    Swag.require(document.omittedObjects == 1)
    Swag.require(Utf8.contains(document.html, "[Image not shown]"))
    Swag.require(Utf8.contains(document.html, "Visible body."))
    Swag.require(not Utf8.contains(document.html, "Hidden destination"))
    Swag.require(not Utf8.contains(document.html, "{}xx"))
}

// A truncated group is rejected rather than quietly displaying an incomplete document.
#test
{
    var loadError: Swag.Error
    discard catch Rtf.Document.load(scopeTestDataPath("viewer.damaged.rtf")) as loadError
    Swag.require(loadError.value() is Errors.InvalidFormatError)
}
