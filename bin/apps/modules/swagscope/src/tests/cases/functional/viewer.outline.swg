#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing, Viewers

// Heading whitespace is normalized as Unicode, without consuming UTF-8 continuation bytes.
#test
{
    let fileName = Testing.tempFilePath("scope-outline-unicode-", ".md")
    let title    = "Guide \u00E0 \u00C5ngstr\u00F6m \u0120 \u0145 \u4E20 \U0001F680"
    discard expect File.writeAllBytes(fileName, Format.toString("# %\n", title))
    defer discard catch File.delete(fileName)
    var host: HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(MarkdownText.viewerPlugin(), &host.root, fileName)
    let zoom    = assume cast(*MarkdownText.ZoomButton, session.info!.children[0])
    let outline = unwrap zoom.outline
    outline.startMarkdown()
    completeViewerBackgroundLoad(&host, &outline.load)
    Swag.require(outline.rows.count == 1)
    Swag.require(outline.headings[0].title == title)
    Swag.require(Pixel.RichString.plainText(outline.rows[0].items[0]!.name.raw) == title)

    outline.add(" \t\r\n\u00A0\u2003First\t\r\n\u00A0\u2003second \t\u00A0", 2, 1)
    Swag.require(outline.rows[1].items[0]!.name == "First second")
    outline.add(" \t\r\n\u00A0\u2003", 2, 2)
    Swag.require(outline.rows[2].items[0]!.name == "")

    let literal = "<b>Literal</b> <url>address</url> <p1>ink</p>"
    outline.add(literal, 4, 3)
    let display = Pixel.RichString.plainText(outline.rows[3].items[0]!.name.raw)
    display.replace("\u2060", "")
    Swag.require(display == literal)
    Swag.require(outline.rows[3].level == 3)
}

#test
{
    let fileName = Testing.tempFilePath("scope-outline-", ".html")
    discard expect File.writeAllBytes(fileName, "<html><body><h1>Guide</h1><div style='height:800px'></div><h3>Details</h3><div style='height:800px'></div></body></html>")
    defer discard catch File.delete(fileName)
    var host: HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(Html.viewerPlugin(), &host.root, fileName)
    let view    = assume cast(*Html.Panel, session.view)
    defer view.setZoom(100)
    for 128 where session.isLoading!() do
        host.fireTimers()
    let outline = assume cast(*DocumentOutline, session.sidePanel!.children[0])
    Swag.require(outline.rows.count == 2 and outline.rows[0].level == 0 and outline.rows[1].level == 2)
    outline.list.selectLine(1)
    let scroll = assume cast(*ScrollWnd, view.view.children[0])
    Swag.require(scroll.scrollPosition().y > 700)
    view.setZoom(150)
    Swag.require(outline.rows.count == 2 and outline.list.selectedLine() == outline.rows[1])
    outline.list.selectLine(0)
    Swag.require(scroll.scrollPosition().y < 2)
}

// A long outline remains reachable with the wheel after the panel itself fills its viewport.
#test
{
    let fileName = Testing.tempFilePath("scope-outline-scroll-", ".md")
    var source: String
    for index in 40 do
        source += Format.toString("# Section %\n\n", index)
    discard expect File.writeAllBytes(fileName, source.toString())
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(880, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)

    let zoom    = assume cast(*MarkdownText.ZoomButton, window.currentInfo!.children[0])
    let outline = unwrap zoom.outline
    outline.startMarkdown()
    completeViewerBackgroundLoad(&host, &outline.load)
    outline.toggle.setChecked(true)
    outline.toggle.sigCheckedChanged.call(outline.toggle)
    window.applyLayout()

    let scroll = outline.list.scrollWnd
    Swag.require(outline.rows.count == 40)
    Swag.require(scroll.scrollSize.y > scroll.paddedClientRect().height)
    let point = scroll.localToSurface(scroll.clientRect().center())
    host.mouseWheel(point, -120)
    Swag.require(scroll.scrollTarget().y > 0)
}

// Its caption glyph and shortcut open the same panel while focus is inside the outline.
#test
{
    let fileName = Testing.tempFilePath("scope-outline-action-", ".md")
    discard expect File.writeAllBytes(fileName, "# Guide\n\n## Last section\n\nDone.\n")
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(880, 560)
    shipFrame(&host)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    window.applyLayout()

    let outline = unwrap (assume cast(*MarkdownText.ZoomButton, window.currentInfo!.children[0])).outline
    let caption = window.outlineCaptionButton
    Swag.require(caption.isLocallyVisible() and caption.icon.isValid())
    Swag.require(window.currentSidePanelButton!.id == OutlineToggleId)

    host.click(caption.surfaceRect().center())
    Swag.require(outline.toggle.isChecked and window.mainSplitter.isPaneVisible(2),
                 Format.toString("caption=%, checked=%, pane=%", caption.surfaceRect(), outline.toggle.isChecked, window.mainSplitter.isPaneVisible(2)).toString())
    host.focus(outline.list.listView)
    host.keyPress(.O, Input.KeyModifiers.Control | .Shift)
    Swag.require(not outline.toggle.isChecked and not window.mainSplitter.isPaneVisible(2))
}

#test
{
    var host: HeadlessHost
    host.setup(640, 360)
    let path    = Path.combine(testSourceRoot(#curlocation), "datas/document-outline.pdf")
    var session = openTestViewer(PdfDocument.viewerPlugin(), &host.root, path)
    let view    = assume cast(*PdfDocument.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    let outline = unwrap view.outline
    Swag.require(outline.rows.count == 4 and outline.rows[1].level == 1 and not outline.rows[0].canExpand())
    view.pdfView.setZoom(1)
    outline.list.selectLine(1)
    Swag.require(view.pdfView.pageIndex == 1)
    outline.list.selectLine(0)
    Swag.require(view.pdfView.pageIndex == 0)
    outline.list.selectLine(3)
    Swag.require(view.pdfView.pageIndex == 0)
}
