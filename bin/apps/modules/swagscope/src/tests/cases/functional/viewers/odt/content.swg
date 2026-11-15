#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// Saved fields, whitespace, bookmarks and nested lists retain their readable sequence.
#test
{
    let path = odtTestPackage("""<text:h text:outline-level="2">A heading</text:h><text:p><text:bookmark-start text:name="later"/>One<text:s text:c="2"/>two<text:tab/>three<text:line-break/><text:a xlink:href="#later">Back</text:a><text:a xlink:href="https://example.invalid">Outside</text:a><text:page-number>7</text:page-number></text:p><text:list><text:list-item><text:p>First</text:p><text:list><text:list-item><text:p>Nested</text:p></text:list-item></text:list></text:list-item></text:list>""")
    defer discard catch File.delete(path)
    let document = expect Odt.Document.load(path)
    Swag.require(document.paragraphs == 4)
    for text in ["<h2", "id=\"later\"", "href=\"#later\"", "&emsp;", "<br>", "Outside", "7", "Nested", "<ul>"] do
        Swag.require(Utf8.contains(document.html, text), text)
    Swag.require(not Utf8.contains(document.html, "https://"))
}

// Revision records, hidden sections, scripts and annotations never become ordinary document text.
#test
{
    let path = odtTestPackage("""<text:tracked-changes><text:p>Deleted private wording</text:p></text:tracked-changes><text:section text:display="none"><text:p>Hidden private wording</text:p></text:section><office:scripts><text:p>Script wording</text:p></office:scripts><text:p>Before<office:annotation><text:p>Editor wording</text:p></office:annotation>After<text:note><text:note-body><text:p>Footnote body</text:p></text:note-body></text:note></text:p>""")
    defer discard catch File.delete(path)
    let document = expect Odt.Document.load(path)
    for hidden in ["Deleted private", "Hidden private", "Script wording", "Editor wording", "Footnote body"] do
        Swag.require(not Utf8.contains(document.html, hidden), hidden)
    Swag.require(Utf8.contains(document.html, "BeforeAfter") and document.omitted >= 1)
}

// Repeated Writer table cells and rows copy both their content and document statistics.
#test
{
    let path = odtTestPackage("""<table:table><table:table-row table:number-rows-repeated="2"><table:table-cell table:number-columns-repeated="2"><text:p>A repeated cell</text:p></table:table-cell></table:table-row></table:table><text:p>After the table</text:p>""")
    defer discard catch File.delete(path)
    let document = expect Odt.Document.load(path)
    Swag.require(document.tables == 1 and document.paragraphs == 5)
    Swag.require(Utf8.contains(document.html, "After the table"))
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, path, false)
    let panel  = assume cast(*Odt.Panel, window.currentView)
    Swag.require(panel.view != null)
}

// Unsupported pictures remain explicit and cannot read a URL or a path outside the package.
#test
{
    let path = odtTestPackage("""<text:p>Before<draw:frame><draw:image xlink:href="https://example.invalid/image.png"/></draw:frame><draw:image xlink:href="%2e%2e/image.png"/><draw:image xlink:href="file:///tmp/image.png"/>After</text:p>""")
    defer discard catch File.delete(path)
    let document = expect Odt.Document.load(path)
    Swag.require(document.images == 0 and document.omitted == 3)
    Swag.require(Utf8.contains(document.html, "Before") and Utf8.contains(document.html, "After"))
    Swag.require(not Utf8.contains(document.html, "<img"))
}

// Empty documents remain valid and their French details refresh without requiring a paragraph.
#test
{
    let path = odtTestPackage("")
    defer discard catch File.delete(path)
    let document = expect Odt.Document.load(path)
    Swag.require(document.paragraphs == 0)
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, path, true, 560, 400)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    Swag.require(Odt.texts().ui_Name == "Document OpenDocument")
    let panel = assume cast(*Odt.Panel, window.currentView)
    Swag.require(panel.view != null)
}

// Wrong package identities, malformed XML and encrypted packages fail with a useful explanation.
#test
{
    let wrong     = odtTestPackage("<text:p>Body</text:p>", mime: "application/vnd.oasis.opendocument.spreadsheet")
    let broken    = odtTestPackage("<text:p>Unclosed")
    let encrypted = odtTestPackage("", manifest: "<manifest><encryption-data/></manifest>")
    defer discard catch File.delete(wrong)
    defer discard catch File.delete(broken)
    defer discard catch File.delete(encrypted)
    for path in [wrong, broken, encrypted]
    {
        var error: Swag.Error
        discard catch Odt.Document.load(path.toString()) as error
        Swag.require(error.value() is Errors.InvalidFormatError or error.value() is Errors.UnsupportedFormatError)
    }
}

// A dark authored page keeps otherwise automatic body text readable.
#test
{
    let path = odtTestPackage("<text:p>A dark page stays readable.</text:p>", styles: "<styles><page-layout-properties background-color='#000000'/></styles>")
    defer discard catch File.delete(path)
    let document = expect Odt.Document.load(path)
    Swag.require(Utf8.contains(document.html, "background-color:#000000;color:#FFFFFF"))
}
