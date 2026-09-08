#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Pdf

func pdfViewFixture()->String
{
    let fileName = Testing.tempFilePath("gui-pdfview-", ".pdf")
    var document = Document.create()
    var first    = Page.create(320, 220)
    first.addText("PDF viewer", 32, 28, 24, Color.fromArgb(Argb.Black))
    document.addPage(#move first)
    var second = Page.create(320, 220)
    second.addText("Second page", 32, 28, 24, Color.fromArgb(Argb.Black))
    document.addPage(#move second)
    expect document.save(fileName)
    return fileName
}

// A document whose first page carries one image and whose second page carries none.
func pdfViewImageFixture()->String
{
    let fileName = Testing.tempFilePath("gui-pdfview-image-", ".pdf")
    var art      = Image.create(8, 8, .BGRA8)
    art.clear()
    var document = Document.create()
    var first    = Page.create(200, 100)
    first.addImage(art, 20, 20, 80, 40)
    document.addPage(#move first)
    var second = Page.create(200, 100)
    second.addText("no image", 10, 10, 12, Color.fromArgb(Argb.Black))
    document.addPage(#move second)
    expect document.save(fileName)
    return fileName
}

// Counts the painted pixels proving a page reached the frame: the white page ground, and
// the dark marks of its text.
func countPageEvidence(image: const *Image)->{ paper: u64, ink: u64 }
{
    var result: retval
    for y in image.height
    {
        for x in image.width
        {
            let color = image.pixelColor(x, y)
            if color.r > 250 and color.g > 250 and color.b > 250 do
                result.paper += 1
            elif color.r < 80 and color.g < 80 and color.b < 80 do
                result.ink += 1
        }
    }

    return result
}

// A document opened and decoded away from the widget is published without reopening it.
#test
{
    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)

    var reader = #move expect Reader.open(fileName.toString())
    var page   = #move expect reader.loadPage(0)
    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.exchangeDocument(&reader, &page)
    Swag.assert(view.pageCount() == 2 and view.pageIndex == 0)
    Swag.assert(reader.pageCount() == 0)

    // The page the host decoded is the one the view holds; nothing decoded it a second time.
    Swag.assert(view.cache.isResident(0) and !view.cache.isResident(1))
}

// A document is laid out from its page tree, so the whole of it is scrollable before a single
// page has been decoded.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(800, 560)
    view.applyLayout()
    expect view.open(corpusPdfPath("llvm-polly-kernelgen-ncar-2012-slides.pdf"))
    Swag.assert(view.pageCount() == 28)
    Swag.assert(view.cache.pages.isEmpty())

    // Every page contributes its own height to the column, and the column is what the scroll
    // frame publishes.
    let content = view.contentSize()
    Swag.assert(content.y > 20 * view.pageRect(0).height)
    Swag.assert(Math.isEqualEpsilon(view.scroll.scrollSize.y, content.y, 0.5))
    Swag.assert(view.pageRect(27).y > view.pageRect(26).y)
}

// A real multi-megabyte document keeps its mapped source, a lightweight page index, and a bounded
// number of decoded pages. Walking the whole document twice must replace page resources rather
// than cache a second document's worth of streams, fonts, paths and images.
#test
{
    let allocator = Swag.defaultAllocator()
    let baseline  = allocator.stats()

    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(800, 560)
    view.applyLayout()
    expect view.open(corpusPdfPath("llvm-polly-kernelgen-ncar-2012-slides.pdf"))
    Swag.assert(view.pageCount() == 28)

    for pageIndex in view.pageCount()
    {
        view.showPage(pageIndex)
        settlePdfView(&host, view)
    }

    // The decoded pages are bounded by both of the view's limits, and the document itself — its
    // mapped source, its object index and the faces it resolved — is what the rest holds.
    let firstPass = allocator.stats()
    Swag.assert(view.cache.pages.count <= PdfView.ResidentPageLimit)
    Swag.assert(view.cache.memoryUsage() <= PdfView.ResidentPageBudget)
    Swag.assert(firstPass.sizeAlloc < baseline.sizeAlloc + 128 * 1024 * 1024)

    for pageIndex in view.pageCount()
    {
        view.showPage(pageIndex)
        settlePdfView(&host, view)
    }

    let secondPass = allocator.stats()
    Swag.assert(view.cache.pages.count <= PdfView.ResidentPageLimit)
    Swag.assert(secondPass.sizeAlloc < baseline.sizeAlloc + 128 * 1024 * 1024)
    Swag.assert(secondPass.sizeAlloc <= firstPass.sizeAlloc + 2 * 1024 * 1024)
}

// The view paints decoded pages straight through the widget's painter: one rendered frame shows
// the page ground and its text, with no offline rasterization in between.
#test
{
    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450, dpiScale: 1.5)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(640, 420)
    view.applyLayout()
    expect view.open(fileName.toString())
    Swag.assert(view.pageCount() == 2 and view.pageIndex == 0)
    Swag.assert(view.zoomMode == .FitPage and view.pageLayout == .Continuous)

    settlePdfView(&host, view)
    let frame = host.render()
    Swag.assert(frame.isValid())
    let evidence = countPageEvidence(&frame)
    Swag.assert(evidence.paper > 10_000)
    Swag.assert(evidence.ink > 50)
    Swag.assert(!view.reportedPaintError)

    // Actual size is one PDF point per 1/96 logical inch, whatever the display resolution.
    view.actualSize()
    Swag.assert(view.zoomMode == .Free)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 96.0'f32 / 72.0, 0.001))

    // Fitting the width uses the whole viewport, so it is never smaller than fitting the page.
    view.zoomToFitWidth()
    let width = view.effectiveZoom()
    view.zoomToFit()
    Swag.assert(width >= view.effectiveZoom())
}

// Zoomed out, the column shows several pages at once: that is what makes it a document rather
// than a stack of independent views.
#test
{
    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(640, 420)
    view.applyLayout()
    expect view.open(fileName.toString())

    // Fitted, one whole page stands in the viewport and the next one waits below it.
    Swag.assert(view.pageRect(0).height <= view.viewportSize().y)
    Swag.assert(view.pageRect(1).y >= view.pageRect(0).bottom())

    view.setZoom(view.effectiveZoom() * 0.4)
    Swag.assert(view.visibleRange().first == 0 and view.visibleRange().last == 1)
    settlePdfView(&host, view)
    Swag.assert(view.cache.isResident(0) and view.cache.isResident(1))

    // Both pages are drawn in the same frame, so the ground shows twice the paper one page has.
    let frame    = host.render()
    let evidence = countPageEvidence(&frame)
    let expected = cast(u64) (view.pageRect(0).width * view.pageRect(0).height)
    Swag.assert(evidence.paper > expected + expected / 2)

    // One page at a time is the other reading of the same document, and it keeps the page.
    view.setPageLayout(.Single)
    Swag.assert(view.visibleRange().first == 0 and view.visibleRange().last == 0)
    view.showPage(1)
    Swag.assert(view.pageIndex == 1 and view.visibleRange().first == 1)
}

// A zoom step is a transform change, so the wheel takes effect immediately: no deferred
// re-rasterization, no timer, and the next frame paints at the new scale.
#test
{
    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(640, 420)
    view.applyLayout()
    expect view.open(fileName.toString())
    settlePdfView(&host, view)

    let fitted = view.effectiveZoom()
    host.mouseWheel({320, 210}, 1, .Control)
    Swag.assert(view.zoomMode == .Free)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), fitted * 1.12, 0.001))

    // A deep zoom stays a transform change and still paints the page region under the view.
    view.setZoom(40)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 40.0, 0.001))
    settlePdfView(&host, view)
    let frame    = host.render()
    let evidence = countPageEvidence(&frame)
    Swag.assert(evidence.paper > 10_000)
    Swag.assert(!view.reportedPaintError)

    // The plain wheel scrolls the document instead of zooming it, and it glides there: the
    // notch names where the document is heading, and the movement follows.
    view.zoomToFit()
    let before = view.scroll.scrollPosition().y
    host.mouseWheel({320, 210}, -1)
    Swag.assert(view.scroll.scrollTarget().y == before + PdfView.WheelScrollStep)

    // A second notch retargets the movement in flight instead of restarting it.
    host.mouseWheel({320, 210}, -1)
    Swag.assert(view.scroll.scrollTarget().y == before + 2 * PdfView.WheelScrollStep)
    host.finishAnimations()
    Swag.assert(view.scroll.scrollPosition().y == before + 2 * PdfView.WheelScrollStep)
}

