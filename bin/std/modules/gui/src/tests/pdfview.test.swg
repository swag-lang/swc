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

// The view rasterizes the page at the exact scale it is shown at, monitor scale included, and
// keeps the decoded page across zoom steps rather than decoding the document again.
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
    @assert(view.pageCount() == 2 and view.pageIndex == 0)
    @assert(view.isFitted)

    view.ensureRaster()
    @assert(view.texture.isValid())
    @assert(Math.isEqualEpsilon(view.rasterScale, view.effectiveZoom() * view.deviceScale(), 0.01))
    @assert(view.rasterScale > 2.8)

    // The whole page fits the raster budget, so the raster covers it completely.
    @assert(view.rasterRect.contains(Math.Rectangle{0, 0, view.pageSize().x, view.pageSize().y}))

    // Actual size is one PDF point per 1/96 logical inch, whatever the raster resolution.
    view.actualSize()
    @assert(!view.isFitted)
    @assert(Math.isEqualEpsilon(view.effectiveZoom(), 96.0'f32 / 72.0, 0.001))
}

// Past the raster budget only the visible region is rasterized, which is what bounds the cost
// of a deep zoom by the viewport rather than by the page.
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

    view.setZoom(40)
    view.ensureRaster()
    @assert(view.texture.isValid())
    @assert(Math.isEqualEpsilon(view.rasterScale, 60.0, 0.75))
    @assert(view.rasterRect.width < view.pageSize().x)
    @assert(view.rasterRect.height < view.pageSize().y)

    // A second pass over an unchanged viewport keeps the raster instead of producing it again.
    let covered = view.rasterRect
    view.ensureRaster()
    @assert(view.rasterRect.x == covered.x and view.rasterRect.y == covered.y)
    @assert(view.rasterRect.width == covered.width and view.rasterRect.height == covered.height)

    // Zooming back out re-rasterizes the whole page.
    view.zoomToFit()
    view.ensureRaster()
    @assert(view.rasterRect.contains(Math.Rectangle{0, 0, view.pageSize().x, view.pageSize().y}))
}

// A wheel burst scales the raster already on screen and produces one sharp replacement after the
// gesture settles, instead of rasterizing the PDF once for every wheel event.
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
    view.ensureRaster()
    let firstScale = view.rasterScale

    var wheel: MouseEvent
    wheel.kind       = .Wheel
    wheel.surfacePos = {320, 210}
    wheel.delta      = {0, 120}
    wheel.modifiers  = .Control
    view.sendEvent(&wheel)
    @assert(view.rasterTimer != null)
    view.ensureRaster()
    @assert(view.rasterScale == firstScale)

    wheel.delta.y = 120
    view.sendEvent(&wheel)
    @assert(view.rasterTimer != null)
    view.ensureRaster()
    @assert(view.rasterScale == firstScale)

    host.fireTimer(view.rasterTimer)
    @assert(view.rasterTimer == null)
    view.ensureRaster()
    @assert(view.rasterScale > firstScale)
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
    @assert(view.pageIndex == 1)
    view.nextPage()
    @assert(view.pageIndex == 1)
    view.previousPage()
    @assert(view.pageIndex == 0)
    view.previousPage()
    @assert(view.pageIndex == 0)
    @assert(pageChanges == 2)

    view.close()
    @assert(view.pageCount() == 0)
    @assert(!view.texture.isValid())
}
