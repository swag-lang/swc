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

// An EPUB starts with its first chapter and can move to the next one.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.epub"), true)
    let view = assume cast(*Epub.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.book.chapters.count == 2 and view.chapter == 0)
    let embedded = assume cast(*EmbeddedViewer, view.embedded)
    let chapter = assume cast(*Html.Panel, embedded.currentView)
    Swag.require(not chapter.band.isLocallyVisible())
    view.turn(1)
    Swag.require(view.chapter == 1 and view.chapterLabel.name.raw == "2 / 2")
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
}

// A root package path cannot escape its archive.
#test
{
    var loadError: Swag.Error
    discard catch Epub.Book.load(scopeTestDataPath("viewer.damaged.epub")) as loadError
    Swag.require(loadError.value() is Errors.InvalidFormatError)
}
