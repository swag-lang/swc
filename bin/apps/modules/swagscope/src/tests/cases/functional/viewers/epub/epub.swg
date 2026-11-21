#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// The package spine, not ZIP order or manifest order, determines the chapters.
#test
{
    let book = expect Epub.Book.load(scopeTestDataPath("viewer.epub"))
    Swag.require(book.chapters.count == 2)
    Swag.require(book.chapters[0].path == "OEBPS/one.xhtml")
    Swag.require(book.chapters[1].path == "OEBPS/two.xhtml")
    Swag.require(File.exists(Path.combine(book.root, book.chapters[0].path)))
}

// Book and current-chapter scopes use the shared search callbacks and keep source offsets for jumps.
#test
{
    var host: HeadlessHost
    let window  = framedViewerWindow(&host, scopeTestDataPath("viewer.navigation.epub"), true)
    let view    = assume cast(*Epub.Panel, window.instances[window.activeChoiceIndex].view)
    let session = &window.instances[window.activeChoiceIndex]
    Swag.require(session.collectMatches != null and session.revealMatch != null and session.searchBounds != null)
    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(session.collectMatches, "Paragraph 0.", &matches)

    Swag.require(matches.count == 2)
    Swag.require(matches[0].major == 0 and matches[1].major == 1)
    Swag.require(matches[0].length == "Paragraph 0.".count and matches[1].length == "Paragraph 0.".count)
    Swag.require(view.chapter == 0 and view.revealSearchMatch(matches[1], "Paragraph 0."))
    Swag.require(view.chapter == 1)

    matches.clear()
    collectViewerMatches(session.collectMatches, "chapter: Paragraph 0.", &matches)
    Swag.require(matches.count == 1 and matches[0].major == 1)
    matches.clear()
    collectViewerMatches(session.collectMatches, "chapitre: Paragraph 0.", &matches)
    Swag.require(matches.count == 1 and matches[0].major == 1)
    matches.clear()
    collectViewerMatches(session.collectMatches, "book: Paragraph 0.", &matches)
    Swag.require(matches.count == 2 and matches[0].major == 0 and matches[1].major == 1)
    matches.clear()
    collectViewerMatches(session.collectMatches, "livre: Paragraph 0.", &matches)
    Swag.require(matches.count == 2 and matches[0].major == 0 and matches[1].major == 1)

    var presentation: Viewer.SearchPresentation
    view.describeSearch(&presentation)
    Swag.require(Utf8.contains(presentation.toolTip, "chapter: text") and Utf8.contains(presentation.toolTip, "book: text"))
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    view.describeSearch(&presentation)
    Swag.require(Utf8.contains(presentation.toolTip, "chapitre: texte") and Utf8.contains(presentation.toolTip, "livre: texte"))
}

// An EPUB starts with its first chapter and can move to the next one.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.epub"), true)
    let view   = assume cast(*Epub.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.book.chapters.count == 2 and view.chapter == 0)
    Swag.require(view.view != null and view.contents.count == 2)
    view.turn(1)
    Swag.require(view.chapter == 1 and view.chapterLabel.name.text == "2 / 2")
}

// A nested package root and chapter path remain inside the extracted book.
#test
{
    let book = expect Epub.Book.load(scopeTestDataPath("viewer.nested.epub"))
    Swag.require(book.chapters.count == 1 and book.chapters[0].path == "OPS/chapters/part.xhtml")
    Swag.require(File.exists(Path.combine(book.root, book.chapters[0].path)))
}

