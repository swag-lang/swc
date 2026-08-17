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
    host.setup(960, 680)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let request = ViewerRequest{ViewerPluginApiVersion, &host.root, &host.root, fileName.toString()}
    var result: ViewerResult
    @assert(sFileScopePluginCreate(&request, &result))
    @assert(result.view != null and result.commands != null)
    @assert(Utf8.contains(result.details.toString(), "2 pages"))

    let view = cast(*PdfPluginView) result.view!
    view.resize(960, 640)
    view.applyLayout()
    @assert(view.document.pages.count == 2)
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
    let view = PdfPluginView.create(&host.root, &host.root, fileName)
    view.resize(640, 380)
    view.applyLayout()
    @assert(!view.imageView.isLocallyVisible())
    @assert(!view.commands.isLocallyVisible())
    Testing.assertContentFits(view)
}
