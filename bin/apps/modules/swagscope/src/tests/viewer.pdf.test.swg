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
    Swag.assert(result.view != null and result.commands != null)

    let view = cast(*PdfViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    Swag.assert(Utf8.contains(view.details.toString(), "2 pages"))
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
    Swag.assert(result.view != null and result.commands != null)
    commandBar.centerGroup = result.commands
    infoBar.centerGroup    = result.info

    let view = cast(*PdfViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    view.dockStyle          = .Center
    view.commands.dockStyle = .None
    result.info!.dockStyle  = .None
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.pdf.document")
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
    Swag.assert(result.view != null and result.commands != null)
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
