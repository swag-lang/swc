#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing

private func createPdfFixture()->String
{
    let fileName = Gui.Testing.tempFilePath("scope-pdf-", ".pdf")
    var document = Pdf.Document.create()
    var first    = Pdf.Page.create(320, 220)
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
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    var result = openTestViewer(pdfViewerPlugin(), &host.root, fileName.toString(), commandParent: &host.root)
    Swag.assert(result.view != null and result.commands == null and result.info != null)

    let view = cast(*PdfViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    assertViewerInfoButton(view.zoomLabel)
    Swag.assert(view.details == "PDF")
    view.resize(640, 420)
    view.applyLayout()

    let pdf = view.pdfView
    Swag.assert(pdf.pageCount() == 2 and pdf.pageIndex == 0)
    Swag.assert(pdf.isFitted)

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
    Swag.assert(pdf.isFitted)
    Swag.assert(!view.previousButton.isEnabled() and view.nextButton.isEnabled())
    expect pdf.showPage(1)
    Swag.assert(pdf.pageIndex == 1)
    Swag.assert(view.previousButton.isEnabled() and !view.nextButton.isEnabled())
    Swag.assert(view.goToTypedPage("1") and pdf.pageIndex == 0)
    Swag.assert(!view.goToTypedPage("0") and !view.goToTypedPage("3") and !view.goToTypedPage("page"))
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
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let commandBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Bottom
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}
    let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    infoBar.dockStyle       = .Top
    infoBar.backgroundStyle = .InformationBar
    infoBar.padding         = {16, 4, 16, 4}

    var result = openTestViewer(pdfViewerPlugin(), &host.root, fileName.toString(), commandParent: commandBar, infoParent: infoBar)
    Swag.assert(result.view != null and result.commands == null and result.info != null)
    infoBar.centerGroup = result.info

    let view = cast(*PdfViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    view.dockStyle         = .Center
    result.info!.dockStyle = .None
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.pdf.document")
}

// Pins the PDF controls inside the application's real information-row layout. The row measures
// viewer contributions before positioning them, so every fixed page and zoom cell must report the
// width its docking pass will consume.
#[Swag.TestTag("golden")]
#test
{
    let fileName = createPdfFixture()
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(ViewerMinWidth, ViewerInfoHeight)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)
    host.root.backgroundStyle = .InformationBar
    host.root.padding         = {8, 2, 8, 2}

    let document = Wnd.create'Wnd(&host.root)
    document.hide()
    let layout = Wnd.create'ViewerInfoLayout(&host.root)
    layout.dockStyle       = .Center
    layout.backgroundStyle = .Transparent

    let actionSize = themeActionButtonSize(layout.themeMetrics())
    layout.filesButton = IconButton.create(layout, layout.theme().icon(.History, themeActionIconSize(layout.themeMetrics())), {0, 0, actionSize, actionSize})
    layout.filesButton.hide()
    layout.fileGroup = StackLayoutCtrl.create(layout, .Left, {0, 0, 0, 36})
    let name = Label.create(layout.fileGroup, "viewer.pdf", {0, 0, 0, 36})
    name.preferredSize.x = Math.ceil(name.itf.measureContent({}).x)
    layout.generalLabel  = Label.create(layout, "PDF", {0, 0, 0, 36}, null, .SecondaryText)

    var result = openTestViewer(pdfViewerPlugin(), document, fileName.toString(), commandParent: document, infoParent: layout)
    Swag.assert(result.view != null and result.info != null)
    let view = cast(*PdfViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    host.root.applyLayout()
    layout.computeLayout()

    Swag.assert(result.info!.position.width == 2 * themeActionButtonSize(view.themeMetrics()) + 76 + 96 + 16)
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
    defer host.shutdown()
    var result = openTestViewer(pdfViewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null and result.commands == null)
    let view = cast(*PdfViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    Swag.assert(!view.failureReason.isEmpty())
}

// The viewer owns the search: PDF text lives compressed in the file, so only the viewer can
// walk pages and reveal a match.
#test
{
    let fileName = createPdfFixture()
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    var result = openTestViewer(pdfViewerPlugin(), &host.root, fileName.toString(), commandParent: &host.root)
    Swag.assert(result.collectMatches != null and result.revealMatch != null and result.searchBounds != null and result.clearSearch != null)

    let view = cast(*PdfViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    view.resize(640, 420)
    view.applyLayout()

    var matches: Array'Viewer.SearchMatch
    result.collectMatches!(result.view!, "second", {}, &matches)
    Swag.assert(matches.count == 1 and result.revealMatch!(result.view!, matches[0], "second"))
    Swag.assert(view.pdfView.pageIndex == 1)
    Swag.assert(view.pdfView.selectedText() == "Second")
    var bounds: Math.Rectangle
    Swag.assert(result.searchBounds!(result.view!, matches[0], &bounds) and !bounds.isEmpty())
    result.clearSearch!(result.view!)
    Swag.assert(view.pdfView.selectedText().isEmpty())
    matches.clear()
    result.collectMatches!(result.view!, "absent", {}, &matches)
    Swag.assert(matches.isEmpty())
}
