using Core, Pdf, Pixel, Gui, Gui.Testing

private func createPdfFixture()->String
{
    let fileName = Gui.Testing.tempFilePath("filescope-pdf-", ".pdf")
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

#test
{
    let fileName = createPdfFixture()
    defer discard catch File.delete(fileName)

    var host: HeadlessHost
    host.setup(640, 450, dpiScale: 1.5)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let request = ViewerRequest{ViewerPluginApiVersion, &host.root, &host.root, fileName.toString()}
    var result: ViewerResult
    @assert(sFileScopePluginCreate(&request, &result))
    @assert(result.view != null and result.commands != null)
    @assert(Utf8.contains(result.details.toString(), "2 pages"))

    let view = cast(*PdfPluginView) result.view!
    view.resize(640, 420)
    view.applyLayout()
    @assert(view.rasterScale > 2.8)
    view.actualSize()
    @assert(Math.isEqualEpsilon(view.imageView.effectiveZoom(), (96.0'f32 / 72.0) / view.rasterScale, 0.001))

    // Zooming in rasterizes the page again instead of magnifying the pixels already on
    // screen: the page is vector art, so its sharpness must follow the zoom. The content
    // still grows by exactly the requested factor, and one raster pixel ends up covering at
    // most one physical pixel.
    let coarseScale = view.rasterScale
    let shownSize   = view.imageView.effectiveZoom() * coarseScale
    view.imageView.setZoom(view.imageView.effectiveZoom() * 4)
    @assert(view.rasterScale > coarseScale)
    @assert(Math.isEqualEpsilon(view.imageView.effectiveZoom() * view.rasterScale, shownSize * 4, 0.01))
    @assert(view.imageView.effectiveZoom() * view.deviceScale() <= 1.001)

    view.imageView.zoomToFit()
    @assert(view.reader.pageCount() == 2)
    @assert(view.imageView.isFitted)
    @assert(!view.previousButton.isEnabled() and view.nextButton.isEnabled())
    expect view.showPage(1)
    @assert(view.pageIndex == 1)
    @assert(view.previousButton.isEnabled() and !view.nextButton.isEnabled())
    Testing.assertContentFits(view)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("filescope-pdf-broken-", ".pdf")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "broken")

    var host: HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()
    let request = ViewerRequest{ViewerPluginApiVersion, &host.root, &host.root, fileName}
    var result: ViewerResult
    @assert(sFileScopePluginCreate(&request, &result))
    @assert(result.view == null and result.commands == null)
    @assert(!result.failureReason.isEmpty())
}
