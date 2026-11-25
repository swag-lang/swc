#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// RTF identifiers have the full signed 32-bit range.
#test
{
    let maximum = expect Rtf.Control.parse(cast(const [..] u8, "\\listid2147483647 "), 0)
    let minimum = expect Rtf.Control.parse(cast(const [..] u8, "\\bliptag-2147483648 "), 0)
    Swag.require(maximum.hasNumber and maximum.number == Swag.S32.Max)
    Swag.require(minimum.hasNumber and minimum.number == Swag.S32.Min)

    var overflow: Swag.Error
    discard catch Rtf.Control.parse(cast(const [..] u8, "\\listid2147483648 "), 0) as overflow
    Swag.require(overflow.value() != null)

    let document = expect Rtf.Document.load(scopeTestDataPath("viewer.large-control.rtf"))
    Swag.require(Utf8.contains(document.html, "Read the document."))
}

// A long public-domain story retains its narrative scale, opening prose and Unicode typography.
#test
{
    let document = expect Rtf.Document.load(scopeTestDataPath("viewer.christmas-carol.rtf"))
    Swag.require(document.paragraphs > 700 and document.paragraphs < 850)
    Swag.require(Utf8.contains(document.html, "Marley was dead") and
                 Utf8.contains(document.html, "A merry Christmas, uncle!"))
    Swag.require(Utf8.contains(document.html, "Scrooge’s nephew"))
}

// Formatted body text becomes a reading page; metadata and styles stay out of its prose.
#test
{
    let document = expect Rtf.Document.load(scopeTestDataPath("viewer.rtf"))
    Swag.require(document.paragraphs == 3 and document.omittedObjects == 0)
    Swag.require(Utf8.contains(document.html, "text-align:center;") and Utf8.contains(document.html, "<b>Rich text reading</b>"))
    Swag.require(Utf8.contains(document.html, "This is ") and Utf8.contains(document.html, "<i>formatted</i>"))
    Swag.require(Utf8.contains(document.html, "<u>searchable</u>") and Utf8.contains(document.html, " text."))
    Swag.require(Utf8.contains(document.html, "First&emsp;second<br>next line."))
    Swag.require(Utf8.contains(document.html, "font-family:'Arial';") and not Utf8.contains(document.html, "Arial;"))
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
    Swag.require(Utf8.contains(document.html, "<p style=\"margin-top:0pt;margin-bottom:0pt\">After the table.</p>"))
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
