#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing, Viewers

// Pins the PDF controls inside the application's real line of readings. The line measures viewer
// contributions before positioning them, so every fixed page and zoom cell must report the width
// its docking pass will consume.
#[Swag.TestTag("golden")]
#test
{
    let fileName = createPdfFixture()
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(ViewerWindow.MinWidth, ViewerReadingLine.Height + ViewerWindow.BarHeight)
    host.root.backgroundStyle = .View
    host.root.padding         = {8, 0, 8, 0}

    let document = Wnd.create'Wnd(&host.root)
    document.hide()
    let foot   = createTestViewerFoot(&host.root)
    let layout = foot.readings
    layout.details.setText("PDF · 2 pages")

    var result = openTestViewer(PdfDocument.viewerPlugin(), document, fileName, commandParent: foot.commands, infoParent: layout)
    Swag.require(result.view != null and result.info != null)
    let view = assume cast(*PdfDocument.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    host.root.applyLayout()
    layout.computeLayout()
    standTestCommands(foot, unwrap result.commands)

    Swag.require(result.info.position.width == Viewer.ZoomSlotWidth)
    Swag.require(view.previousButton.position.right() <= view.pageLabel.position.x)
    Swag.require(view.pageLabel.position.right() <= view.nextButton.position.x)
    Swag.require(view.nextButton.surfaceRect().bottom() <= view.zoomLabel.surfaceRect().y)

    var image = host.render(&host.root)
    assertScopeImageGolden(&image, "viewer.pdf.info-bar")
}

// A document is paper standing on the ground of the window, its outline in the margin beside the
// page with the part being read on an Arc rule.
#[Swag.TestTag("golden")]
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-pdf-page-", ".pdf")
    defer discard catch File.delete(fileName)
    var document = Pdf.Document.create()
    for title in ["Introduction", "Results"]
    {
        var page = Pdf.Page.create(595, 842)
        page.addText(title, 72, 72, 28, Color.fromArgb(Argb.Black))
        document.addPage(#move page)
    }

    expect document.save(fileName)

    var host: HeadlessHost
    host.setup(960, 640)
    shipFrame(&host)
    host.theme.setLight()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.resize(960, 640)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)
    let view = assume cast(*PdfDocument.Panel, window.currentView)
    completeViewerBackgroundLoad(&host, &view.load)

    // The writer of the fixture records no outline: the parts are given as a reader found them.
    for title, page in ["Introduction", "Results", "Method", "Appendices"] do
        view.bookmarks.add(Pdf.OutlineEntry{title: title, level: 1, pageIndex: Math.min(page, 1)})
    view.fillMargin()
    window.applyLayout()
    view.placeMargin()
    host.settleAnimations(window, 4)

    let margin = unwrap view.margin
    Swag.require(margin.isLocallyVisible() and margin.titles.count == 4 and margin.active == 0)
    Swag.require(margin.position.right() <= view.pdfView.pageColumn().x)
    var image = host.render(window)
    assertScopeImageGolden(&image, "viewer.pdf.page.paper")
}