// Scrolling is bounded by the document, and reversing at an edge responds on the first notch.
#test
{
    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(640, 420)
    view.applyLayout()
    expect view.open(fileName.toString())

    for 32 do
        host.mouseWheel({320, 210}, 1)
    host.finishAnimations()
    Swag.assert(view.scroll.scrollPosition().y == 0)

    // The end of the document is the last page's bottom, not the first page's.
    let limit = Math.max(view.contentSize().y - view.viewportSize().y, 0)
    for 128 do
        host.mouseWheel({320, 210}, -1)
    host.finishAnimations()
    Swag.assert(Math.isEqualEpsilon(view.scroll.scrollPosition().y, limit, 1))
    Swag.assert(view.pageIndex == 1)

    let edge = view.scroll.scrollPosition().y
    host.mouseWheel({320, 210}, 1)
    host.finishAnimations()
    Swag.assert(view.scroll.scrollPosition().y == edge - PdfView.WheelScrollStep)

    // Scrolling back through the whole document lands on the first page again.
    for 256 do
        host.mouseWheel({320, 210}, 1)
    host.finishAnimations()
    Swag.assert(view.scroll.scrollPosition().y == 0 and view.pageIndex == 0)
}

// The images of a page are uploaded to the renderer once per page and released with the page.
#test
{
    let fileName = pdfViewImageFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(640, 420)
    view.applyLayout()
    expect view.open(fileName.toString())
    settlePdfView(&host, view)

    let first = view.cache.resident(0)
    Swag.assert(first != null and first!.hasTextures and first!.textures.count == 1)
    Swag.assert(first!.textures[0].isValid())

    // A second frame reuses the uploaded texture instead of building a new one.
    let handle = first!.textures[0].handle
    discard host.render()
    Swag.assert(first!.textures.count == 1 and first!.textures[0].handle == handle)

    // Closing the document releases every texture with the pages that owned them.
    view.close()
    Swag.assert(view.cache.pages.isEmpty() and view.pageCount() == 0)
}

