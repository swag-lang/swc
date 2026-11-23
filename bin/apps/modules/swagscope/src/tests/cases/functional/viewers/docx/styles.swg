#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Viewers

func readWordRun(source: string, theme: const *Package.OfficeTheme)->Docx.RunFormat
{
    var result: #returntype
    var scan = Package.Scanner.create(source)
    var token:  Package.Token
    while scan.next(&token)
    {
        if token.kind == .Start do
            result.read(&token, theme)
    }

    Swag.require(not scan.damaged)
    return result
}

func readWordParagraph(source: string)->Docx.ParagraphFormat
{
    var result: #returntype
    var scan = Package.Scanner.create(source)
    var token:  Package.Token
    while scan.next(&token)
    {
        if token.kind == .Start do
            result.read(&token)
    }

    Swag.require(not scan.damaged)
    return result
}

// Named styles retain inherited paragraph geometry and Word's character-style toggle semantics.
#test
{
    var theme  = Package.OfficeTheme.defaults()
    let source = """<styles><docDefaults><rPrDefault><rPr><sz val="22"/></rPr></rPrDefault></docDefaults>
        <style type="paragraph" styleId="Normal" default="1"><pPr><spacing after="200"/></pPr></style>
        <style type="paragraph" styleId="Chapter"><basedOn val="Normal"/><pPr><outlineLvl val="0"/><spacing before="240" after="120"/></pPr><rPr><b/><sz val="32"/></rPr></style>
        <style type="paragraph" styleId="QuietChapter"><basedOn val="Chapter"/><rPr><b/></rPr></style>
        <style type="character" styleId="Strong"><rPr><b/><i/></rPr></style></styles>"""
    let styles = expect Docx.StyleCatalog.parse(source, &theme)
    Swag.require(styles.defaultRun.size == 22 and styles.defaultParagraphId == "Normal")
    let chapter = unwrap styles.lookup(String.from("Chapter"), .Paragraph)
    Swag.require(not chapter.limited and chapter.paragraph.heading() == 1)
    Swag.require(chapter.paragraph.before == 240 and chapter.paragraph.after == 120)
    Swag.require(chapter.run.bold == .On and chapter.run.size == 32)
    let quiet = unwrap styles.lookup(String.from("QuietChapter"), .Paragraph)
    Swag.require(quiet.run.bold == .Off and quiet.run.size == 32)
    Swag.require(quiet.paragraph.heading() == 1)
    Swag.require(styles.lookup(String.from("Strong"), .Paragraph) == null)
}

// Missing parents and cycles preserve known properties while explicitly limiting the style.
#test
{
    var theme  = Package.OfficeTheme.defaults()
    let source = """<styles><style type="paragraph" styleId="A"><basedOn val="B"/><rPr><sz val="24"/></rPr></style>
        <style type="paragraph" styleId="B"><basedOn val="A"/></style>
        <style type="paragraph" styleId="Missing"><basedOn val="Absent"/><rPr><i/></rPr></style></styles>"""
    let styles = expect Docx.StyleCatalog.parse(source, &theme)
    let cycle  = unwrap styles.lookup(String.from("A"), .Paragraph)
    Swag.require(cycle.limited and cycle.run.size == 24)
    let missing = unwrap styles.lookup(String.from("Missing"), .Paragraph)
    Swag.require(missing.limited and missing.run.italic == .On)
    Swag.require(styles.lookup(String.from("Absent"), .Paragraph) == null)
}

// Direct formatting resets a style; a style toggle composes with the paragraph's effective state.
#test
{
    var theme = Package.OfficeTheme.defaults()
    var run   = readWordRun("<rPr><b/><i/><sz val=\"28\"/></rPr>", &theme)
    let reset = readWordRun("<rPr><b val=\"0\"/><i val=\"false\"/><sz val=\"22\"/></rPr>", &theme)
    run.overlay(&reset)
    Swag.require(run.bold == .Off and run.italic == .Off and run.size == 22)
    let toggle = readWordRun("<rPr><b/></rPr>", &theme)
    run.applyStyle(&toggle)
    Swag.require(run.bold == .On)
    run.applyStyle(&toggle)
    Swag.require(run.bold == .Off)
}

// Unsupported underline patterns remain legible and carry the style's simplification notice.
#test
{
    var theme  = Package.OfficeTheme.defaults()
    let single = readWordRun("<rPr><u val=\"single\"/></rPr>", &theme)
    let double = readWordRun("<rPr><u val=\"double\"/></rPr>", &theme)
    let none   = readWordRun("<rPr><u val=\"none\"/></rPr>", &theme)
    Swag.require(single.underline == .On and not single.limited)
    Swag.require(double.underline == .On and double.limited)
    Swag.require(none.underline == .Off and not none.limited)
}

