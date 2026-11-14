#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Gui.Testing, Viewers

internal func createPdfFixture()->String
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

// Files from different PDF producers and page encodings open as readable pages.
#test
{
    const Cases: [4] string = [
        "viewer.object-stream.pdf",
        "viewer.rotation.pdf",
        "viewer.jpeg.pdf",
        "viewer.ccitt.pdf"]
    for name in Cases
    {
        var reader = expect Pdf.Reader.open(scopeTestDataPath(name))
        Swag.require(reader.pageCount() > 0, name)
        let page = expect reader.loadPage(0)
        Swag.require(page.width > 0 and page.height > 0, name)
    }
}

// A complete LLVM reference manual is a larger, real-world multipage PDF.
#test
{
    var reader = expect Pdf.Reader.open(scopeTestDataPath("viewer.openmp-reference.pdf"))
    Swag.require(reader.pageCount() == 67)
    let first = expect reader.loadPage(0)
    let last  = expect reader.loadPage(66)
    Swag.require(first.width > 0 and first.height > 0)
    Swag.require(last.width > 0 and last.height > 0)
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
    Swag.require(result.view != null and result.commands != null and result.info != null)

    let view = assume cast(*PdfDocument.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    assertViewerInfoButton(view.zoomLabel)
    Swag.require(view.details == "PDF · 2 pages · 113 × 78 mm · Viewer fixture · Swag Scope")
    Swag.require(PdfDocument.paperText({842, 595}) == "A4" and PdfDocument.paperText({612, 792}) == "Letter")
    view.resize(640, 420)
    view.applyLayout()

    let pdf = view.pdfView
    Swag.require(pdf.pageCount() == 2 and pdf.pageIndex == 0)
    Swag.require(pdf.zoomMode == .FitPage and pdf.pageLayout == .Continuous)

    // Actual size shows one PDF point per 1/96 logical inch; an explicit zoom multiplies the
    // shown size exactly, with the rasterization following the widget internally.
    pdf.actualSize()
    Swag.require(Math.isEqualEpsilon(pdf.effectiveZoom(), 96.0'f32 / 72.0, 0.001))
    let shown = pdf.effectiveZoom()
    pdf.setZoom(shown * 4)
    Swag.require(Math.isEqualEpsilon(pdf.effectiveZoom(), shown * 4, 0.001))

    let beforeZoomOut = pdf.effectiveZoom()
    var zoomOut       = KeyEvent{kind: .Pressed, key: .Subtract, modifiers: .Control}
    view.sendEvent(&zoomOut)
    Swag.require(pdf.effectiveZoom() < beforeZoomOut)
    var actual = KeyEvent{kind: .Pressed, key: .D0, modifiers: .Control}
    view.sendEvent(&actual)
    Swag.require(Math.isEqualEpsilon(pdf.effectiveZoom(), 96.0'f32 / 72.0, 0.001))

    pdf.zoomToFit()
    Swag.require(pdf.zoomMode == .FitPage)

    // Fitting the width is the reading scale of a continuous document, and the shortcut the
    // viewer binds for it.
    var fitWidth = KeyEvent{kind: .Pressed, key: .W}
    view.sendEvent(&fitWidth)
    Swag.require(pdf.zoomMode == .FitWidth)
    pdf.zoomToFit()

    Swag.require(not view.previousButton.isEnabled() and view.nextButton.isEnabled())
    pdf.showPage(1)
    Swag.require(pdf.pageIndex == 1)
    Swag.require(view.previousButton.isEnabled() and not view.nextButton.isEnabled())

    let oldTip  = String.from(view.pageLabel.toolTip)
    let oldZoom = pdf.effectiveZoom()
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(view.pageLabel.toolTip == PdfDocument.texts().ui_GoToPage and view.pageLabel.toolTip != oldTip)
    Swag.require(view.previousButton.toolTip == appStrings().ui_PreviousPage and view.nextButton.toolTip == appStrings().ui_NextPage)
    Swag.require(view.zoomLabel.toolTip == PdfDocument.texts().ui_ZoomMenu)
    Swag.require(pdf.pageIndex == 1 and pdf.effectiveZoom() == oldZoom and pdf.zoomMode == .FitPage)
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
    Swag.require(view.pageLabel.toolTip == oldTip)
    Swag.require(view.goToTypedPage("1") and pdf.pageIndex == 0)
    Swag.require(not view.goToTypedPage("0") and not view.goToTypedPage("3") and not view.goToTypedPage("page"))
    Testing.assertContentFits(view)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-pdf-broken-", ".pdf")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "broken")

    var host: HeadlessHost
    host.setup(640, 420)
    var result = openTestViewer(PdfDocument.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.require(result.view != null and result.commands != null)
    let view = assume cast(*PdfDocument.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(not view.failureReason.isEmpty())
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
    Swag.require(result.collectMatches != null and
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
    Swag.require(revealed)
    Swag.require(view.pdfView.pageIndex == 1)
    Swag.require(view.pdfView.selectedText() == "Second")

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

    Swag.require(not bounds.isEmpty())
    result.clearSearch()
    Swag.require(view.pdfView.selectedText().isEmpty())
    matches.clear()
    collectViewerMatches(result.collectMatches, "absent", &matches)
    Swag.require(matches.isEmpty())
}
