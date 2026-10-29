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
    Swag.assert(outline.rows.count == 1)
    Swag.assert(outline.headings[0].title == title)
    Swag.assert(outline.rows[0].items[0]!.name == title)

    outline.add(" \t\r\n\u00A0\u2003First\t\r\n\u00A0\u2003second \t\u00A0", 2, 1)
    Swag.assert(outline.rows[1].items[0]!.name == "First second")
    outline.add(" \t\r\n\u00A0\u2003", 2, 2)
    Swag.assert(outline.rows[2].items[0]!.name == "")
}

#test
{
    let fileName = Testing.tempFilePath("scope-outline-", ".html")
    discard expect File.writeAllBytes(fileName, "<html><body><h1>Guide</h1><div style='height:800px'></div><h2>Details</h2><div style='height:800px'></div></body></html>")
    defer discard catch File.delete(fileName)
    var host: HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(Html.viewerPlugin(), &host.root, fileName)
    let view    = assume cast(*Html.Panel, session.view)
    defer view.setZoom(100)
    for 128 where session.isLoading!() do
        host.fireTimers()
    let outline = assume cast(*DocumentOutline, session.sidePanel!.children[0])
    Swag.assert(outline.rows.count == 2)
    outline.list.selectLine(1)
    let scroll = assume cast(*ScrollWnd, view.view.children[0])
    Swag.assert(scroll.scrollPosition().y > 700)
    view.setZoom(150)
    Swag.assert(outline.rows.count == 2 and outline.list.selectedLine() == outline.rows[1])
    outline.list.selectLine(0)
    Swag.assert(scroll.scrollPosition().y < 2)
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
    Swag.assert(outline.rows.count == 40)
    Swag.assert(scroll.scrollSize.y > scroll.paddedClientRect().height)
    let point = scroll.localToSurface(scroll.clientRect().center())
    host.mouseWheel(point, -120)
    Swag.assert(scroll.scrollTarget().y > 0)
}