// Word theme fonts and luminance transforms match the real producer's stored fallback color.
#test
{
    var theme = Package.OfficeTheme.defaults()
    theme.read("""<a:theme><a:themeElements><a:clrScheme><a:dk2><a:srgbClr val="1F497D"/></a:dk2></a:clrScheme><a:fontScheme><a:majorFont><a:latin typeface="Georgia"/></a:majorFont><a:minorFont><a:latin typeface="Arial"/></a:minorFont></a:fontScheme></a:themeElements></a:theme>""")
    let run = readWordRun("""<rPr><rFonts asciiTheme="majorHAnsi"/><color val="548DD4" themeColor="text2" themeTint="99"/><sz val="32"/></rPr>""", &theme)
    Swag.require(not run.limited and run.family == "Georgia" and run.size == 32)
    Swag.require(run.color == "548DD4", run.color)
    Swag.require(Utf8.contains(run.css(), "font-size:16.0pt;"))
    let white = readWordRun("<color themeColor=\"text2\" themeTint=\"00\"/>", &theme)
    Swag.require(not white.limited and white.color == "FFFFFF")
    let black = readWordRun("<color themeColor=\"text2\" themeShade=\"00\"/>", &theme)
    Swag.require(not black.limited and black.color == "000000")
    var absent   = Package.OfficeTheme.defaults()
    let fallback = readWordRun("<color val=\"548DD4\" themeColor=\"text2\" themeTint=\"99\"/>", &absent)
    Swag.require(fallback.color == "548DD4")
}

// Invalid font declarations and oversized text cannot inject CSS or request unbounded glyphs.
#test
{
    var theme = Package.OfficeTheme.defaults()
    let run   = readWordRun("""<rPr><rFonts ascii="Bad';position:absolute"/><sz val="999999"/></rPr>""", &theme)
    Swag.require(run.limited and run.family.isEmpty() and run.size == 0)
    Swag.require(run.css().isEmpty())
    let color = readWordRun("<color val=\"red;display:none\"/>", &theme)
    Swag.require(color.limited and color.color.isEmpty())
}

// Zero margins and hanging indents override inherited values rather than disappearing as unset.
#test
{
    var parent = readWordParagraph("<pPr><outlineLvl val=\"0\"/><ind left=\"720\" right=\"360\" firstLine=\"360\"/><spacing before=\"240\" after=\"120\" line=\"276\"/></pPr>")
    let child  = readWordParagraph("<pPr><outlineLvl val=\"9\"/><ind left=\"0\" hanging=\"360\"/><spacing before=\"0\"/></pPr>")
    parent.overlay(&child)
    Swag.require(parent.heading() == 0 and parent.before == 0 and parent.after == 120)
    Swag.require(parent.left == 0 and parent.right == 360 and parent.first == -360)
    let css = parent.css()
    Swag.require(Utf8.contains(css, "margin-left:0.00pt;"))
    Swag.require(Utf8.contains(css, "text-indent:-18.00pt;"))
    Swag.require(Utf8.contains(css, "line-height:1.150;"))
}

// A document resolves relationship-based style/theme paths and inherited headings and character styles.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.styles.docx"))
    Swag.require(document.usePaperColors and not document.stylesSimplified)
    Swag.require(document.tables == 1 and document.paragraphs == 12)
    Swag.require(Utf8.contains(document.html, "<h1"))
    Swag.require(Utf8.contains(document.html, "A little room for words"))
    Swag.require(Utf8.contains(document.html, "font-size:24.0pt;"))
    Swag.require(Utf8.contains(document.html, "font-family:'Segoe UI';"))
    Swag.require(Utf8.contains(document.html, "color:#5A7F70;"))
    Swag.require(Utf8.contains(document.html, "margin-left:18.00pt;"))
    Swag.require(Utf8.contains(document.html, "<i>follow a thought</i>"))
    Swag.require(Utf8.contains(document.html, "font-weight:normal;"))
    Swag.require(Utf8.contains(document.html, "and a quieter ending."))
}

// The final section's authored paper and margin box drive the reading body's width and padding.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.styles.docx"))
    Swag.require(document.pageWidth == 11906 and document.pageHeight == 16838)
    Swag.require(document.marginTop == 1440 and
                 document.marginRight == 1440 and
                 document.marginBottom == 1440 and
                 document.marginLeft == 1440)
    Swag.require(Utf8.contains(document.html, "max-width:793.73px;min-height:1122.53px;"))
    Swag.require(Utf8.contains(document.html, "padding:96.00px 96.00px 96.00px 96.00px;box-sizing:border-box;"))
}

