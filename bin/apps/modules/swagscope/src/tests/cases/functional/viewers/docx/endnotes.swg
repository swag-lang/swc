#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

// Endnote references keep first-use order, support repeated return links and expose missing IDs.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.endnotes.docx"))
    Swag.require(Utf8.contains(document.html, "Opening <sup id=\"docx-endnote-ref-1\"><a href=\"#docx-endnote-2\">2</a></sup> middle <sup id=\"docx-endnote-ref-2\"><a href=\"#docx-endnote-1\">1</a></sup> ending <sup id=\"docx-endnote-ref-3\"><a href=\"#docx-endnote-2\">2</a></sup> missing <sup>9</sup>[Endnote not shown]."), document.html)
    Swag.require(Utf8.contains(document.html, "<section class=\"docx-endnotes\"><h2>Endnotes</h2><div id=\"docx-endnote-2\"><sup>2</sup><p>Second endnote appears first.</p><p><a href=\"#docx-endnote-ref-1\">Return to reference 1</a></p><p><a href=\"#docx-endnote-ref-3\">Return to reference 2</a></p></div>"), document.html)
    Swag.require(Utf8.contains(document.html, "<div id=\"docx-endnote-1\"><sup>1</sup><p>First &amp; safely &lt;escaped&gt; endnote.</p><p><a href=\"#docx-endnote-ref-2\">Return to reference 1</a></p></div></section>"), document.html)
    Swag.require(document.endnotesSimplified)
    Swag.require(Utf8.contains(document.details(), "endnote placement or formatting simplified"))
}

// Endnote references keep first-use order, support repeated return links and expose missing IDs.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.endnotes.docx"))
    Swag.require(Utf8.contains(document.html, "Opening <sup id=\"docx-endnote-ref-1\"><a href=\"#docx-endnote-2\">2</a></sup> middle <sup id=\"docx-endnote-ref-2\"><a href=\"#docx-endnote-1\">1</a></sup> ending <sup id=\"docx-endnote-ref-3\"><a href=\"#docx-endnote-2\">2</a></sup> missing <sup>9</sup>[Endnote not shown]."), document.html)
    Swag.require(Utf8.contains(document.html, "<section class=\"docx-endnotes\"><h2>Endnotes</h2><div id=\"docx-endnote-2\"><sup>2</sup><p>Second endnote appears first.</p><p><a href=\"#docx-endnote-ref-1\">Return to reference 1</a></p><p><a href=\"#docx-endnote-ref-3\">Return to reference 2</a></p></div>"), document.html)
    Swag.require(Utf8.contains(document.html, "<div id=\"docx-endnote-1\"><sup>1</sup><p>First &amp; safely &lt;escaped&gt; endnote.</p><p><a href=\"#docx-endnote-ref-2\">Return to reference 1</a></p></div></section>"), document.html)
    Swag.require(document.endnotesSimplified)
    Swag.require(Utf8.contains(document.details(), "endnote placement or formatting simplified"))
}

// Endnote prose preserves paragraphs, whitespace elements and escaped source text.
#test
{
    let notes = expect Docx.EndnoteCatalog.parse("""<w:endnotes>
        <w:endnote w:id="1"><w:p><w:r><w:t>First &amp; foremost</w:t><w:tab/><w:t>note</w:t></w:r></w:p>
            <w:p><w:r><w:t>Second paragraph</w:t><w:br/><w:t>continued</w:t></w:r></w:p></w:endnote>
        <w:endnote w:id="2"><w:p><w:r><w:t>Later note</w:t></w:r></w:p></w:endnote>
    </w:endnotes>""")
    let first = notes.lookup("1")
    let later = notes.lookup("2")
    Swag.require(first.found and not first.limited)
    Swag.require(first.html == "<p>First &amp; foremost&emsp;note</p><p>Second paragraph<br>continued</p>")
    Swag.require(later.found and later.html == "<p>Later note</p>")
    Swag.require(not notes.lookup("3").found)
}

// Direct run emphasis is retained while unsupported shapes remain readable and disclosed.
#test
{
    let notes = expect Docx.EndnoteCatalog.parse("""<endnotes>
        <endnote id="8"><p><r><rPr><b/><i/><u/></rPr><t>Bold &amp; styled</t></r>
            <r><rPr><strike/></rPr><t> crossed</t></r>
            <r><rPr><b val="0"/><u val="none"/></rPr><t> plain</t></r></p><tbl/></endnote>
    </endnotes>""")
    let note = notes.lookup("8")
    Swag.require(note.found and note.limited)
    Swag.require(note.html == "<p><b><i><u>Bold &amp; styled</u></i></b><s> crossed</s> plain</p>")
}

// Separator and continuation records are metadata, including their reserved negative IDs.
#test
{
    let notes = expect Docx.EndnoteCatalog.parse("""<endnotes>
        <endnote type="separator" id="0"><p><r><t>ignore separator</t></r></p></endnote>
        <endnote type="continuationSeparator" id="-1"><p><r><t>ignore continuation</t></r></p></endnote>
        <endnote type="continuationNotice" id="-2"><p><r><t>ignore notice</t></r></p></endnote>
        <endnote id="1"><p><r><t>Readable note</t></r></p></endnote>
    </endnotes>""")
    Swag.require(not notes.lookup("0").found)
    Swag.require(not notes.lookup("-1").found)
    Swag.require(not notes.lookup("-2").found)
    Swag.require(notes.lookup("1").found)
}

// Invalid roots, duplicate IDs, unknown negative IDs and damaged XML are rejected.
#test
{
    var rootError: Swag.Error
    discard catch Docx.EndnoteCatalog.parse("<document/>") as rootError
    Swag.require(rootError.value() is Errors.InvalidFormatError)

    var duplicateError: Swag.Error
    discard catch Docx.EndnoteCatalog.parse("""<endnotes>
        <endnote id="1"><p>first</p></endnote><endnote id="1"><p>duplicate</p></endnote>
    </endnotes>""") as duplicateError
    Swag.require(duplicateError.value() is Errors.InvalidFormatError)

    var negativeError: Swag.Error
    discard catch Docx.EndnoteCatalog.parse("<endnotes><endnote id=\"-4\"><p>unknown</p></endnote></endnotes>") as negativeError
    Swag.require(negativeError.value() is Errors.InvalidFormatError)

    var specialError: Swag.Error
    discard catch Docx.EndnoteCatalog.parse("<endnotes><endnote type=\"separator\" id=\"-4\"/></endnotes>") as specialError
    Swag.require(specialError.value() is Errors.InvalidFormatError)

    var damagedError: Swag.Error
    discard catch Docx.EndnoteCatalog.parse("<endnotes><endnote id=\"1\"><p><r><t>truncated") as damagedError
    Swag.require(damagedError.value() is Errors.InvalidFormatError)
}
