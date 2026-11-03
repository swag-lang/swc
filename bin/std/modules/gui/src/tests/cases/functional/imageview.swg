#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A movie decoded away from the widget is published by ownership exchange only.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    var image = Image.create(4, 2, .RGBA8)
    image.fill(Argb.White)
    let fileName = Testing.tempFilePath("gui-imageview-", ".gif")
    defer discard catch File.delete(fileName)
    let encoded = expect image.encode("prepared.gif")
    expect File.writeAllBytes(fileName, unwrap encoded.toSlice())
    var movie: Movie
    expect movie.load(fileName)

    let view = ImageView.create(&host.root, {0, 0, 300, 200})
    Swag.require(view.exchangeMovie(&movie))
    Swag.require(view.movie.isValid() and not movie.isValid())
    Swag.require(view.movie.frameCount == 1 and view.uploadedTexture.isValid())

    var replacement: Movie
    expect replacement.load(fileName)
    Swag.require(view.exchangeMovie(&replacement))
    Swag.require(view.movie.isValid() and replacement.isValid())
}

// A still image starts fitted, supports explicit zoom, and releases its renderer texture cleanly.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let view  = ImageView.create(&host.root, {0, 0, 300, 200})
    var image = Image.create(100, 50, .RGBA8)
    image.fill(Argb.White)
    view.setImage(image)

    Swag.require(view.isFitted)
    Swag.require(Math.isEqualEpsilon(view.effectiveZoom(), 3, 0.001))

    view.actualSize()
    Swag.require(not view.isFitted)
    Swag.require(Math.isEqualEpsilon(view.effectiveZoom(), 1, 0.001))

    view.zoomIn()
    Swag.require(Math.isEqualEpsilon(view.effectiveZoom(), 1.25, 0.001))

    view.setPanOffset({37, -24})
    Swag.require(view.panOffset == Math.Point{37, -24} and not view.isFitted)

    view.zoomToFit()
    Swag.require(view.isFitted)
    Swag.require(view.panOffset == Math.Point{})

    view.rotateClockwise()
    Swag.require(view.rotationQuarterTurns == 1 and not view.isMirrored)
    Swag.require(Math.isEqualEpsilon(view.effectiveZoom(), 2, 0.001))
    view.mirrorHorizontally()
    Swag.require(view.rotationQuarterTurns == 3 and view.isMirrored)
    view.mirrorVertically()
    Swag.require(view.rotationQuarterTurns == 3 and not view.isMirrored)
    view.rotateCounterClockwise()
    Swag.require(view.rotationQuarterTurns == 2)
    view.resetTransform()
    Swag.require(view.rotationQuarterTurns == 0 and not view.isMirrored)

    let textureHandle = view.uploadedTexture.handle
    image.fill(Argb.Red)
    view.updateImage(&image)
    Swag.require(view.uploadedTexture.handle == textureHandle)
    Swag.require(view.image.pixels[0] == 255 and view.image.pixels[1] == 0)
    Swag.require(view.isFitted)

    view.clear()
    Swag.require(not view.uploadedTexture.isValid() and view.rotationQuarterTurns == 0 and not view.isMirrored)
}

// Exchanging a picture keeps the texture and the view, and hands the previous pixels back.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let view  = ImageView.create(&host.root, {0, 0, 300, 200})
    var image = Image.create(100, 50, .RGBA8)
    image.fill(Argb.White)
    view.setImage(image)

    let textureHandle = view.uploadedTexture.handle
    var next = Image.create(100, 50, .RGBA8)
    next.fill(Argb.Red)
    let nextPixels = next.pixels.buffer
    view.exchangeImage(&next)

    // The view shows the new picture, and the caller now owns the one that just left it.
    Swag.require(view.uploadedTexture.handle == textureHandle)
    Swag.require(view.image.pixels.buffer == nextPixels)
    Swag.require(view.image.pixels[0] == 255 and view.image.pixels[1] == 0)
    Swag.require(next.pixels[0] == 255 and next.pixels[1] == 255)
    Swag.require(view.isFitted)

    // A different geometry falls back to a copy and leaves the caller's picture alone.
    var wider = Image.create(120, 50, .RGBA8)
    wider.fill(Argb.Blue)
    let widerPixels = wider.pixels.buffer
    view.exchangeImage(&wider)
    Swag.require(wider.pixels.buffer == widerPixels)
    Swag.require(view.image.width == 120)
}

// A one-shot decode can hand its storage to the view without allocating a second pixel buffer.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let view  = ImageView.create(&host.root, {0, 0, 300, 200})
    var image = Image.create(100, 50, .RGBA8)
    image.fill(Argb.Red)
    let pixels = image.pixels.buffer

    view.takeImage(&image)

    Swag.require(not image.isValid())
    Swag.require(view.image.pixels.buffer == pixels)
    Swag.require(view.uploadedTexture.isValid() and view.isFitted)
}

