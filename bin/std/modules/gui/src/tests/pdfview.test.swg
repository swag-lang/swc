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

// Counts the painted pixels proving the page reached the frame: the white page ground, and
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
}

// A real multi-megabyte document keeps only its mapped source, lightweight page index and current
// decoded page. Walking the whole document twice must replace page resources rather than cache a
// second document's worth of streams, fonts, paths and images.
#test
{
    let allocator = Swag.defaultAllocator()
    let baseline  = allocator.stats()

    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    expect view.open(corpusPdfPath("llvm-polly-kernelgen-ncar-2012-slides.pdf"))
    Swag.assert(view.pageCount() == 28)
    for pageIndex in view.pageCount() do
        expect view.showPage(pageIndex)
    let firstPass = allocator.stats()
    Swag.assert(firstPass.sizeAlloc < baseline.sizeAlloc + 64 * 1024 * 1024)

    for pageIndex in view.pageCount() do
        expect view.showPage(pageIndex)
    let secondPass = allocator.stats()
    Swag.assert(secondPass.sizeAlloc < baseline.sizeAlloc + 64 * 1024 * 1024)
    Swag.assert(secondPass.sizeAlloc <= firstPass.sizeAlloc + 2 * 1024 * 1024)
}

// The view paints the decoded page straight through the widget's painter: one rendered frame
// shows the page ground and its text, with no offline rasterization in between.
#test
{
    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450, dpiScale: 1.5)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    expect view.open(fileName.toString())
    view.resize(640, 420)
    view.applyLayout()
    Swag.assert(view.pageCount() == 2 and view.pageIndex == 0)
    Swag.assert(view.isFitted)

    let frame = host.render()
    Swag.assert(frame.isValid())
    let evidence = countPageEvidence(&frame)
    Swag.assert(evidence.paper > 10_000)
    Swag.assert(evidence.ink > 50)
    Swag.assert(!view.reportedPaintError)

    // Actual size is one PDF point per 1/96 logical inch, whatever the display resolution.
    view.actualSize()
    Swag.assert(!view.isFitted)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 96.0'f32 / 72.0, 0.001))
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
    expect view.open(fileName.toString())
    view.resize(640, 420)
    view.applyLayout()
    discard host.render()

    let fitted = view.effectiveZoom()
    host.mouseWheel({320, 210}, 120, .Control)
    Swag.assert(!view.isFitted)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), fitted * 1.12, 0.001))

    // A deep zoom stays a transform change and still paints the page region under the view.
    view.setZoom(40)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 40.0, 0.001))
    let frame    = host.render()
    let evidence = countPageEvidence(&frame)
    Swag.assert(evidence.paper > 10_000)
    Swag.assert(!view.reportedPaintError)

    // The plain wheel scrolls instead of zooming.
    let before = view.panOffset.y
    host.mouseWheel({320, 210}, 120)
    Swag.assert(view.panOffset.y == before + 60)
}

// Wheel scrolling is bounded by the page, and reversing at an edge responds on the first notch.
// A fitted page cannot be pushed into empty space; a zoomed page can reach, but not cross, its
// physical edges.
#test
{
    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    expect view.open(fileName.toString())
    view.resize(640, 420)
    view.applyLayout()

    for 32 do
        host.mouseWheel({320, 210}, 120)
    Swag.assert(view.panOffset == Math.Point{})

    view.setZoom(4)
    let client      = view.paddedClientRect()
    let page        = view.pageSize()
    let verticalMax = Math.max(page.y * view.effectiveZoom() - client.height, 0) * 0.5
    for 128 do
        host.mouseWheel({320, 210}, 120)
    Swag.assert(view.panOffset.y <= verticalMax + 0.01)
    Swag.assert(view.panOffset.y >= verticalMax - 0.01)

    let edge = view.panOffset.y
    host.mouseWheel({320, 210}, -120)
    Swag.assert(view.panOffset.y == edge - PdfView.WheelScrollStep)

    for 256 do
        host.mouseWheel({320, 210}, -120)
    Swag.assert(view.panOffset.y >= -verticalMax - 0.01)
}

// The images of a page are uploaded to the renderer once per page and released with it.
#test
{
    let fileName = pdfViewImageFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    expect view.open(fileName.toString())
    view.resize(640, 420)
    view.applyLayout()

    discard host.render()
    Swag.assert(view.hasTextures)
    Swag.assert(view.imageTextures.count == 1)
    Swag.assert(view.imageTextures[0].isValid())

    // A second frame reuses the uploaded texture instead of building a new one.
    let handle = view.imageTextures[0].handle
    discard host.render()
    Swag.assert(view.imageTextures.count == 1)
    Swag.assert(view.imageTextures[0].handle == handle)

    // Turning the page releases the previous page's textures.
    view.nextPage()
    Swag.assert(!view.hasTextures)
    Swag.assert(view.imageTextures.count == 0)
    discard host.render()
    Swag.assert(view.hasTextures and view.imageTextures.count == 0)
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
    expect view.open(fileName.toString())
    view.resize(640, 420)
    view.applyLayout()

    var pageChanges = 0
    view.sigPageChanged += func|&pageChanges|(pdf)
    {
        discard pdf
        pageChanges += 1
    }

    view.nextPage()
    Swag.assert(view.pageIndex == 1)
    view.nextPage()
    Swag.assert(view.pageIndex == 1)
    view.previousPage()
    Swag.assert(view.pageIndex == 0)
    view.previousPage()
    Swag.assert(view.pageIndex == 0)
    Swag.assert(pageChanges == 2)

    view.close()
    Swag.assert(view.pageCount() == 0)
    Swag.assert(!view.hasTextures and view.imageTextures.count == 0)
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
// clipboard receives what the page shows.
#test
{
    let fileName = pdfViewFixture()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    expect view.open(fileName.toString())
    view.resize(640, 420)
    view.applyLayout()

    // Page-space (32, 28)-(32+w, 52) holds "PDF viewer"; aim inside it through the fit scale.
    let scale   = view.effectiveZoom()
    let client  = view.paddedClientRect()
    let size    = view.pageSize()
    let originX = client.horzCenter() - size.x * scale * 0.5 + view.panOffset.x
    let originY = client.vertCenter() - size.y * scale * 0.5 + view.panOffset.y

    let dragFrom = view.localToSurface(Math.Point{originX + 33 * scale, originY + 40 * scale})
    let dragTo   = view.localToSurface(Math.Point{originX + 300 * scale, originY + 40 * scale})
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
    expect view.open(fileName.toString())
    view.resize(640, 420)
    view.applyLayout()

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
    Swag.assert(view.revealTextMatch(matches[0]) and view.selectedText() == "Second")
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
    expect view.showPage(1)
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
    expect view.open(fileName.toString())
    view.resize(640, 420)
    view.applyLayout()

    host.clickPopupMenuItemWhenShown(PdfView.CtxSelectAll)
    view.showContextMenu({100, 100})
    host.pump()
    Swag.assert(view.selectedText() == "PDF viewer")

    host.clickPopupMenuItemWhenShown(PdfView.CtxCopy)
    view.showContextMenu({100, 100})
    host.pump()
    Swag.assert(Clipboard.getString() == "PDF viewer")
}
