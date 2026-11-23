#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Footnote prose preserves paragraph order, tabs, line breaks and escaped source text.
#test
{
    let notes = expect Docx.FootnoteCatalog.parse("""<w:footnotes>
        <w:footnote w:id="1"><w:p><w:r><w:t>First &amp; foremost</w:t><w:tab/><w:t>note</w:t></w:r></w:p>
            <w:p><w:r><w:t>Second paragraph</w:t><w:br/><w:t>continued</w:t></w:r></w:p></w:footnote>
        <w:footnote w:id="2"><w:p><w:r><w:t>Later note</w:t></w:r></w:p></w:footnote>
    </w:footnotes>""")
    let first = notes.lookup("1")
    let later = notes.lookup("2")
    Swag.require(first.found and not first.limited)
    Swag.require(first.html == "<p>First &amp; foremost&emsp;note</p><p>Second paragraph<br>continued</p>")
    Swag.require(later.found and later.html == "<p>Later note</p>")
    Swag.require(not notes.lookup("3").found)
}

// Separator and continuation records are metadata, including their reserved negative IDs.
#test
{
    let notes = expect Docx.FootnoteCatalog.parse("""<footnotes>
        <footnote type="separator" id="0"><p><r><t>ignore separator</t></r></p></footnote>
        <footnote type="continuationSeparator" id="-1"><p><r><t>ignore continuation</t></r></p></footnote>
        <footnote type="continuationNotice" id="-2"><p><r><t>ignore notice</t></r></p></footnote>
        <footnote id="1"><p><r><t>Readable note</t></r></p></footnote>
    </footnotes>""")
    Swag.require(not notes.lookup("0").found)
    Swag.require(not notes.lookup("-1").found)
    Swag.require(not notes.lookup("-2").found)
    Swag.require(notes.lookup("1").found)
}

// Unsupported shapes keep note prose readable and disclose the simplified formatting.
#test
{
    let notes = expect Docx.FootnoteCatalog.parse("""<footnotes>
        <footnote id="8"><p><r><t>Plain</t><rPr><b/></rPr></r></p><tbl/></footnote>
    </footnotes>""")
    let note  = notes.lookup("8")
    Swag.require(note.found and note.limited and Utf8.contains(note.html, "Plain"))
}

// Common direct emphasis in note runs is retained without a simplification notice.
#test
{
    let notes = expect Docx.FootnoteCatalog.parse("""<footnotes>
        <footnote id="9"><p><r><rPr><b/><i/><u/></rPr><t>Bold &amp; styled</t></r>
            <r><rPr><strike/></rPr><t> crossed</t></r>
            <r><rPr><b val="0"/><u val="none"/></rPr><t> plain</t></r></p></footnote>
    </footnotes>""")
    let note  = notes.lookup("9")
    Swag.require(note.found and not note.limited)
    Swag.require(note.html == "<p><b><i><u>Bold &amp; styled</u></i></b><s> crossed</s> plain</p>")
}

// Invalid roots, duplicate IDs and unknown negative IDs are rejected.
#test
{
    var rootError: Swag.Error
    discard catch Docx.FootnoteCatalog.parse("<document/>") as rootError
    Swag.require(rootError.value() is Errors.InvalidFormatError)

    var duplicateError: Swag.Error
    discard catch Docx.FootnoteCatalog.parse("""<footnotes>
        <footnote id="1"><p>first</p></footnote><footnote id="1"><p>duplicate</p></footnote>
    </footnotes>""") as duplicateError
    Swag.require(duplicateError.value() is Errors.InvalidFormatError)

    var negativeError: Swag.Error
    discard catch Docx.FootnoteCatalog.parse("<footnotes><footnote id=\"-4\"><p>unknown</p></footnote></footnotes>") as negativeError
    Swag.require(negativeError.value() is Errors.InvalidFormatError)

    var specialError: Swag.Error
    discard catch Docx.FootnoteCatalog.parse("<footnotes><footnote type=\"separator\" id=\"-4\"/></footnotes>") as specialError
    Swag.require(specialError.value() is Errors.InvalidFormatError)
}

// References render inline and append only referenced notes in their document order.
#test
{
    let fileName  = scopeTestDataPath("viewer.footnotes.docx")
    let archive   = expect Archive.Zip.load(fileName)
    let parts     = Package.PartReader{fileName, &archive, Docx.texts().err_Invalid, Docx.texts().err_TooLarge}
    let docSource = expect parts.text("word/document.xml")
    Swag.require(docSource.count > 0)
    let relations = expect parts.relationships("word/document.xml")
    let styles    = expect parts.text("word/styles.xml", required: false, limit: 4 * 1024 * 1024)
    let numbering = expect parts.text("word/numbering.xml", required: false, limit: 4 * 1024 * 1024)
    Swag.require(styles.isEmpty() and numbering.isEmpty())
    var theme            = Package.OfficeTheme.defaults()
    let styleCatalog     = expect Docx.StyleCatalog.parse(styles, &theme)
    let numberingCatalog = expect Docx.NumberingCatalog.parse(numbering)
    Swag.require(not styleCatalog.loaded and not numberingCatalog.limited)
    let path = Package.relationshipPath(relations.toSlice(), "/footnotes")
    Swag.require(path == "word/footnotes.xml", path)
    let source  = expect parts.text(path, required: false, limit: 4 * 1024 * 1024)
    let catalog = expect Docx.FootnoteCatalog.parse(source)
    Swag.require(catalog.lookup("1").found and catalog.lookup("2").found)

    let document = expect Docx.Document.load(scopeTestDataPath("viewer.footnotes.docx"))
    Swag.require(Utf8.contains(document.html, "Opening <sup id=\"docx-footnote-ref-1\"><a href=\"#docx-footnote-2\">2</a></sup> middle <sup id=\"docx-footnote-ref-2\"><a href=\"#docx-footnote-1\">1</a></sup> ending <sup id=\"docx-footnote-ref-3\"><a href=\"#docx-footnote-2\">2</a></sup>again."))
    Swag.require(Utf8.contains(document.html, "<section><h2>Footnotes</h2><div id=\"docx-footnote-2\"><sup>2</sup><p>Second note appears first.</p><p><a href=\"#docx-footnote-ref-1\">Return to reference 1</a></p><p><a href=\"#docx-footnote-ref-3\">Return to reference 2</a></p></div>"), document.html)
    Swag.require(Utf8.contains(document.html, "<div id=\"docx-footnote-1\"><sup>1</sup><p>First &amp; safely &lt;escaped&gt;&emsp;text.</p><p>A second note paragraph.</p><p><a href=\"#docx-footnote-ref-2\">Return to reference 1</a></p></div></section>"))
    Swag.require(document.footnotesSimplified)
    Swag.require(Utf8.contains(document.details(), "footnote placement or formatting simplified"))
}

// A damaged optional footnotes part leaves the text available and marks the missing reference.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.bad-footnotes.docx"))
    Swag.require(Utf8.contains(document.html, "Opening <sup>2</sup>"), document.html)
    Swag.require(Utf8.contains(document.html, "[Footnote not shown]"))
    Swag.require(not Utf8.contains(document.html, "truncated"))
    Swag.require(document.footnotesSimplified)
    Swag.require(Utf8.contains(document.details(), "footnote placement or formatting simplified"))
}