// Counts the pixels of one row that sit between the two plateaus of an opaque red-on-white
// picture, which is how wide the edges crossing that row are drawn.
private func edgeSpread(image: *Image, row: s32)->s32
{
    var result = 0's32
    for x in image.width
    {
        let green = cast(s32, image.pixelColor(x, row).g)
        if green > 8 and green < 247 do
            result += 1
    }

    return result
}

// A vector document is drawn at the scale the view shows it at, so a magnified drawing is drawn
// again rather than magnified: its edges stay a pixel wide however far the view zooms in.
//
// The same document rasterized once at its view-box size and shown through the picture path is
// the control: there the zoom magnifies pixels, and every edge is spread over the zoom factor.
// The document is opaque and covers its whole view box, so the only pixels between the two
// plateaus of the measured row are the two edges of the disc.
#test
{
    const Source = """\
        <svg viewBox='0 0 40 40'><rect width='40' height='40' fill='#FFFFFF'/>\
        <circle cx='20' cy='20' r='16' fill='#FF0000'/></svg>"""

    var host: Testing.HeadlessHost
    host.setup(240, 240)

    let drawing = expect Svg.Drawing.parse(Source)
    let view    = ImageView.create(&host.root, {0, 0, 240, 240})

    view.setDrawing(drawing)
    Swag.require(view.hasContent() and view.isFitted)
    Swag.require(view.contentSize().width == 40 and view.contentSize().height == 40)
    Swag.require(Math.isEqualEpsilon(view.effectiveZoom(), 6, 0.001))

    // A row crossing the disc where its edge is slanted, so the edge covers more than one column
    // and its width is what the measure reports.
    const SlantedRow = 52's32
    var vectorRender = host.render(&host.root)
    let vectorEdge   = edgeSpread(&vectorRender, SlantedRow)

    view.setImage(drawing.rasterize(40, 40, 1))
    Swag.require(not view.hasDrawing() and view.image.width == 40)
    Swag.require(Math.isEqualEpsilon(view.effectiveZoom(), 6, 0.001))
    var rasterRender = host.render(&host.root)
    let rasterEdge   = edgeSpread(&rasterRender, SlantedRow)

    Swag.require(vectorEdge > 0 and vectorEdge <= 8)
    Swag.require(rasterEdge >= vectorEdge * 3)

    view.clear()
    Swag.require(not view.hasContent() and not view.hasDrawing())
}

// A video frame reaches the view as planes: the texture is kept across frames, the geometry comes
// from the picture even though the view holds no image, and the next size starts a new texture.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let view = ImageView.create(&host.root, {0, 0, 300, 200})

    var planes: Array'u8
    planes.resize(100 * 50 + 50 * 25 * 2)
    Memory.set(planes.storage(), 235, 100 * 50)
    Memory.set(planes.storage() + 100 * 50, 128, 50 * 25 * 2)

    let picture = YuvPlanarView{
        luma: planes.storage(),
        chromaB: planes.storage() + 100 * 50,
        chromaR: planes.storage() + 100 * 50 + 50 * 25,
        lumaStride: 100,
        chromaStride: 50,
        width: 100,
        height: 50}

    view.updateVideoFrame(&picture)
    Swag.require(view.hasContent())
    Swag.require(not view.image.isValid())
    Swag.require(view.uploadedTexture.isValid() and view.uploadedTexture.pixelFormat == .Yuv420)
    Swag.require(view.contentSize().width == 100 and view.contentSize().height == 50)
    Swag.require(view.isFitted)
    Swag.require(Math.isEqualEpsilon(view.effectiveZoom(), 3, 0.001))

    // The next picture of a playing stream reuses the texture the first one created.
    let textureHandle = view.uploadedTexture.handle
    view.updateVideoFrame(&picture)
    Swag.require(view.uploadedTexture.handle == textureHandle)

    // A stream that changes size, or a view that is cleared, starts over.
    let smaller = YuvPlanarView{
        luma: planes.storage(),
        chromaB: planes.storage() + 100 * 50,
        chromaR: planes.storage() + 100 * 50 + 50 * 25,
        lumaStride: 100,
        chromaStride: 50,
        width: 60,
        height: 40}
    view.updateVideoFrame(&smaller)
    Swag.require(view.contentSize().width == 60 and view.contentSize().height == 40)

    view.clear()
    Swag.require(not view.hasContent())
    Swag.require(not view.uploadedTexture.isValid())
}

// A picture whose samples are not square is laid out and fitted with the size it is shown at,
// while the storage it was given keeps every column it holds.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let view  = ImageView.create(&host.root, {0, 0, 300, 200})
    var image = Image.create(100, 50, .RGBA8)
    image.fill(Argb.White)
    view.setImage(image)
    Swag.require(view.isFitted)
    Swag.require(Math.isEqualEpsilon(view.effectiveZoom(), 3, 0.001))

    // Two hundred columns across the same fifty rows: the fit halves.
    view.setDisplaySize(200, 50)
    Swag.require(view.isFitted)
    Swag.require(Math.isEqualEpsilon(view.effectiveZoom(), 1.5, 0.001))

    view.setDisplaySize(0, 0)
    Swag.require(Math.isEqualEpsilon(view.effectiveZoom(), 3, 0.001))
}
