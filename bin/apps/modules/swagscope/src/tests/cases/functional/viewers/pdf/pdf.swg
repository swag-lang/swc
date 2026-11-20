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

internal func createMultipagePdfFixture(pageCount: u32)->String
{
    let fileName = Gui.Testing.tempFilePath("scope-pdf-pages-", ".pdf")
    var document = Pdf.Document.create()
    for index in 0 until pageCount
    {
        var page = Pdf.Page.create(300 + cast(f32, index % 5 * 5), 420)
        page.addText(Format.toString("Generated report page %", index + 1), 24, 32, 18, Color.fromArgb(Argb.Black))
        page.addText("Summary · analysis · references", 24, 76, 11, Color.fromArgb(Argb.Black))
        document.addPage(#move page)
    }
    expect document.save(fileName)
    return fileName
}

// A generated thousand-page document keeps only the active five-page neighborhood and follows
// the current tile into view when the rail itself has to scroll.
#test
{
    let fileName = createMultipagePdfFixture(1000)
    defer discard catch File.delete(fileName)
    var host: HeadlessHost
    host.setup(680, 520)
    var session = openTestViewer(PdfDocument.viewerPlugin(), &host.root, fileName)
    let view = assume cast(*PdfDocument.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.resize(680, 500)
    view.applyLayout()
    view.thumbnailTask.wait()
    host.pump()
    Swag.require(view.pdfView.pageCount() == 1000 and view.thumbnails.count == 5 and view.thumbnailButtons.count == 5)
    Swag.require(view.thumbnailStart == 0 and view.thumbnailScroll.scrollSize.y == 730)

    view.pdfView.showPage(999)
    Swag.require(view.pdfView.pageIndex == 999)
    host.pump()
    view.thumbnailTask.wait()
    host.pump()
    Swag.require(view.thumbnailStart == 995)
    for button, slot in view.thumbnailButtons
    {
        let pageNumber = 996 + slot
        let expected = pageNumber == 1000 ? Format.toString("% · %", PdfDocument.texts().ui_CurrentPage, pageNumber) : Format.toString("%", pageNumber)
        Swag.require(button.text() == expected, Format.toString("slot % shows '%', expected '%'.", slot, button.text(), expected))
    }
    Swag.require(view.thumbnailScroll.scrollPosition().y > 0)
    for imageView in view.thumbnails
    {
        if let image = imageView.picture() do
            Swag.require(image.isValid() and image.width <= 112 and image.height <= 112)
        else do
            Swag.require(false)
    }

    view.thumbnailButtons[1].button.sigPressed.call(view.thumbnailButtons[1])
    Swag.require(view.pdfView.pageIndex == 996)
    Swag.require(view.thumbnailButtons[1].text() == Format.toString("% · %", PdfDocument.texts().ui_CurrentPage, 997))
    Swag.require(view.thumbnailScroll.scrollPosition().y > 0)
}

// Exporting rasterizes one selected PDF page at the reader's stated 300 DPI without rewriting it.
#test
{
    let source = createPdfFixture()
    defer discard catch File.delete(source)
    let target = Gui.Testing.tempFilePath("scope-pdf-export-", ".png")
    defer discard catch File.delete(target)

    var host: HeadlessHost
    host.setup(640, 450)
    var reader = expect Pdf.Reader.open(source)
    let originalPages = reader.pageCount()
    let originalSize = (expect File.info(source)).size
    var session = openTestViewer(PdfDocument.viewerPlugin(), &host.root, source)
    let view = assume cast(*PdfDocument.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    view.resize(640, 420)
    view.applyLayout()
    view.pdfView.showPage(1)
    Swag.require(view.pdfView.pageIndex == 1)
    Swag.require(view.exportPageButton.isEnabled())
    Swag.require(expect PdfDocument.savePagePng(source, target, view.pdfView.pageIndex) == target)
    let image = expect Image.load(target)
    Swag.require(image.isValid() and image.width >= 1333 and image.height >= 916)
    reader = expect Pdf.Reader.open(source)
    Swag.require(reader.pageCount() == originalPages and (expect File.info(source)).size == originalSize)

    let asyncTarget = Gui.Testing.tempFilePath("scope-pdf-export-worker-", ".png")
    defer discard catch File.delete(asyncTarget)
    view.startPageExport(view.pdfView.pageIndex, asyncTarget)
    view.pageExportTask.wait()
    view.finishPageExport()
    Swag.require(not view.pageExporting and expect Image.load(asyncTarget).isValid())

    let rangeFolder = Gui.Testing.tempFilePath("scope-pdf-range-", "")
    expect Directory.create(rangeFolder)
    defer discard catch Directory.delete(rangeFolder, recurse: true)
    var range: PdfDocument.PageRange
    Swag.require(PdfDocument.parsePageRange("1-2", originalPages, &range) and range.first == 0 and range.last == 1)
    for invalid in ["", "0-1", "2-1", "1-3", "one-two", "1-51"]
    {
        var rejected: PdfDocument.PageRange
        Swag.require(not PdfDocument.parsePageRange(invalid, originalPages, &rejected), invalid)
    }
    var capped: PdfDocument.PageRange
    Swag.require(not PdfDocument.parsePageRange("1-51", 100, &capped))
    view.startPageRangeExport(range, rangeFolder, "fixture", 150)
    view.pageExportTask.wait()
    view.finishPageExport()
    let firstExport = expect Image.load(PdfDocument.pageRangeFileName(rangeFolder, "fixture", 0))
    let lastExport = expect Image.load(PdfDocument.pageRangeFileName(rangeFolder, "fixture", 1))
    Swag.require(firstExport.width == 667 and lastExport.width == 667 and firstExport.height == 459)
    var overwriteFailure: Swag.Error
    discard catch PdfDocument.savePageRange(source, rangeFolder, "fixture", 0, 1, 150) as overwriteFailure
    Swag.require(overwriteFailure.value() != null)

    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "PDF", host.theme)
    view.describeLens(&entries)
    var found = false
    for entry in results.sections[0]!.entries where entry.title == PdfDocument.texts().ui_ExportPage
    {
        Swag.require(not entry.disabled)
        found = true
    }
    Swag.require(found)
    var rangeLens = Lens.Results{}
    var rangeEntries = Viewer.LensEntries.create(&rangeLens, "PDF", host.theme)
    view.describeLens(&rangeEntries)
    found = false
    for entry in rangeLens.sections[0]!.entries where entry.title == PdfDocument.texts().ui_ExportRange
    {
        Swag.require(not entry.disabled)
        found = true
    }
    Swag.require(found)
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

    // A real embedded-font document keeps searchable text through its opening and final index pages.
    let firstText = expect reader.loadPageText(0)
    let lastText  = expect reader.loadPageText(66)
    Swag.require(Utf8.contains(firstText, "LLVM OpenMP") and
                 Utf8.contains(lastText, "__kmpc_dispatch_init_4"))
}

// The mixed fixture keeps its first-page text searchable and renders its scanned attachment as a
// raster page with no extracted text layer.
#test
{
    var reader = expect Pdf.Reader.open(scopeTestDataPath("viewer.mixed-text-scan.pdf"))
    Swag.require(reader.pageCount() == 2)
    let text = expect reader.loadPageText(0)
    Swag.require(Utf8.contains(text, "ALPHA marker is searchable"))

    let scanned = expect reader.loadPage(1)
    let image   = expect scanned.render({scale: 0.25, maxDimension: 256, maxPixels: 65_536})
    Swag.require(image.isValid() and image.width > 0 and image.height > 0)
    Swag.require(expect reader.loadPageText(1) == "")
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
    view.thumbnailTask.wait()
    host.pump()
    Swag.require(view.children.count == 2 and view.children.contains(cast(*Wnd, view.pdfView)) and
                 view.thumbnails.count == 5 and view.thumbnailButtons.count == 5)
    if let firstThumbnail = view.thumbnails[0].picture() do
        Swag.require(firstThumbnail.isValid())
    else do
        Swag.require(false)
    if let secondThumbnail = view.thumbnails[1].picture() do
        Swag.require(secondThumbnail.isValid())
    else do
        Swag.require(false)
    Swag.require(view.thumbnailButtons[0].isEnabled() and view.thumbnailButtons[1].isEnabled() and
                 not view.thumbnailButtons[2].isEnabled())
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
    let zoomedOut = pdf.effectiveZoom()
    Swag.require(zoomedOut < beforeZoomOut)

    // The actual size takes Ctrl alone, as the zoom steps and the other viewers do.
    var shiftedActual = KeyEvent{kind: .Pressed, key: .D0, modifiers: .Control | .Shift}
    view.sendEvent(&shiftedActual)
    Swag.require(pdf.effectiveZoom() == zoomedOut)
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
    Swag.require(view.thumbnailButtons[1].text() == Format.toString("% · %", PdfDocument.texts().ui_CurrentPage, 2))
    view.thumbnailButtons[0].button.sigPressed.call(view.thumbnailButtons[0])
    Swag.require(pdf.pageIndex == 0)
    pdf.showPage(1)

    let oldTip  = String.from(view.pageLabel.toolTip)
    let oldZoom = pdf.effectiveZoom()
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(view.pageLabel.toolTip == PdfDocument.texts().ui_GoToPage and view.pageLabel.toolTip != oldTip)
    Swag.require(view.previousButton.toolTip == appStrings().ui_PreviousPage and view.nextButton.toolTip == appStrings().ui_NextPage)
    Swag.require(view.zoomLabel.toolTip == PdfDocument.texts().ui_ZoomMenu)
    Swag.require(view.thumbnailHeading.text() == PdfDocument.texts().ui_Thumbnails)
    Swag.require(view.thumbnailButtons[1].text() == Format.toString("% · %", PdfDocument.texts().ui_CurrentPage, 2))
    Swag.require(pdf.pageIndex == 1 and pdf.effectiveZoom() == oldZoom and pdf.zoomMode == .FitPage)
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
    Swag.require(view.pageLabel.toolTip == oldTip)
    Swag.require(view.goToTypedPage("1") and pdf.pageIndex == 0)
    Swag.require(not view.goToTypedPage("0") and not view.goToTypedPage("3") and not view.goToTypedPage("page"))
    Testing.assertContentFits(view)
}

// The thumbnail rail follows a page jump with a bounded five-page window, and a tile click navigates.
#test
{
    let fileName = createMultipagePdfFixture(9)
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(680, 520)
    var result = openTestViewer(PdfDocument.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view = assume cast(*PdfDocument.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)

    let directBatch = expect PdfDocument.loadThumbnailBatch(fileName, 4, 9)
    Swag.require(directBatch.first == 4 and directBatch.images.count == 5)
    view.thumbnailTask.wait()
    host.pump()
    Swag.require(view.thumbnailStart == 0 and view.thumbnails.count == 5)
    view.resize(680, 500)
    view.applyLayout()
    Swag.require(view.thumbnailScroll.scrollSize.y >= 730)
    view.pdfView.showPage(6)
    Swag.require(view.pdfView.pageIndex == 6)
    host.pump()
    view.thumbnailTask.wait()
    host.pump()
    Swag.require(view.thumbnailStart == 4)
    Swag.require(not view.thumbnailTask.isDone())
    Swag.require(view.thumbnailButtons[2].text() == Format.toString("% · %", PdfDocument.texts().ui_CurrentPage, 7),
                 Format.toString("Current thumbnail text was '%', page index is %", view.thumbnailButtons[2].text(), view.pdfView.pageIndex))
    for imageView in view.thumbnails
    {
        if let image = imageView.picture() do
            Swag.require(image.isValid() and image.width <= 112 and image.height <= 112)
        else do
            Swag.require(false)
    }
    view.thumbnailButtons[4].button.sigPressed.call(view.thumbnailButtons[4])
    Swag.require(view.pdfView.pageIndex == 8)
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
    source += "1 0 obj\n<< /Type /Catalog /Pages 2 0 R /PageLabels << /Nums [1 << /S /r >> 3 << /S /D >> 6 << /P (1-Cover) >>] >> >>\nendobj\n"
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
    Swag.require(view.goToTypedPage("1-cover") and view.pdfView.pageIndex == 6)
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
