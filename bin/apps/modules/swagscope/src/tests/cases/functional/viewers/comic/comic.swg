#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// Comic pages follow natural filename order and leave non-image archive members out of navigation.
#test
{
    let fileName = scopeTestDataPath("viewer.comic.cbz")
    let book     = expect Comic.Book.load(fileName)
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
    let view   = assume cast(*Comic.Panel, window.instances[window.activeChoiceIndex].view)
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
    Swag.require(view.pageLabel.name.text == "2 / 2")
}

// The page readout accepts a one-based page number and rejects values outside the book.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.comic.cbz"), false)
    let view   = assume cast(*Comic.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.goToTypedPage("0") == false)
    Swag.require(view.goToTypedPage("3") == false)
    Swag.require(view.goToTypedPage("page") == false)
    Swag.require(view.goToTypedPage("2"))
    Swag.require(view.activePage == 1 or view.pendingPage == 1)
    Swag.drainWork()
    host.pump()
    Swag.require(view.activePage == 1 and view.pageLabel.text() == "2 / 2")
}

// Horizontal keys follow Western order by default and reverse for manga reading.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.comic.cbz"), false)
    let view   = assume cast(*Comic.Panel, window.instances[window.activeChoiceIndex].view)

    view.rightToLeft = true
    var nextPage = KeyEvent{kind: .Pressed, key: .Left}
    view.sendEvent(&nextPage)
    Swag.require(view.activePage == 1)

    var previousPage = KeyEvent{kind: .Pressed, key: .Right}
    view.sendEvent(&previousPage)
    Swag.require(view.activePage == 0 or view.pendingPage == 0)
    Swag.drainWork()
    host.pump()
    Swag.require(view.activePage == 0)
}

// Nested image paths and mixed PNG/JPEG pages still follow natural archive order.
#test
{
    let book = expect Comic.Book.load(scopeTestDataPath("viewer.nested.cbz"))
    Swag.require(book.pages.count == 2)
    Swag.require(book.archive.entries[book.pages[0]].path == "chapter/2.png")
    Swag.require(book.archive.entries[book.pages[1]].path == "chapter/10.jpg")
}

// A licensed short comic keeps all three real pages readable in archive order.
#test
{
    let fileName = scopeTestDataPath("viewer.peppercarrot.ep01.cbz")
    let book     = expect Comic.Book.load(fileName)
    Swag.require(book.pages.count == 3)
    Swag.require(book.archive.entries[book.pages[0]].path == "01.jpg")
    Swag.require(book.archive.entries[book.pages[2]].path == "03.jpg")

    let entry = &book.archive.entries[book.pages[2]]
    let bytes = expect Archive.Zip.loadEntry(fileName, entry)
    let image = expect Image.decode(entry.path, bytes.toSlice())
    Swag.require(image.isValid())
}

// A complete fifteen-page comic opens at the beginning and jumps to its final page on demand.
#test
{
    var host: HeadlessHost
    let fileName = scopeTestDataPath("viewer.peppercarrot.ep36.cbz")
    let window   = framedViewerWindow(&host, fileName, false)
    let view     = assume cast(*Comic.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.book.pages.count == 15 and view.activePage == 0)
    Swag.require(view.book.archive.entries[view.book.pages[0]].path == "01.jpg")
    Swag.require(view.book.archive.entries[view.book.pages[14]].path == "15.jpg")

    Swag.require(view.goToTypedPage("15"))
    Swag.drainWork()
    host.pump()
    Swag.require(view.activePage == 14 and view.pageLabel.text() == "15 / 15")
}
