#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Internal bookmarks resolve safely and external relationships follow their URI policy.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.links.docx"))
    Swag.require(Utf8.contains(document.html, "<a href=\"#docx-bookmark-Later\">Jump ahead</a>"), document.html)
    Swag.require(Utf8.contains(document.html, "<a href=\"#docx-bookmark-Later\">Jump again</a>"))
    Swag.require(Utf8.contains(document.html, "<a id=\"docx-bookmark-Later\"></a>Destination"), document.html)
    Swag.require(Utf8.contains(document.html, "<a href=\"https://example.invalid/private\" rel=\"noopener noreferrer\">External label</a>"), document.html)
    Swag.require(not Utf8.contains(document.html, "href=\"#docx-bookmark-bad name\""))
    Swag.require(Utf8.contains(document.html, "Unsafe target"))
    Swag.require(Utf8.contains(document.html, "Missing target"))
    Swag.require(document.linksSimplified)
    Swag.require(Utf8.contains(document.details(), "some links simplified"))
}

// Safe HTTP(S) and mailto links remain clickable; unsafe and dangling relationships are disclosed.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.external-links.docx"))
    Swag.require(Utf8.contains(document.html, "<a href=\"https://example.invalid/source?q=one&amp;r=two\" rel=\"noopener noreferrer\">Web &amp; source</a>"), document.html)
    Swag.require(Utf8.contains(document.html, "<a href=\"mailto:field-office@example.invalid\" rel=\"noopener noreferrer\">Email source</a>"), document.html)
    Swag.require(Utf8.contains(document.html, "[Link not followed]Unsafe source"), document.html)
    Swag.require(Utf8.contains(document.html, "[Link not followed]Missing source"), document.html)
    Swag.require(document.linksSimplified)
    Swag.require(Utf8.contains(document.details(), "some links simplified"))
}