// Page navigation keeps the zoom mode, reports the ends, and close releases the content.
#test
{
    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(640, 420)
    view.applyLayout()
    expect view.open(fileName.toString())

    var pageChanges = 0
    view.sigPageChanged += func|&pageChanges|(pdf)
    {
        discard pdf
        pageChanges += 1
    }

    let fitted = view.effectiveZoom()
    view.nextPage()
    Swag.assert(view.pageIndex == 1)
    view.nextPage()
    Swag.assert(view.pageIndex == 1)
    view.previousPage()
    Swag.assert(view.pageIndex == 0)
    view.previousPage()
    Swag.assert(view.pageIndex == 0)
    Swag.assert(pageChanges == 2)
    Swag.assert(view.zoomMode == .FitPage and view.effectiveZoom() == fitted)

    view.close()
    Swag.assert(view.pageCount() == 0 and view.contentSize() == Math.Point{})
}

// The text index reads a page the way a reader does: lines top to bottom, words separated by
// their gaps, positions and rectangles answering in page space.
#test
{
    var page = Page.create(320, 220)
    page.addText("alpha beta", 40, 40, 20, Color.fromArgb(Argb.Black))
    page.addText("gamma", 40, 80, 20, Color.fromArgb(Argb.Black))

    let index = TextIndex.build(&page)
    Swag.assert(index.text == "alpha beta\ngamma")
    Swag.assert(index.runs.count == 2)

    // A point inside the first glyph answers its exact offset.
    let hit = index.positionAt({41, 50})
    Swag.assert(hit.distance == 0)
    Swag.assert(hit.offset == 0)

    // A point far to the right of a line snaps to that line's end.
    let far = index.positionAt({300, 50})
    Swag.assert(far.offset == 10)

    let word = index.wordRangeAt(7)
    Swag.assert(index.text.toString()[word.start until word.end] == "beta")

    var rects: Array'Math.Rectangle
    index.rangeRects(0, 5, &rects)
    Swag.assert(rects.count == 1)
    Swag.assert(rects[0].x >= 39 and rects[0].x <= 41)
    Swag.assert(rects[0].y >= 39 and rects[0].y <= 41)
}

