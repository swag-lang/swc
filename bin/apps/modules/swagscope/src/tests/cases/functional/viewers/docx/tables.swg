#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Word grid spans, cell widths, and vertical alignment become HTML table-cell attributes.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.table-span.docx"))
    Swag.require(document.tables == 1)
    Swag.require(Utf8.contains(document.html, "<table><tr><td colspan=\"2\" style=\"width:288.00px;vertical-align:middle;\"><p>Spans two columns</p></td><td><p>Third column</p></td></tr>"), document.html)
    Swag.require(Utf8.contains(document.html, "<tr><td><p>One</p></td><td><p>Two</p></td><td><p>Three</p></td></tr></table>"), document.html)
}