// A published, public-domain book uses a larger, illustrated EPUB 3 package.
#test
{
    let book = expect Epub.Book.load(scopeTestDataPath("viewer.christmas-carol.epub"))
    Swag.require(book.chapters.count == 4)
    Swag.require(Utf8.contains(book.chapters[0].path, "wrap0000.xhtml"))
    Swag.require(Utf8.contains(book.chapters[1].path, "46-h-0.htm.xhtml"))
    let chapter = expect File.readAllText(Path.combine(book.root, book.chapters[1].path))
    Swag.require(Utf8.contains(chapter, "Scrooge"))

    // Its Dublin Core metadata names it, and the information sheet says so.
    Swag.require(Utf8.startsWith(book.metadata.title.toString(), "A Christmas Carol in Prose"), book.metadata.title)
    Swag.require(book.metadata.creators == "Charles Dickens" and book.metadata.language == "en", book.metadata.creators)

    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.christmas-carol.epub"), false)
    let view   = assume cast(*Epub.Panel, window.instances[window.activeChoiceIndex].view)
    let sheet  = InfoSheet.create(&host.root)
    view.describeInformation(sheet)
    let text = sheet.text()
    Swag.require(Utf8.contains(text, "4 chapters") and
                 Utf8.contains(text, "Author\nCharles Dickens") and
                 Utf8.contains(text, "Language\nen"),
                 text)
}

// A spine reference names the first manifest item with its identifier; one naming no item, or an
// item that is not a document, makes the book unreadable.
#test
{
    func loadSpine(spine: string)->Swag.Error
    {
        const Container = """<?xml version="1.0"?>
<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>"""
        const Manifest  = """<item id="a" href="first.xhtml" media-type="application/xhtml+xml"/>
<item id="a" href="second.xhtml" media-type="application/xhtml+xml"/>
<item id="p" href="picture.png" media-type="image/png"/>"""
        let package = Format.toString("<package><manifest>%</manifest><spine>%</spine></package>", Manifest, spine)
        let page    = "<html><body>page</body></html>"
        let bytes   = storedZipBytes([{name: "mimetype", bytes: cast(const [..] u8, "application/epub+zip")},
                                      {name: "META-INF/container.xml", bytes: cast(const [..] u8, Container)},
                                      {name: "book.opf", bytes: package.toSlice()},
                                      {name: "first.xhtml", bytes: cast(const [..] u8, page)},
                                      {name: "second.xhtml", bytes: cast(const [..] u8, page)},
                                      {name: "picture.png", bytes: cast(const [..] u8, page)}])
        let fileName = Gui.Testing.tempFilePath("scope-epub-spine-", ".epub")
        defer discard catch File.delete(fileName)
        expect File.writeAllBytes(fileName, bytes.toSlice())

        var loadError: Swag.Error
        catch
        {
            let book = try Epub.Book.load(fileName)
            Swag.require(book.chapters.count == 2 and
                         book.chapters[0].path == "first.xhtml" and
                         book.chapters[1].path == "first.xhtml")
        } as loadError
        return loadError
    }

    Swag.require(loadSpine("""<itemref idref="a"/><itemref idref="a"/>""").value() == null)
    Swag.require(loadSpine("""<itemref idref="a"/><itemref idref="b"/>""").value() is Errors.InvalidFormatError)
    Swag.require(loadSpine("""<itemref idref="p"/>""").value() is Errors.UnsupportedFormatError)
}

// A root package path cannot escape its archive.
#test
{
    var loadError: Swag.Error
    discard catch Epub.Book.load(scopeTestDataPath("viewer.damaged.epub")) as loadError
    Swag.require(loadError.value() is Errors.InvalidFormatError)
}

// The Explorer preview of a book is the cover its package names, decoded from the archive and
// fitted; a book that names no cover has none to give.
#test
{
    let cover = expect Epub.loadCover(scopeTestDataPath("viewer.christmas-carol.epub"))
    Swag.require(Utf8.endsWith(cover.path.toString(), "_cover.jpg") and cover.bytes.count > 0)

    let plugin = Epub.viewerPlugin()
    let image  = expect plugin.thumbnail!(scopeTestDataPath("viewer.christmas-carol.epub"), 128)
    Swag.require(image.isValid() and Math.max(image.width, image.height) == 128 and image.height > image.width)

    let none = expect Epub.loadCover(scopeTestDataPath("viewer.epub"))
    Swag.require(none.bytes.isEmpty() and none.path.isEmpty())
    Swag.require(not (expect plugin.thumbnail(scopeTestDataPath("viewer.epub"), 128)).isValid())
}