// Selection on the view: a drag over words takes them, a double click takes one word, and the
// clipboard receives what the document shows.
#test
{
    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(640, 420)
    view.applyLayout()
    expect view.open(fileName.toString())
    settlePdfView(&host, view)

    // Page-space (32, 28)-(32+w, 52) holds "PDF viewer"; aim inside it through the fit scale.
    let scale = view.effectiveZoom()
    let page  = pdfPageRectOnScreen(view, 0)

    let dragFrom = view.canvas.localToSurface(Math.Point{page.x + 33 * scale, page.y + 40 * scale})
    let dragTo   = view.canvas.localToSurface(Math.Point{page.x + 300 * scale, page.y + 40 * scale})
    host.drag(dragFrom, dragTo)
    Swag.assert(view.hasSelection())
    Swag.assert(view.selectedText() == "PDF viewer")
    Swag.assert(view.copySelection())
    Swag.assert(Clipboard.getString() == "PDF viewer")

    host.doubleClick(dragFrom)
    Swag.assert(view.selectedText() == "PDF")

    view.clearSelection()
    Swag.assert(!view.hasSelection())
    Swag.assert(!view.copySelection())

    view.selectAll()
    Swag.assert(view.selectedText() == "PDF viewer")
}

// A selection running past the bottom of a page keeps going on the next one: the column is one
// document, so the copy is what the reader dragged over.
#test
{
    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(640, 420)
    view.applyLayout()
    expect view.open(fileName.toString())
    view.setZoom(view.effectiveZoom() * 0.4)
    settlePdfView(&host, view)

    let scale = view.effectiveZoom()
    let first = pdfPageRectOnScreen(view, 0)
    let last  = pdfPageRectOnScreen(view, 1)
    let start = view.canvas.localToSurface(Math.Point{first.x + 33 * scale, first.y + 40 * scale})
    let end   = view.canvas.localToSurface(Math.Point{last.x + 300 * scale, last.y + 40 * scale})
    host.drag(start, end)
    Swag.assert(view.hasSelection())
    Swag.assert(view.selectionStart().pageIndex == 0 and view.selectionEnd().pageIndex == 1)
    Swag.assert(view.selectedText() == "PDF viewer\nSecond page")
}

// Search scans forward from the current page, wraps once around the document, and turns the
// match into the visible selection.
#test
{
    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(640, 420)
    view.applyLayout()
    expect view.open(fileName.toString())
    settlePdfView(&host, view)

    Swag.assert(view.findText("second"))
    Swag.assert(view.pageIndex == 1)
    Swag.assert(view.selectedText() == "Second")

    // The same query keeps walking and comes back around to the only match.
    Swag.assert(view.findText("second"))
    Swag.assert(view.pageIndex == 1)
    Swag.assert(view.selectedText() == "Second")

    // A match behind the current page is reached through the wrap.
    Swag.assert(view.findText("viewer"))
    Swag.assert(view.pageIndex == 0)
    Swag.assert(view.selectedText() == "viewer")

    Swag.assert(!view.findText("absent"))

    let matches = view.findTextMatches("second")
    Swag.assert(matches.count == 1 and matches[0].pageIndex == 1)
    let revealed = view.revealTextMatch(matches[0])
    Swag.assert(revealed and view.selectedText() == "Second")
    settlePdfView(&host, view)
    var matchRect: Math.Rectangle
    Swag.assert(view.textMatchRect(matches[0], &matchRect) and !matchRect.isEmpty())

    var exact: PdfTextSearchOptions
    exact.comparison = .Latin1
    Swag.assert(view.findTextMatches("second", exact).isEmpty())

    var words: PdfTextSearchOptions
    words.wholeWord = true
    Swag.assert(view.findTextMatches("view", words).isEmpty())

    var expression: PdfTextSearchOptions
    expression.regularExpression = true
    let expressionMatches = view.findTextMatches(#raw "Sec.nd", expression)
    Swag.assert(expressionMatches.count == 1 and expressionMatches[0].pageIndex == 1 and expressionMatches[0].byteLength == 6)
    Swag.assert(view.findTextMatches("(", expression).isEmpty())

    // The progressive form answers the same matches a page at a time and never waits for one;
    // an invalid expression ends it at once.
    var collected: Array'PdfTextMatch
    var page = 0'u64
    while !view.collectTextMatches("second", {}, &page, &collected) do
        Threading.Thread.sleep(1'ms)
    Swag.assert(page == 2 and collected.count == 1 and collected[0].pageIndex == 1 and collected[0].byteOffset == 0 and collected[0].byteLength == 6)
    page = 0
    collected.clear()
    Swag.assert(view.collectTextMatches("(", expression, &page, &collected) and collected.isEmpty())
}

// The document's text is extracted on a worker the first time a search asks for it, once per
// document: closing the document stops the worker wherever it is, and the next document starts
// its own extraction.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(640, 420)
    view.applyLayout()
    expect view.open(corpusPdfPath("llvm-polly-kernelgen-ncar-2012-slides.pdf"))
    Swag.assert(!view.documentText.started)

    var matches: Array'PdfTextMatch
    var page = 0'u64
    discard view.collectTextMatches("polly", {}, &page, &matches)
    Swag.assert(view.documentText.started)
    view.close()
    Swag.assert(!view.documentText.started and view.pageCount() == 0)

    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)
    expect view.open(fileName.toString())
    Swag.assert(!view.documentText.started)
    let found = view.findTextMatches("page")
    Swag.assert(view.documentText.started and view.documentText.isComplete())
    Swag.assert(found.count == 1 and found[0].pageIndex == 1 and found[0].byteOffset == 7)
    Swag.assert(view.findText("viewer") and view.pageIndex == 0 and view.selectedText() == "viewer")

    // Showing another page keeps the extracted text: the second search costs no decode.
    view.showPage(1)
    Swag.assert(view.documentText.started)
    Swag.assert(view.findTextMatches("PDF").count == 1)
}

