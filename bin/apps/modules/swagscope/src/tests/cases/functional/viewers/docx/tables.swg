#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// A Word grid span becomes the matching HTML table-cell column span.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.table-span.docx"))
    Swag.require(document.tables == 1)
    Swag.require(Utf8.contains(document.html, "<table><tr><td style=\"width:288.00px\" colspan=\"2\"><p>Spans two columns</p></td><td><p>Third column</p></td></tr>"), document.html)
    Swag.require(Utf8.contains(document.html, "<tr><td><p>One</p></td><td><p>Two</p></td><td><p>Three</p></td></tr></table>"), document.html)
}
