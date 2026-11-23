#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Header and footer paragraphs preserve text order while escaping markup and retaining line breaks.
#test
{
    let header = expect Docx.HeaderFooterReader.parse("""<w:hdr><w:p><w:r><w:t>Quarter &amp; year</w:t></w:r></w:p>
        <w:p><w:r><w:t>Second line</w:t><w:br/><w:t>continued</w:t><w:tab/><w:t>page</w:t></w:r></w:p></w:hdr>""")
    Swag.require(header.html == "<p>Quarter &amp; year</p><p>Second line<br>continued&emsp;page</p>")
    Swag.require(not header.limited)
}

// A footer part uses the same ordered paragraph projection.
#test
{
    let footer = expect Docx.HeaderFooterReader.parse("<w:ftr><w:p><w:r><w:t>Confidential</w:t></w:r></w:p></w:ftr>")
    Swag.require(footer.html == "<p>Confidential</p>" and not footer.limited)
}

// The package relationship IDs connect section references to their bounded header/footer parts.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.headers.docx"))
    Swag.require(Utf8.contains(document.html,
                               "<header><p>Field notes</p></header><p>Document body</p><footer><p>Page footer</p></footer>"))
    Swag.require(document.pageElementsSimplified)
    Swag.require(Utf8.contains(document.details(), "headers and footers simplified"))
}

// A damaged optional header does not prevent its body or valid footer from opening.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.bad-header.docx"))
    Swag.require(Utf8.contains(document.html, "<p>Document body</p>"))
    Swag.require(Utf8.contains(document.html, "<footer><p>Page footer</p></footer>"))
    Swag.require(not Utf8.contains(document.html, "<header>"))
    Swag.require(Utf8.contains(document.details(), "headers and footers simplified"))
}

// A different package part cannot be mistaken for a header or footer.
#test
{
    var error: Swag.Error
    discard catch Docx.HeaderFooterReader.parse("<w:document><w:p/></w:document>") as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}
