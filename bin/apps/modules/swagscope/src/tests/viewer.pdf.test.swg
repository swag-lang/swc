#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing, Viewers

private func createPdfFixture()->String
{
    let fileName = Gui.Testing.tempFilePath("scope-pdf-", ".pdf")
    var document = Pdf.Document.create()
    document.metadata.title  = "Viewer fixture"
    document.metadata.author = "Swag Scope"
    var first = Pdf.Page.create(320, 220)
    first.addText("PDF viewer", 32, 28, 24, Color.fromArgb(Argb.Black))
    document.addPage(#move first)
    var second = Pdf.Page.create(320, 220)
    second.addText("Second page", 32, 28, 24, Color.fromArgb(Argb.Black))
    document.addPage(#move second)
    expect document.save(fileName)
    return fileName
}

#test
{
    let fileName = createPdfFixture()
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(640, 450, dpiScale: 1.5)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    host.theme.setDark()
    host.notify(.ThemeChanged)

    var result = openTestViewer(PdfDocument.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null and result.commands == null and result.info != null)

    let view = assume cast(*PdfDocument.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    assertViewerInfoButton(view.zoomLabel)
    Swag.assert(view.details == "PDF · 2 pages · 113 × 78 mm · Viewer fixture · Swag Scope")
    Swag.assert(PdfDocument.paperText({842, 595}) == "A4" and PdfDocument.paperText({612, 792}) == "Letter")
    view.resize(640, 420)
    view.applyLayout()

    let pdf = view.pdfView
    Swag.assert(pdf.pageCount() == 2 and pdf.pageIndex == 0)
    Swag.assert(pdf.zoomMode == .FitPage and pdf.pageLayout == .Continuous)

    // Actual size shows one PDF point per 1/96 logical inch; an explicit zoom multiplies the
    // shown size exactly, with the rasterization following the widget internally.
    pdf.actualSize()
    Swag.assert(Math.isEqualEpsilon(pdf.effectiveZoom(), 96.0'f32 / 72.0, 0.001))
    let shown = pdf.effectiveZoom()
    pdf.setZoom(shown * 4)
    Swag.assert(Math.isEqualEpsilon(pdf.effectiveZoom(), shown * 4, 0.001))

    let beforeZoomOut = pdf.effectiveZoom()
    var zoomOut       = KeyEvent{kind: .Pressed, key: .Subtract}
    view.sendEvent(&zoomOut)
    Swag.assert(pdf.effectiveZoom() < beforeZoomOut)
    var actual = KeyEvent{kind: .Pressed, key: .D0, modifiers: .Control}
    view.sendEvent(&actual)
    Swag.assert(Math.isEqualEpsilon(pdf.effectiveZoom(), 96.0'f32 / 72.0, 0.001))

    pdf.zoomToFit()
    Swag.assert(pdf.zoomMode == .FitPage)

    // Fitting the width is the reading scale of a continuous document, and the shortcut the
    // viewer binds for it.
    var fitWidth = KeyEvent{kind: .Pressed, key: .W}
    view.sendEvent(&fitWidth)
    Swag.assert(pdf.zoomMode == .FitWidth)
    pdf.zoomToFit()

    Swag.assert(not view.previousButton.isEnabled() and view.nextButton.isEnabled())
    pdf.showPage(1)
    Swag.assert(pdf.pageIndex == 1)
    Swag.assert(view.previousButton.isEnabled() and not view.nextButton.isEnabled())

    let oldTip  = String.from(view.pageLabel.toolTip)
    let oldZoom = pdf.effectiveZoom()
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(view.pageLabel.toolTip == PdfDocument.texts().ui_GoToPage and view.pageLabel.toolTip != oldTip)
    Swag.assert(view.previousButton.toolTip == PdfDocument.texts().ui_Previous and view.nextButton.toolTip == PdfDocument.texts().ui_Next)
    Swag.assert(view.zoomLabel.toolTip == PdfDocument.texts().ui_ZoomMenu)
    Swag.assert(pdf.pageIndex == 1 and pdf.effectiveZoom() == oldZoom and pdf.zoomMode == .FitPage)
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
    Swag.assert(view.pageLabel.toolTip == oldTip)
    Swag.assert(view.goToTypedPage("1") and pdf.pageIndex == 0)
    Swag.assert(not view.goToTypedPage("0") and not view.goToTypedPage("3") and not view.goToTypedPage("page"))
    Testing.assertContentFits(view)
}

// Pins the centered page navigation and the zoom value exposed in the information band.
#[Swag.TestTag("golden")]
#test
{
    let fileName = createPdfFixture()
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(720, 500)

    with let commandBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 52})
    {
        .dockStyle       = .Bottom
        .backgroundStyle = .Window
        .padding         = {16, 8, 16, 8}
    }

    with let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    {
        .dockStyle       = .Top
        .backgroundStyle = .InformationBar
        .padding         = {16, 4, 16, 4}
    }

    var result = openTestViewer(PdfDocument.viewerPlugin(), &host.root, fileName, commandParent: commandBar, infoParent: infoBar)
    Swag.assert(result.view != null and result.commands == null and result.info != null)
    infoBar.centerGroup = result.info

    let view = assume cast(*PdfDocument.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.dockStyle        = .Center
    result.info.dockStyle = .None
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.pdf.document")
}

// Pins the PDF controls inside the application's real line of readings. The line measures viewer
// contributions before positioning them, so every fixed page and zoom cell must report the width
// its docking pass will consume.
#[Swag.TestTag("golden")]
#test
{
    let fileName = createPdfFixture()
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(ViewerWindow.MinWidth, ViewerReadingLine.Height)
    host.root.backgroundStyle = .View
    host.root.padding         = {8, 0, 8, 0}

    let document = Wnd.create'Wnd(&host.root)
    document.hide()
    with let layout = ViewerReadingLine.create(&host.root)
    {
        .dockStyle = .Center
        .details.setText("PDF · 1 page")
    }

    var result = openTestViewer(PdfDocument.viewerPlugin(), document, fileName, commandParent: document, infoParent: layout)
    Swag.assert(result.view != null and result.info != null)
    let view = assume cast(*PdfDocument.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    host.root.applyLayout()
    layout.computeLayout()

    Swag.assert(result.info.position.width == 2 * themeActionButtonSize(view.themeMetrics()) + 76 + 96 + 16)
    Swag.assert(view.previousButton.position.right() <= view.pageLabel.position.x)
    Swag.assert(view.pageLabel.position.right() <= view.nextButton.position.x)
    Swag.assert(view.nextButton.position.right() <= view.zoomLabel.position.x)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.pdf.info-bar")
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-pdf-broken-", ".pdf")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "broken")

    var host: HeadlessHost
    host.setup(640, 420)
    var result = openTestViewer(PdfDocument.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null and result.commands == null)
    let view = assume cast(*PdfDocument.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.assert(not view.failureReason.isEmpty())
}

// The viewer owns the search: PDF text lives compressed in the file, so only the viewer can
// walk pages and reveal a match.
#test
{
    let fileName = createPdfFixture()
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(640, 450)

    var result = openTestViewer(PdfDocument.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.collectMatches != null and
                result.revealMatch != null and
                result.searchBounds != null and
                result.clearSearch != null)

    let view = assume cast(*PdfDocument.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.resize(640, 420)
    view.applyLayout()

    var matches: Array'Viewer.SearchMatch
    collectViewerMatches(result.collectMatches, "second", &matches)
    let revealed = matches.count == 1 and result.revealMatch(matches[0], "second")
    Swag.assert(revealed)
    Swag.assert(view.pdfView.pageIndex == 1)
    Swag.assert(view.pdfView.selectedText() == "Second")

    // The page carrying the match is decoded on a worker, and the geometry of a match answers
    // once that page has landed, which is when the host's own poll picks the marker up.
    var bounds: Math.Rectangle
    for 4000
    {
        discard host.render()
        host.fireTimers()
        if result.searchBounds(matches[0], &bounds) do
            break
        Threading.Thread.sleep(1'ms)
    }

    Swag.assert(not bounds.isEmpty())
    result.clearSearch()
    Swag.assert(view.pdfView.selectedText().isEmpty())
    matches.clear()
    collectViewerMatches(result.collectMatches, "absent", &matches)
    Swag.assert(matches.isEmpty())
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

    for light in [false, true]
    {
        var host: HeadlessHost
        host.setup(960, 640)
        if light do
            host.theme.setLight()
        else do
            host.theme.setDark()
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
        Swag.assert(margin.isLocallyVisible() and margin.titles.count == 4 and margin.active == 0)
        Swag.assert(margin.position.right() <= view.pdfView.pageColumn().x)
        var image = host.render(window)
        Pixel.Testing.assertImageGolden(&image, light ? "viewer.pdf.page.paper" : "viewer.pdf.page")
    }
}
