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

// Vertical restarts span their continuation row without rendering an extra continuation cell.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.table-merge.docx"))
    Swag.require(document.tables == 1)
    Swag.require(Utf8.contains(document.html, "<table><tr><td rowspan=\"2\"><p>Spans two rows</p></td><td><p>Outer cell</p></td></tr><tr><td><p>Next row cell</p></td></tr></table>"), document.html)
    Swag.require(not Utf8.contains(document.details(), "some table cell merges simplified"))
}

// Nested tables retain their content without reporting an unsupported merge.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.nested-table.docx"))
    Swag.require(document.tables == 2)
    Swag.require(Utf8.contains(document.html, "<table><tr><td><p>Outer cell</p><table><tr><td><p>Nested cell</p></td></tr></table></td></tr></table>"), document.html)
    Swag.require(not Utf8.contains(document.details(), "some table cell merges simplified"))
}

// Unmatched continuation cells remain visible and disclose the simplified merge.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.bad-table-merge.docx"))
    Swag.require(Utf8.contains(document.html, "<td><p>Unmatched merge</p></td>"), document.html)
    Swag.require(Utf8.contains(document.details(), "some table cell merges simplified"))
}