// Real producer defaults retain their sizes and typefaces; unsupported section columns are disclosed.
#test
{
    let document = expect Docx.Document.load(scopeTestDataPath("viewer.poi-sample.docx"))
    Swag.require(document.usePaperColors and not document.stylesSimplified and document.sectionLayoutSimplified)
    for property in ["font-size:11.0pt;", "font-size:16.0pt;", "color:#548DD4;", "font-family:'Arial Black';"] do
        Swag.require(Utf8.contains(document.html, property))
}

// Styled headings are available through the same filterable outline as other document readers.
#test
{
    var host: Gui.Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.styles.docx"), false)
    let view   = assume cast(*Docx.Panel, window.currentView)
    let outline = unwrap view.outline
    Swag.require(outline.headings.count == 3)
    Swag.require(outline.headings[0].title == "A little room for words")
    Swag.require(outline.headings[0].level == 1 and outline.headings[1].level == 2)
    Swag.require(not view.view!.documentStyle.followTheme)
    outline.setFilter("good things")
    Swag.require(outline.rows.count == 1)
    outline.list.selectLine(0)
    Swag.require(view.view != null)
}

func wordStyleVariant(part, before, after: string)->String
{
    let source  = scopeTestDataPath("viewer.styles.docx")
    let archive = expect Archive.Zip.load(source)
    var entries: Array'ZipFixtureEntry
    for item in archive.entries
    {
        var entry: ZipFixtureEntry
        entry.name  = item.path
        entry.plain = expect Archive.Zip.loadEntry(source, item)
        if item.path == part
        {
            var text = String.from(cast(string, entry.plain.toSlice()))
            text.replace(before, after)
            entry.plain.clear()
            entry.plain.add(text.toSlice())
        }

        entry.packed = entry.plain
        entries.add(entry)
    }

    let path = Gui.Testing.tempFilePath("scope-word-styles-", ".docx")
    discard expect File.writeAllBytes(path, buildZipEntries(entries.toSlice()).toSlice())
    return path
}

// Broken optional styles cannot hide a healthy main document or silently claim full formatting.
#test
{
    let path = wordStyleVariant("word/styles/reading.xml", "</w:styles>", "")
    defer discard catch File.delete(path)
    let document = expect Docx.Document.load(path)
    Swag.require(document.stylesSimplified)
    Swag.require(Utf8.contains(document.html, "A little room for words"))
    Swag.require(Utf8.contains(document.html, "Keep the words together."))
    Swag.require(Utf8.contains(document.details(), Docx.texts().ui_StylesSimplified))
}

// A missing style keeps the body readable and exposes the approximation in the details band.
#test
{
    let path = wordStyleVariant("word/document.xml", "w:val=\"ReadingTitle\"", "w:val=\"MissingTitle\"")
    defer discard catch File.delete(path)
    let document = expect Docx.Document.load(path)
    Swag.require(document.stylesSimplified and document.paragraphs == 12)
    Swag.require(Utf8.contains(document.html, "A little room for words"))
}

// Hidden run text never enters the rendered document; a direct reset restores ordinary content.
#test
{
    var theme = Package.OfficeTheme.defaults()
    var run   = readWordRun("<rPr><vanish/></rPr>", &theme)
    var html: String
    run.appendHtml(&html, "Hidden editing note")
    Swag.require(html.isEmpty())
    let visible = readWordRun("<vanish val=\"0\"/>", &theme)
    run.overlay(&visible)
    run.appendHtml(&html, "Visible body")
    Swag.require(Utf8.contains(html, "Visible body"))
}

// Automatic text follows the authored paper's contrast, including dark Word pages.
#test
{
    var entries: [2] ZipFixtureEntry
    entries[0].name = "word/document.xml"
    entries[0].plain.add("""<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:background w:color="000000"/><w:body><w:p><w:r><w:rPr><w:color w:val="auto"/></w:rPr><w:t>A dark page stays readable.</w:t></w:r></w:p></w:body></w:document>""")
    entries[0].packed = entries[0].plain
    entries[1].name   = "word/_rels/document.xml.rels"
    entries[1].plain.add("<Relationships/>")
    entries[1].packed = entries[1].plain
    let path = Gui.Testing.tempFilePath("scope-word-paper-", ".docx")
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, buildZipEntries(entries[0 until entries.count]).toSlice())
    let document = expect Docx.Document.load(path)
    Swag.require(document.usePaperColors and document.paperColor == "000000")
    Swag.require(Utf8.contains(document.html, "background-color:#000000;color:#FFFFFF"))
    Swag.require(Utf8.contains(document.html, "color:inherit;"))
    Swag.require(Utf8.contains(document.html, "A dark page stays readable."))
}
