#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Numbered, nested and bulleted Word paragraphs retain list semantics in reading order.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.numbering.docx"))
    Swag.require(document.paragraphs == 5)
    Swag.require(Utf8.contains(document.html, "First item"))
    Swag.require(Utf8.contains(document.html, "Nested item"))
    Swag.require(Utf8.contains(document.html, "Second item"))
    Swag.require(Utf8.contains(document.html, "Bullet item"))
    Swag.require(Utf8.contains(document.html, "<ol type=\"1\" start=\"3\"><li><p>First item</p><ol type=\"a\"><li><p>Nested item</p></li></ol></li><li><p>Second item</p></li></ol>"))
    Swag.require(Utf8.contains(document.html, "<ul type=\"square\"><li><p>Bullet item</p></li></ul>"))
}

// A paragraph that references a missing numbering ID stays readable and discloses simplification.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.numbering-missing.docx"))
    Swag.require(Utf8.contains(document.html, "Bullet item"))
    Swag.require(document.stylesSimplified)
    Swag.require(not Utf8.contains(document.html, "</>"))
    Swag.require(Utf8.contains(document.html, "<ol type=\"1\"><li><p>Bullet item</p></li></ol>"))
}

// Number overrides restart an abstract sequence and can replace an individual level.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.numbering-overrides.docx"))
    Swag.require(Utf8.contains(document.html, "<ol type=\"1\" start=\"4\"><li><p>Restarted first</p></li><li><p>Restarted second</p></li></ol>"))
    Swag.require(Utf8.contains(document.html, "<ol type=\"a\" start=\"2\"><li><p>Replacement first</p></li><li><p>Replacement second</p></li></ol>"))
    Swag.require(not document.stylesSimplified)
}
