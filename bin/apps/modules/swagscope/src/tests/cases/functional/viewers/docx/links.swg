#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Internal anchors are safe and forward references resolve; relation links stay inert.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.links.docx"))
    Swag.require(Utf8.contains(document.html, "<a href=\"#docx-bookmark-Later\">Jump ahead</a>"), document.html)
    Swag.require(Utf8.contains(document.html, "<a href=\"#docx-bookmark-Later\">Jump again</a>"))
    Swag.require(Utf8.contains(document.html, "<a id=\"docx-bookmark-Later\"></a>Destination"), document.html)
    Swag.require(Utf8.contains(document.html, "External label"))
    Swag.require(not Utf8.contains(document.html, "https://example.invalid"))
    Swag.require(not Utf8.contains(document.html, "href=\"#docx-bookmark-bad name\""))
    Swag.require(Utf8.contains(document.html, "Unsafe target"))
    Swag.require(Utf8.contains(document.html, "Missing target"))
    Swag.require(document.linksSimplified)
    Swag.require(Utf8.contains(document.details(), "some links simplified"))
}
