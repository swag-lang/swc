#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// Comic pages follow natural filename order and leave non-image archive members out of navigation.
#test
{
    let fileName = scopeTestDataPath("viewer.comic.cbz")
    let book = expect Comic.Book.load(fileName)
    Swag.require(book.pages.count == 2)
    Swag.require(book.archive.entries[book.pages[0]].path == "2.png")
    Swag.require(book.archive.entries[book.pages[1]].path == "10.png")

    let page = expect Archive.Zip.loadEntry(fileName, &book.archive.entries[book.pages[0]])
    Swag.require(page.count > 0)
}

// The first image opens as a page, and the reader can turn to the second one.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.comic.cbz"), false)
    let view = assume cast(*Comic.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.book.pages.count == 2 and view.activePage == 0)
    Swag.require(not view.status.isVisible())
    Swag.require(Path.lowercaseExtension(view.previewFile) == ".png", view.previewFile)
    let embedded = assume cast(*EmbeddedViewer, view.embedded)
    Swag.require(embedded.choices[0].key == "image")

    view.turn(1)
    Swag.require(view.activePage == 1)
    Swag.drainWork()
    host.pump()
    Swag.require(not view.status.isVisible())
    Swag.require(view.pageLabel.name.raw == "2 / 2")

}

// Nested image paths and mixed PNG/JPEG pages still follow natural archive order.
#test
{
    let book = expect Comic.Book.load(scopeTestDataPath("viewer.nested.cbz"))
    Swag.require(book.pages.count == 2)
    Swag.require(book.archive.entries[book.pages[0]].path == "chapter/2.png")
    Swag.require(book.archive.entries[book.pages[1]].path == "chapter/10.jpg")
}
