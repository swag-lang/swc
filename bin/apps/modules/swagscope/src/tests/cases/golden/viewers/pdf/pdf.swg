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

    var result = openTestViewer(PdfDocument.viewerPlugin(), document, fileName, commandParent: foot.commands, infoParent: layout)
    Swag.require(result.view != null and result.info != null)
    let view = assume cast(*PdfDocument.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    layout.details.setText(view.details)
    host.root.applyLayout()
    layout.computeLayout()
    standTestCommands(foot, unwrap result.commands)

    Swag.require(result.info.position.width == Viewer.ZoomSlotWidth + themeActionButtonSize(view.themeMetrics()))
    Swag.require(view.previousButton.position.right() <= view.pageLabel.position.x)
    Swag.require(view.pageLabel.position.right() <= view.nextButton.position.x)
    Swag.require(view.nextButton.surfaceRect().bottom() <= view.zoomLabel.surfaceRect().y)

    var image = host.render(&host.root)
    assertScopeImageGolden(&image, "viewer.pdf.info-bar")
}

// A document is paper standing on the ground of the window; its outline opens only on demand.
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

    window.applyLayout()
    host.settleAnimations(window, 4)

    Swag.require(not window.currentSidePanelHost!.isLocallyVisible())
    var image = host.render(window)
    assertScopeImageGolden(&image, "viewer.pdf.page.paper")
}

// The page gallery shares the document canvas. Both the scanned sheet and the text page
// keep their own proportions, with a frame marking the page being read.
#[Swag.TestTag("golden")]
#test
{
    var host: HeadlessHost
    let workspace = testWorkspace(&host, width: 920, height: 550)
    defer host.shutdown()
    let window = workspace.primary
    let path   = isolatedScopeFixture("viewer.mixed-text-scan.pdf")
    defer discardIsolatedScopeFixture(path)
    window.openFile(path, remember: false)
    completeQueuedViewerFile(&host, window)
    let view = assume cast(*PdfDocument.Panel, window.currentView)
    view.openPages()
    settlePdfGallery(&host, view)
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "viewer.pdf.pages.encre")
}

// A compact document with authored bookmarks opens directly to its searchable outline.
#[Swag.TestTag("golden")]
#test
{
    var host: HeadlessHost
    let workspace = testWorkspace(&host, light: true, width: 820, height: 470)
    defer host.shutdown()
    let window = workspace.primary
    let path   = isolatedScopeFixture("document-outline.pdf")
    defer discardIsolatedScopeFixture(path)
    window.openFile(path, remember: false)
    completeQueuedViewerFile(&host, window)
    window.sendCommandEvent(ViewerCommands.Outline)
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "viewer.pdf.bookmarks.paper")
}