// The panel is hosted at the information edge and exposes the document hierarchy in both languages.
#[Swag.TestTag("golden")]
#test
{
    let previous = MarkdownText.g_ViewerSettings
    defer MarkdownText.g_ViewerSettings = previous
    MarkdownText.g_ViewerSettings = {}
    let fileName = Testing.tempFilePath("scope-outline-", ".md")
    let source   = "# Document guide\n\nAn introduction to this document.\n\n## Getting started\n\nRead the first steps.\n\n### Installation\n\nInstall the application.\n\n### Configuration\n\nChoose your preferences.\n\n## Reference\n\nThe complete reference.\n\n### Commands\n\nThe available commands.\n"
    discard expect File.writeAllBytes(fileName, source)
    defer discard catch File.delete(fileName)
    var host: HeadlessHost
    host.setup(880, 560)
    shipFrame(&host)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    Swag.assert(not window.readingLine.isLocallyVisible())
    Swag.assert(not window.viewerBar.isLocallyVisible())
    let zoom    = assume cast(*MarkdownText.ZoomButton, window.currentInfo!.children[0])
    let outline = unwrap zoom.outline
    Swag.assert(not outline.load.started)
    outline.toggle.setChecked(true)
    outline.toggle.sigCheckedChanged.call(outline.toggle)
    completeViewerBackgroundLoad(&host, &outline.load)
    Swag.assert(outline.rows.count == 6 and outline.list.lineCount() == 6)
    window.applyLayout()
    let firstText = outline.list.cellTextRect(0, 0)
    let depths    = [0, 1, 2, 2, 1, 2]
    for row, index in outline.rows
    {
        Swag.assert(row.parent == null and not row.canExpand())
        let text = outline.list.cellTextRect(cast(u32, index), 0)
        Swag.assert(Math.abs(text.x - firstText.x - depths[index] * 16) <= 1)
    }

    outline.list.selectLine(0)
    host.focus(outline.list.listView)
    host.keyPress(.Left)
    Swag.assert(outline.list.lineCount() == 6)
    window.applyLayout()
    let previousScroll = assume cast(*ScrollWnd, window.currentView!.children[0]).scrollPosition().y
    let cell = outline.list.cellTextRect(5, 0)
    host.click(outline.list.listView.localToSurface(cell.center()))
    discard host.render(window)
    Swag.assert(outline.list.selectedLine() == outline.rows[5])
    Swag.assert(assume cast(*ScrollWnd, window.currentView.children[0]).scrollPosition().y > previousScroll)
    outline.list.selectLine(0)
    host.settleAnimations(window, 6)
    let scroll = assume cast(*ScrollWnd, window.currentView.children[0])
    scroll.setScrollPos(0, 150)
    let firstCell = outline.list.cellTextRect(0, 0)
    host.click(outline.list.listView.localToSurface(firstCell.center()))
    host.settleAnimations(window, 6)
    let firstHeading = scroll.view.children[0]
    let inset        = assume cast(*Markdown.View, window.currentView).documentStyle.topInset
    Swag.assert(Math.abs(firstHeading.surfaceRect().y - scroll.surfaceRect().y - inset) < 2)
    let sidePanelHost = unwrap window.currentSidePanelHost
    let card = assume cast(*FloatingPanel, sidePanelHost.children[0])
    let cardTop = card.surfaceRect().y - sidePanelHost.surfaceRect().y
    Swag.assert(cardTop >= window.stripInset() + window.themeMetrics().floating_Inset)
    Swag.assert(card.radius() == window.themeMetrics().corner_Floating)
    var image = host.render(window)
    image.crop(outline.surfaceRect())
    Pixel.Testing.assertImageGolden(&image, "viewer.outline.markdown")
    var whole = host.render(window)
    Pixel.Testing.assertImageGolden(&whole, "viewer.outline.markdown.window")

    var paperHost: HeadlessHost
    paperHost.setup(880, 560)
    shipFrame(&paperHost)
    paperHost.theme.setLight()
    let paperWindow = ViewerWindow.create(&paperHost.surfaceWnd, createViewerPluginRegistry())
    paperWindow.openFile(fileName, remember: false)
    completeQueuedViewerFile(&paperHost, paperWindow)
    let paperZoom = assume cast(*MarkdownText.ZoomButton, paperWindow.currentInfo!.children[0])
    let paperOutline = unwrap paperZoom.outline
    paperOutline.toggle.setChecked(true)
    paperOutline.toggle.sigCheckedChanged.call(paperOutline.toggle)
    completeViewerBackgroundLoad(&paperHost, &paperOutline.load)
    paperWindow.applyLayout()
    var paper = paperHost.render(paperWindow)
    Pixel.Testing.assertImageGolden(&paper, "viewer.outline.markdown.window.paper")
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    window.resize(880, 420)
    window.applyLayout()
    Swag.assert(outline.title.text() == "Plan" and outline.toggle.toolTip == "Plan")
    Swag.assert(outline.list.selectedLine() == outline.rows[0])
    Testing.assertContentFits(outline)
    var french = host.render(window)
    french.crop(outline.surfaceRect())
    Pixel.Testing.assertImageGolden(&french, "viewer.outline.markdown.fr")
    window.setFullScreen(true)
    Swag.assert(not window.currentSidePanelHost.isVisible())
    window.setFullScreen(false)
    Swag.assert(window.currentSidePanelHost.isVisible())
    Swag.assert(not window.readingLine.isLocallyVisible())
    Swag.assert(not window.viewerBar.isLocallyVisible())
}

#test
{
    var host: HeadlessHost
    host.setup(640, 360)
    let path    = Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/document-outline.pdf")
    var session = openTestViewer(PdfDocument.viewerPlugin(), &host.root, path)
    let view    = assume cast(*PdfDocument.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    let outline = unwrap view.outline
    Swag.assert(outline.rows.count == 4 and outline.rows[1].level == 1 and not outline.rows[0].canExpand())
    view.pdfView.setZoom(1)
    outline.list.selectLine(1)
    Swag.assert(view.pdfView.pageIndex == 1)
    outline.list.selectLine(0)
    Swag.assert(view.pdfView.pageIndex == 0)
    outline.list.selectLine(3)
    Swag.assert(view.pdfView.pageIndex == 0)
}
