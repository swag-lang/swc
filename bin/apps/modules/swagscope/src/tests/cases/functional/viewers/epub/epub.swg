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
    view.turn(1)
    Swag.require(view.chapter == 1 and view.chapterLabel.name.raw == "2 / 2")
}