// The context menu reaches the same selection commands the keyboard binds.
#test
{
    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(640, 420)
    view.applyLayout()
    expect view.open(fileName.toString())
    settlePdfView(&host, view)

    host.clickPopupMenuItemWhenShown(PdfView.CtxSelectAll)
    view.showContextMenu({100, 100})
    host.pump()
    Swag.assert(view.selectedText() == "PDF viewer")

    host.clickPopupMenuItemWhenShown(PdfView.CtxCopy)
    view.showContextMenu({100, 100})
    host.pump()
    Swag.assert(Clipboard.getString() == "PDF viewer")
}

// Zooming past a flattening bucket does not make the frame that crosses it flatten the whole
// page: the view keeps drawing at the flattening the page holds and a worker raises it, so the
// frame at the new zoom shows the page, and the finer geometry arrives from the worker.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    view.resize(800, 560)
    view.applyLayout()
    expect view.open(corpusPdfPath("llvm-polly-impact-2011-slides.pdf"))
    settlePdfView(&host, view)

    // A page is flattened for the scale it will be shown at by the worker that decoded it, so
    // the frame that first shows it neither decodes nor tessellates.
    let entry = view.cache.resident(0)
    Swag.assert(entry != null)
    let fitted = entry!.preparedScale
    Swag.assert(fitted > 0 and !view.preparing)

    // Four times the zoom is two buckets up, so the page does not hold the flattening the frame
    // wants; the frame still paints, and asks for it.
    view.setZoom(view.effectiveZoom() * 4)
    let frame = host.render()
    Swag.assert(frame.isValid())
    Swag.assert(countPageEvidence(&frame).paper > 10_000)
    Swag.assert(!view.reportedPaintError)
    Swag.assert(view.preparingScale > fitted)

    // The worker publishes through the view's own poll, so firing that timer is what adopts it.
    for 2000
    {
        if !view.preparing do
            break
        Threading.Thread.sleep(1'ms)
        host.fireTimers()
    }

    Swag.assert(!view.preparing)
    Swag.assert(view.cache.resident(0)!.preparedScale > fitted)

    // Zooming back out asks for less than the page holds, so nothing is prepared again.
    let raised = view.cache.resident(0)!.preparedScale
    view.setZoom(view.effectiveZoom() / 8)
    discard host.render()
    Swag.assert(!view.preparing and view.cache.resident(0)!.preparedScale == raised)

    // Closing the document stops the worker and releases what it was raising.
    view.close()
    Swag.assert(!view.preparing and view.cache.pages.isEmpty())
}
