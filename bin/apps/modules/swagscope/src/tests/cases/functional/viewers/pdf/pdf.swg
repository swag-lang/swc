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
    Swag.require(view.children.count == 1 and view.children[0] == cast(*Wnd, view.pdfView))
    assertViewerInfoButton(view.zoomLabel)
    Swag.require(view.details == "PDF · 2 pages · 113 × 78 mm · Viewer fixture · Swag Scope")
    Swag.require(PdfDocument.paperText({842, 595}) == "A4" and PdfDocument.paperText({612, 792}) == "Letter")
    view.resize(640, 420)
    view.applyLayout()

    let pdf = view.pdfView
    Swag.require(pdf.pageCount() == 2 and pdf.pageIndex == 0)
    Swag.require(pdf.zoomMode == .FitPage and pdf.pageLayout == .Continuous)

    // Actual size shows one PDF point per 1/96 logical inch, and it is the 100 % of the readout,
    // as a picture's own pixels are; an explicit zoom multiplies the shown size exactly, with the
    // rasterization following the widget internally.
    pdf.actualSize()
    Swag.require(Math.isEqualEpsilon(pdf.effectiveZoom(), 96.0'f32 / 72.0, 0.001))
    Swag.require(view.zoomPercent() == 100 and view.zoomLabel.text() == Viewer.zoomText(100))
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

// A document that labels its pages names the page in view by its label beside its position, and
// the page dialog accepts a label as well as a position.
#test
{
    let fileName = Testing.tempFilePath("scope-pdf-labels-", ".pdf")
    defer discard catch File.delete(fileName)
    var source: String = "%PDF-1.7\n"
    source += "1 0 obj\n<< /Type /Catalog /Pages 2 0 R /PageLabels << /Nums [1 << /S /r >> 3 << /S /D >> 6 << /P (Cover) >>] >> >>\nendobj\n"
    source += "2 0 obj\n<< /Type /Pages /Count 7 /Kids [3 0 R 3 0 R 3 0 R 3 0 R 3 0 R 3 0 R 3 0 R] >>\nendobj\n"
    source += "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 40 30] /Resources << >> >>\nendobj\n"
    source += "trailer\n<< /Root 1 0 R >>\n%%EOF\n"
    discard expect File.writeAllText(fileName, source)

    var host: HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PdfDocument.viewerPlugin(), &host.root, fileName)
    let view    = assume cast(*PdfDocument.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.resize(640, 360)
    view.applyLayout()
    Swag.require(view.pageLabels.count == 7)
    Swag.require(view.pageReadout() == Viewer.pageText(0, 7))

    Swag.require(view.goToTypedPage("II"))
    Swag.require(view.pdfView.pageIndex == 2, Format.toString("page %", view.pdfView.pageIndex))
    Swag.require(view.pageReadout() == "ii (3/7)")
    Swag.require(view.goToTypedPage("cover") and view.pdfView.pageIndex == 6)
    Swag.require(view.goToTypedPage("4") and view.pdfView.pageIndex == 3)
    Swag.require(not view.goToTypedPage("xiv"))

    // The lens answers `:` with a page, named by its label and its position.
    var windowHost: HeadlessHost
    let window = framedViewerWindow(&windowHost, fileName, false)
    let shown  = assume cast(*PdfDocument.Panel, window.instances[window.activeChoiceIndex].view)
    window.lens.open(":ii")
    windowHost.finishAnimations()
    let row = (unwrap window.lens.results.sections[0]).entries[0]
    Swag.require(row.title == Format.toString(appStrings().lens_GoToPage, "ii (3)") and row.lead == "3")
    row.run!()
    window.lens.close()
    windowHost.finishAnimations()
    Swag.require(shown.pdfView.pageIndex == 2)
}

// The lens selects the text of the page in view and copies a selection, as the page's context
// menu does; with nothing selected, the copy is offered faint.
#test
{
    var host: HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PdfDocument.viewerPlugin(), &host.root, scopeTestDataPath("viewer.pdf"))
    let view    = assume cast(*PdfDocument.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.resize(640, 360)
    view.applyLayout()
    discard host.render(view)

    func row(view: *PdfDocument.Panel, host: *HeadlessHost, title: string, results: *Lens.Results)->*Lens.Entry?
    {
        var entries = Viewer.LensEntries.create(results, "PDF", host.theme)
        view.describeLens(&entries)
        for &entry in results.sections[0]!.entries where entry.title == title do
            return entry
        Swag.require(false, title)
        return null
    }

    var before: Lens.Results
    Swag.require((unwrap row(view, &host, PdfDocument.texts().ui_CopyText, &before)).disabled)
    var select: Lens.Results
    (unwrap row(view, &host, PdfDocument.texts().ui_SelectPage, &select)).run!()
    Swag.require(view.pdfView.hasSelection())

    discard catch Clipboard.resetFake()
    var copy: Lens.Results
    let entry = unwrap row(view, &host, PdfDocument.texts().ui_CopyText, &copy)
    Swag.require(not entry.disabled)
    entry.run!()
    Swag.require(not Clipboard.getString().isEmpty())

    // The zoom rows bear the names every reading viewer gives them.
    var zoom: Lens.Results
    (unwrap row(view, &host, appStrings().cmd_ZoomIn, &zoom)).run!()
    Swag.require(view.pdfView.zoomMode == .Free)

    // Actual size, which `Ctrl 0` reaches, has its row too: a point shown as the 1/72 inch it
    // measures. The row reads as chosen once the pages show at it, as the readout's 100 %.
    var actual: Lens.Results
    let actualRow = unwrap row(view, &host, appStrings().cmd_ZoomReset, &actual)
    Swag.require(not actualRow.checked)
    actualRow.run!()
    Swag.require(view.pdfView.zoomMode == .Free and view.pdfView.zoom == PdfView.ActualSizeZoom)
    var chosen: Lens.Results
    Swag.require((unwrap row(view, &host, appStrings().cmd_ZoomReset, &chosen)).checked)

    // The menu's percentages are of the same actual size the readout measures against.
    view.setZoomPercent(200)
    Swag.require(view.zoomPercent() == 200 and Math.isEqualEpsilon(view.pdfView.effectiveZoom(), 2 * PdfView.ActualSizeZoom, 0.001))

    // At the page view's limits, the step that cannot be taken reads as unavailable.
    view.pdfView.setZoom(PdfView.MaxZoom)
    var largest: Lens.Results
    Swag.require((unwrap row(view, &host, appStrings().cmd_ZoomIn, &largest)).disabled)
    var shrinkable: Lens.Results
    Swag.require(not (unwrap row(view, &host, appStrings().cmd_ZoomOut, &shrinkable)).disabled)
    view.pdfView.setZoom(PdfView.MinZoom)
    var smallest: Lens.Results
    Swag.require((unwrap row(view, &host, appStrings().cmd_ZoomOut, &smallest)).disabled)
}

// The information sheet says whether the pages carry text, without a search: once the text is
// extracted, a scanned document reads as pictures and a written one as text on every page.
#test
{
    for name, index in ["viewer.jpeg.pdf", "viewer.pdf"]
    {
        var host: HeadlessHost
        host.setup(960, 680)
        let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        window.resize(960, 680)
        window.openFile(scopeTestDataPath(name))
        completeQueuedViewerFile(&host, window)
        window.applyLayout()
        window.toggleInformation()

        let view     = assume cast(*PdfDocument.Panel, window.instances[window.activeChoiceIndex].view)
        var attempts = 0
        while not view.pdfView.textCoverage().complete and attempts < 5_000
        {
            Threading.Thread.sleep(1'ms)
            host.pump()
            attempts += 1
        }

        host.pump()
        window.infoSheet.selectPage(1)
        let text     = window.infoSheet.text()
        let expected = index == 0 ? PdfDocument.texts().ui_TextLayerNone : PdfDocument.texts().ui_TextLayerAll
        Swag.require(Utf8.contains(text, Format.toString("Text layer\n%", expected).toString()), text)
    }
}
