#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing, Viewers

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
    Swag.require(embedded.choices.count == 1 and embedded.choices[0].key == "image")
    Swag.require(not embedded.viewerMenu.isLocallyVisible())

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
    let pngBytes = expect Archive.Zip.loadEntry(scopeTestDataPath("viewer.nested.cbz"), &book.archive.entries[book.pages[0]])
    let jpgBytes = expect Archive.Zip.loadEntry(scopeTestDataPath("viewer.nested.cbz"), &book.archive.entries[book.pages[1]])
    let pngPage = expect Image.decode("chapter/2.png", pngBytes.toSlice())
    let jpgPage = expect Image.decode("chapter/10.jpg", jpgBytes.toSlice())
    Swag.require(pngPage.width == 96 and pngPage.height == 128)
    Swag.require(jpgPage.width == 96 and jpgPage.height == 128)
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

// A colon and a page number in the lens turn to that page; a page past the last offers nothing.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.comic.cbz"), false)
    let view   = assume cast(*Comic.Panel, window.instances[window.activeChoiceIndex].view)
    window.lens.open(":2")
    host.finishAnimations()
    let section = unwrap window.lens.results.sections[0]
    Swag.require(section.entries[0].title == Format.toString(appStrings().lens_GoToPage, 2))
    section.entries[0].run!()
    window.lens.close()
    host.finishAnimations()
    Swag.require(view.activePage == 1 or view.pendingPage == 1)

    window.lens.open(":3")
    host.finishAnimations()
    Swag.require(window.lens.results.sections.isEmpty())
    window.lens.close()
    host.finishAnimations()
}

// The page rows of the lens stop at the ends of the book, and teach the arrow that turns the way
// the book reads: a manga turns forward with the left one.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.comic.cbz"), false)
    let view   = assume cast(*Comic.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.activePage == 0)

    func pageRows(window: *ViewerWindow, host: *HeadlessHost)->{previousDisabled: bool, nextDisabled: bool, nextKey: String}
    {
        var result: #returntype
        window.lens.open()
        host.finishAnimations()
        defer
        {
            window.lens.close()
            host.finishAnimations()
        }

        for section in window.lens.results.sections
        {
            for &entry in section!.entries
            {
                if entry.title == Comic.texts().ui_Previous
                {
                    result.previousDisabled = entry.disabled
                }
                elif entry.title == Comic.texts().ui_Next
                {
                    result.nextDisabled = entry.disabled
                    result.nextKey      = entry.detail
                }
                elif entry.title == Comic.texts().ui_RightToLeft
                {
                    Swag.require(entry.detail.isEmpty(), "no key toggles the reading direction")
                }
            }
        }

        return result
    }

    let leftToRight = pageRows(window, &host)
    Swag.require(leftToRight.previousDisabled and not leftToRight.nextDisabled)
    Swag.require(leftToRight.nextKey == Input.formatKeyShortcut(.None, .Right))

    view.rightToLeft = true
    let rightToLeft = pageRows(window, &host)
    Swag.require(rightToLeft.nextKey == Input.formatKeyShortcut(.None, .Left))
}

// A `ComicInfo.xml` at the root of the book is read for the information sheet, and a manga that
// says it reads from right to left turns its pages that way from the start.
#test
{
    let page = expect File.readAllBytes(scopeTestDataPath("viewer.png"))
    const Info = """<?xml version="1.0"?>
<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Title>The Potion of Flight</Title>
  <Series>Pepper &amp; Carrot</Series>
  <Number>1</Number>
  <Writer>David Revoy</Writer>
  <Year>2014</Year>
  <Manga>YesAndRightToLeft</Manga>
</ComicInfo>"""
    let bytes    = storedZipBytes([{name: "ComicInfo.xml", bytes: cast(const [..] u8, Info)}, {name: "01.png", bytes: page.toSlice()}, {name: "02.png", bytes: page.toSlice()}])
    let fileName = Gui.Testing.tempFilePath("scope-comic-info-", ".cbz")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, bytes.toSlice())

    let book = expect Comic.Book.load(fileName)
    Swag.require(book.pages.count == 2 and book.info.title == "The Potion of Flight")
    Swag.require(book.info.series == "Pepper & Carrot" and book.info.number == "1" and book.info.rightToLeft)

    // The Explorer cover needs only the page order, and leaves the description unread.
    let cover = expect Comic.Book.loadPages(fileName)
    Swag.require(cover.pages.count == 2 and cover.info.isEmpty() and not cover.info.rightToLeft)

    var host: HeadlessHost
    let window = framedViewerWindow(&host, fileName, false)
    let view   = assume cast(*Comic.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.rightToLeft)
    let sheet = InfoSheet.create(&host.root)
    view.describeInformation(sheet)
    let text = sheet.text()
    Swag.require(Utf8.contains(text, "2 pages"), text)
    Swag.require(Utf8.contains(text, "Title\nThe Potion of Flight") and Utf8.contains(text, "Author\nDavid Revoy"), text)
    Swag.require(Utf8.contains(text, "Series\nPepper & Carrot") and Utf8.contains(text, "Published\n2014"), text)
}
