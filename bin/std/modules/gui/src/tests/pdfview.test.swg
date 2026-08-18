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
    @assert(view.pageCount() == 2 and view.pageIndex == 0)
    @assert(view.isFitted)

    let frame = host.render()
    @assert(frame.isValid())
    let evidence = countPageEvidence(&frame)
    @assert(evidence.paper > 10_000)
    @assert(evidence.ink > 50)
    @assert(!view.reportedPaintError)

    // Actual size is one PDF point per 1/96 logical inch, whatever the display resolution.
    view.actualSize()
    @assert(!view.isFitted)
    @assert(Math.isEqualEpsilon(view.effectiveZoom(), 96.0'f32 / 72.0, 0.001))
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
    @assert(!view.isFitted)
    @assert(Math.isEqualEpsilon(view.effectiveZoom(), fitted * 1.12, 0.001))

    // A deep zoom stays a transform change and still paints the page region under the view.
    view.setZoom(40)
    @assert(Math.isEqualEpsilon(view.effectiveZoom(), 40.0, 0.001))
    let frame = host.render()
    let evidence = countPageEvidence(&frame)
    @assert(evidence.paper > 10_000)
    @assert(!view.reportedPaintError)

    // The plain wheel scrolls instead of zooming.
    let before = view.panOffset.y
    host.mouseWheel({320, 210}, 120)
    @assert(view.panOffset.y == before + 60)
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
    @assert(view.hasTextures)
    @assert(view.imageTextures.count == 1)
    @assert(view.imageTextures[0].isValid())

    // A second frame reuses the uploaded texture instead of building a new one.
    let handle = view.imageTextures[0].handle
    discard host.render()
    @assert(view.imageTextures.count == 1)
    @assert(view.imageTextures[0].handle == handle)

    // Turning the page releases the previous page's textures.
    view.nextPage()
    @assert(!view.hasTextures)
    @assert(view.imageTextures.count == 0)
    discard host.render()
    @assert(view.hasTextures and view.imageTextures.count == 0)
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
    @assert(!view.hasTextures and view.imageTextures.count == 0)
}
