#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing

private func createPdfFixture()->String
{
    let fileName = Gui.Testing.tempFilePath("filescope-pdf-", ".pdf")
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

    let request = ViewerRequest{&host.root, &host.root, fileName.toString()}
    var result: ViewerResult
    createPdfViewer(&request, &result)
    @assert(result.view != null and result.commands != null)
    @assert(Utf8.contains(result.details.toString(), "2 pages"))

    let view = cast(*PdfViewer) result.view!
    view.resize(640, 420)
    view.applyLayout()

    let pdf = view.pdfView
    @assert(pdf.pageCount() == 2 and pdf.pageIndex == 0)
    @assert(pdf.isFitted)

    // Actual size shows one PDF point per 1/96 logical inch; an explicit zoom multiplies the
    // shown size exactly, with the rasterization following the widget internally.
    pdf.actualSize()
    @assert(Math.isEqualEpsilon(pdf.effectiveZoom(), 96.0'f32 / 72.0, 0.001))
    let shown = pdf.effectiveZoom()
    pdf.setZoom(shown * 4)
    @assert(Math.isEqualEpsilon(pdf.effectiveZoom(), shown * 4, 0.001))

    let beforeZoomOut = pdf.effectiveZoom()
    var zoomOut       = KeyEvent{kind: .Pressed, key: .Subtract}
    view.sendEvent(&zoomOut)
    @assert(pdf.effectiveZoom() < beforeZoomOut)
    var actual = KeyEvent{kind: .Pressed, key: .D0, modifiers: .Control}
    view.sendEvent(&actual)
    @assert(Math.isEqualEpsilon(pdf.effectiveZoom(), 96.0'f32 / 72.0, 0.001))

    pdf.zoomToFit()
    @assert(pdf.isFitted)
    @assert(!view.previousButton.isEnabled() and view.nextButton.isEnabled())
    expect pdf.showPage(1)
    @assert(pdf.pageIndex == 1)
    @assert(view.previousButton.isEnabled() and !view.nextButton.isEnabled())
    Testing.assertContentFits(view)
}

// Pins page navigation and magnification as one compact icon family around the page readout.
#test
{
    let fileName = createPdfFixture()
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(720, 500)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let commandBar = Wnd.create'Wnd(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Bottom
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}

    let request = ViewerRequest{&host.root, commandBar, fileName.toString()}
    var result: ViewerResult
    createPdfViewer(&request, &result)
    @assert(result.view != null and result.commands != null)

    let view = cast(*PdfViewer) result.view!
    view.dockStyle          = .Center
    view.commands.dockStyle = .Center
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.pdf.document")
}

#test
{
    let fileName = Gui.Testing.tempFilePath("filescope-pdf-broken-", ".pdf")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "broken")

    var host: HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()
    let request = ViewerRequest{&host.root, &host.root, fileName}
    var result: ViewerResult
    createPdfViewer(&request, &result)
    @assert(result.view == null and result.commands == null)
    @assert(!result.failureReason.isEmpty())
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

    let request = ViewerRequest{&host.root, &host.root, fileName.toString()}
    var result: ViewerResult
    createPdfViewer(&request, &result)
    @assert(result.findText != null and result.revealMatch == null)

    let view = cast(*PdfViewer) result.view!
    view.resize(640, 420)
    view.applyLayout()

    @assert(result.findText!(result.view!, "second"))
    @assert(view.pdfView.pageIndex == 1)
    @assert(view.pdfView.selectedText() == "Second")
    @assert(!result.findText!(result.view!, "absent"))
}
