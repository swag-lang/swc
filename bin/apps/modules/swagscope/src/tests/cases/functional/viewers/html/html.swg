#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func htmlViewerFixturePath()->String => Path.combine(scopeTestDataDirectory(), "viewer.html")

// A generated handbook exercises navigation and search inside a long, structured reading page.
#test
{
    let fileName = scopeTestDataPath("viewer.field-guide.html")
    let source   = expect File.readAllText(fileName)

    var host: Testing.HeadlessHost
    host.setup(820, 560)
    var result = openTestViewer(Html.viewerPlugin(), &host.root, fileName)
    finishHtmlViewer(&host, &result)

    let phrase = "Standard equipment checklist"
    let offset = source.indexOf(phrase)
    Swag.require(offset != Swag.U64.Max)
    let match = Viewer.SearchMatch{offset: offset, length: phrase.count}
    Swag.require(result.revealMatch!(match, phrase))
    var bounds: Math.Rectangle
    Swag.require(result.searchBounds!(match, &bounds) and not bounds.isEmpty())
}

func finishHtmlViewer(host: *Testing.HeadlessHost, result: *ViewerSession)
{
    Swag.require(result.isLoading != null)
    let isLoading = result.isLoading

    var attempts: u32
    while isLoading() and attempts < 100
    {
        Threading.Thread.sleep(5'ms)
        host.app.runFrame()
        attempts += 1
    }

    Swag.require(not result.isLoading())
}

// The reader sheet is reversible, keeps the rendered DOM alive, and retains fragment navigation.
#test
{
    let fileName = scopeTestDataPath("viewer.field-guide.html")
    let source   = expect File.readAllText(fileName)
    var host: Testing.HeadlessHost
    host.setup(820, 560)
    var result = openTestViewer(Html.viewerPlugin(), &host.root, fileName)
    finishHtmlViewer(&host, &result)

    let panel = assume cast(*Html.Panel, result.view)
    let offset = source.indexOf("Safety and access")
    Swag.require(offset != Swag.U64.Max and panel.view.revealFileOffset(offset, "Safety and access"))
    let readingOffset = panel.view.readingOffset()
    Swag.require(readingOffset != Swag.U64.Max)

    panel.view.setReaderMode(true)
    Swag.require(panel.view.isReaderMode() and panel.view.readingOffset() == readingOffset)
    Swag.require(panel.view.navigateToFragment("#contacts") and panel.view.isReaderMode())
    panel.view.setReaderMode(false)
    Swag.require(not panel.view.isReaderMode() and panel.view.navigateToFragment("#sampling"))
}

// The viewer remains a thin ABI adapter around the reusable GUI control.
#test
{
    let fileName = htmlViewerFixturePath()

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    var result = openTestViewer(Html.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.require(result.view != null)
    Swag.require(result.commands == null and
                 result.info != null and
                 result.revealMatch != null and
                 result.searchBounds != null and
                 result.clearSearch != null and
                 result.isLoading != null)
    Swag.require(result.isLoading())
    Swag.require(Utf8.contains(result.details, "HTML"))
    let view = assume cast(*Html.Panel, result.view)
    finishHtmlViewer(&host, &result)
    Swag.require(view.children.count == 1 and view.children[0] == cast(*Wnd, view.view))
    Swag.require(result.view != null and
                 result.revealMatch != null and
                 result.searchBounds != null and
                 result.clearSearch != null)

    var zoomIn = KeyEvent{kind: .Pressed, key: .OemPlus, modifiers: .Control}
    Swag.require(view.hookOnChildEvent!(view.view, &zoomIn))
    Swag.require(view.zoomPercent == 125 and view.view.documentStyle.bodyFontSize == 20)
    var resetZoom = KeyEvent{kind: .Pressed, key: .D0, modifiers: .Control}
    Swag.require(view.hookOnChildEvent(view.view, &resetZoom) and view.zoomPercent == 100)

    let source = expect File.readAllText(fileName)
    let offset = source.indexOf("immutable")
    Swag.require(offset != Swag.U64.Max)
    let match    = Viewer.SearchMatch{offset: offset, length: "immutable".count}
    let revealed = result.revealMatch(match, "immutable")
    Swag.require(revealed)
    var bounds: Math.Rectangle
    Swag.require(result.searchBounds(match, &bounds) and not bounds.isEmpty())

    let oldTip = String.from(view.zoomLabel.toolTip)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(view.zoomLabel.toolTip == Html.texts().ui_ZoomMenu)
    Swag.require(view.zoomPercent == 100 and result.searchBounds(match, &bounds))
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
    Swag.require(view.zoomLabel.toolTip == oldTip)
    result.clearSearch()
}

// The zoom of the rendered document stands in the window's line of readings at its fixed width.
#test
{
    var host: Testing.HeadlessHost
    host.setup(820, 560)

    with let readings = ViewerReadingLine.create(&host.root)
    {
        .dockStyle = .Bottom
    }

    var result = openTestViewer(Html.viewerPlugin(), &host.root, htmlViewerFixturePath(), infoParent: readings)
    Swag.require(result.view != null and result.info != null)
    let view = assume cast(*Html.Panel, result.view)
    Swag.require(result.info.preferredSize.x == Viewer.ZoomSlotWidth)
    finishHtmlViewer(&host, &result)
    Swag.require(result.info != null)
    view.dockStyle = .Center

    host.root.applyLayout()
    Swag.require(result.info.parent == cast(*Wnd, readings) and result.info.position.width > 0)
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)
}

// The information sheet names the encoding the page is really read with and what decided it,
// in the reader's language: a legacy page is not reported as UTF-8.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    let fileName = Gui.Testing.tempFilePath("scope-html-legacy-", ".html")
    defer discard catch File.delete(fileName)
    var legacy: String = "<html><head><meta charset=\"iso-8859-1\"></head><body><p>caf"
    legacy.append(0xE9'u8)
    legacy += "</p></body></html>"
    expect File.writeAllBytes(fileName, legacy.bytes())

    var legacyResult = openTestViewer(Html.viewerPlugin(), &host.root, fileName)
    let legacyView   = assume cast(*Html.Panel, legacyResult.view)
    finishHtmlViewer(&host, &legacyResult)
    Swag.require(legacyView.encodingText() == "Windows-1252 · declared by the page")

    // Without a label or a mark, the bytes are all there is to decide from.
    let bareName = Gui.Testing.tempFilePath("scope-html-bare-", ".html")
    defer discard catch File.delete(bareName)
    expect File.writeAllBytes(bareName, "<html><body><p>plain page</p></body></html>")

    var result = openTestViewer(Html.viewerPlugin(), &host.root, bareName)
    let view   = assume cast(*Html.Panel, result.view)
    finishHtmlViewer(&host, &result)
    Swag.require(view.encodingText() == "UTF-8 · detected from the bytes")

    // A byte-order mark answers before anything the page says.
    let markedName = Gui.Testing.tempFilePath("scope-html-marked-", ".html")
    defer discard catch File.delete(markedName)
    var marked: Array'u8
    marked.add([0xEF'u8, 0xBB, 0xBF])
    marked.add("<html><body><p>marked page</p></body></html>")
    expect File.writeAllBytes(markedName, marked.toSlice())

    var markedResult = openTestViewer(Html.viewerPlugin(), &host.root, markedName)
    let markedView   = assume cast(*Html.Panel, markedResult.view)
    finishHtmlViewer(&host, &markedResult)
    Swag.require(markedView.encodingText() == "UTF-8 · byte-order mark")

    expect host.app.setLanguage("fr")
    Swag.require(legacyView.encodingText() == "Windows-1252 · déclaré par la page")
    Swag.require(view.encodingText() == "UTF-8 · déduit des octets")
    Swag.require(markedView.encodingText() == "UTF-8 · indicateur d’ordre des octets")
}

// File-open failures cross the viewer boundary instead of becoming viewer-specific content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)

    let fileName = Gui.Testing.tempFilePath("scope-html-missing-", ".html")
    var result   = openTestViewer(Html.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.require(result.view == null and result.commands == null)
    Swag.require(not result.failureReason.isEmpty())
}

// The information sheet gives what a page says of itself in its head.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-html-facts-", ".html")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "<html lang=\"en\"><head><title>Release notes</title><meta name=\"description\" content=\"What changed\"></head><body><p>Text</p></body></html>")
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, false)
    window.toggleInformation()
    host.pump()
    let text = window.infoSheet.text()
    Swag.require(Utf8.contains(text, "Title\nRelease notes") and
                 Utf8.contains(text, "Language\nen") and
                 Utf8.contains(text, "Description\nWhat changed"),
                 text)
}

// A page followed from a link brings its own head to the information sheet, while a loaded page
// laid out again keeps the head it was read with.
#test
{
    let firstName  = Gui.Testing.tempFilePath("scope-html-first-", ".html")
    let secondName = Gui.Testing.tempFilePath("scope-html-second-", ".html")
    defer discard catch File.delete(firstName)
    defer discard catch File.delete(secondName)
    let secondLink = Path.fileName(secondName) orelse ""
    discard expect File.writeAllText(firstName, Format.toString("<html><head><title>First</title></head><body><p><a href=\"%\">Onward</a></p></body></html>", secondLink).toString())
    discard expect File.writeAllText(secondName, "<html><head><title>Second</title></head><body><p>Arrived</p></body></html>")

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, firstName, false)
    let panel  = assume cast(*Html.Panel, window.currentView)
    Swag.require(panel.factsFinal and panel.shownFacts.title == "First")

    // The zoom is shared by every page opened after this one.
    panel.setZoom(150)
    Swag.require(panel.factsFinal and panel.shownFacts.title == "First")
    panel.setZoom(100)

    Swag.require(panel.view.findText("Onward"))
    var bounds: Math.Rectangle
    Swag.require(panel.view.searchMatchRect(&bounds))
    panel.view.clearSearch()
    host.click(Math.Point{bounds.x + bounds.width / 2, bounds.y + bounds.height / 2})
    for 100 where panel.view.isLoading()
    {
        Threading.Thread.sleep(5'ms)
        host.app.runFrame()
    }

    Swag.require(panel.factsFinal and panel.shownFacts.title == "Second", panel.shownFacts.title)
}
