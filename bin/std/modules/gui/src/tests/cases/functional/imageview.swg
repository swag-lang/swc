#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

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
    Swag.assert(view.exchangeMovie(&movie))
    Swag.assert(view.movie.isValid() and not movie.isValid())
    Swag.assert(view.movie.frameCount == 1 and view.uploadedTexture.isValid())

    var replacement: Movie
    expect replacement.load(fileName)
    Swag.assert(view.exchangeMovie(&replacement))
    Swag.assert(view.movie.isValid() and replacement.isValid())
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let view  = ImageView.create(&host.root, {0, 0, 300, 200})
    var image = Image.create(100, 50, .RGBA8)
    image.fill(Argb.White)
    view.setImage(image)

    Swag.assert(view.isFitted)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 3, 0.001))

    view.actualSize()
    Swag.assert(not view.isFitted)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 1, 0.001))

    view.zoomIn()
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 1.25, 0.001))

    view.setPanOffset({37, -24})
    Swag.assert(view.panOffset == Math.Point{37, -24} and not view.isFitted)

    view.zoomToFit()
    Swag.assert(view.isFitted)
    Swag.assert(view.panOffset == Math.Point{})

    view.rotateClockwise()
    Swag.assert(view.rotationQuarterTurns == 1 and not view.isMirrored)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 2, 0.001))
    view.mirrorHorizontally()
    Swag.assert(view.rotationQuarterTurns == 3 and view.isMirrored)
    view.mirrorVertically()
    Swag.assert(view.rotationQuarterTurns == 3 and not view.isMirrored)
    view.rotateCounterClockwise()
    Swag.assert(view.rotationQuarterTurns == 2)
    view.resetTransform()
    Swag.assert(view.rotationQuarterTurns == 0 and not view.isMirrored)

    let textureHandle = view.uploadedTexture.handle
    image.fill(Argb.Red)
    view.updateImage(&image)
    Swag.assert(view.uploadedTexture.handle == textureHandle)
    Swag.assert(view.image.pixels[0] == 255 and view.image.pixels[1] == 0)
    Swag.assert(view.isFitted)

    view.clear()
    Swag.assert(not view.uploadedTexture.isValid() and view.rotationQuarterTurns == 0 and not view.isMirrored)
}

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
    Swag.assert(view.uploadedTexture.handle == textureHandle)
    Swag.assert(view.image.pixels.buffer == nextPixels)
    Swag.assert(view.image.pixels[0] == 255 and view.image.pixels[1] == 0)
    Swag.assert(next.pixels[0] == 255 and next.pixels[1] == 255)
    Swag.assert(view.isFitted)

    // A different geometry falls back to a copy and leaves the caller's picture alone.
    var wider = Image.create(120, 50, .RGBA8)
    wider.fill(Argb.Blue)
    let widerPixels = wider.pixels.buffer
    view.exchangeImage(&wider)
    Swag.assert(wider.pixels.buffer == widerPixels)
    Swag.assert(view.image.width == 120)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let view  = ImageView.create(&host.root, {0, 0, 300, 200})
    var image = Image.create(100, 50, .RGBA8)
    image.fill(Argb.Red)
    let pixels = image.pixels.buffer

    view.takeImage(&image)

    Swag.assert(not image.isValid())
    Swag.assert(view.image.pixels.buffer == pixels)
    Swag.assert(view.uploadedTexture.isValid() and view.isFitted)
}

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
    Swag.assert(view.hasContent() and view.isFitted)
    Swag.assert(view.contentSize().width == 40 and view.contentSize().height == 40)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 6, 0.001))

    // A row crossing the disc where its edge is slanted, so the edge covers more than one column
    // and its width is what the measure reports.
    const SlantedRow = 52's32
    var vectorRender = host.render(&host.root)
    let vectorEdge   = edgeSpread(&vectorRender, SlantedRow)

    view.setImage(drawing.rasterize(40, 40, 1))
    Swag.assert(not view.hasDrawing() and view.image.width == 40)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 6, 0.001))
    var rasterRender = host.render(&host.root)
    let rasterEdge   = edgeSpread(&rasterRender, SlantedRow)

    Swag.assert(vectorEdge > 0 and vectorEdge <= 8)
    Swag.assert(rasterEdge >= vectorEdge * 3)

    view.clear()
    Swag.assert(not view.hasContent() and not view.hasDrawing())
}

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
    Swag.assert(view.hasContent())
    Swag.assert(not view.image.isValid())
    Swag.assert(view.uploadedTexture.isValid() and view.uploadedTexture.pixelFormat == .Yuv420)
    Swag.assert(view.contentSize().width == 100 and view.contentSize().height == 50)
    Swag.assert(view.isFitted)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 3, 0.001))

    // The next picture of a playing stream reuses the texture the first one created.
    let textureHandle = view.uploadedTexture.handle
    view.updateVideoFrame(&picture)
    Swag.assert(view.uploadedTexture.handle == textureHandle)

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
    Swag.assert(view.contentSize().width == 60 and view.contentSize().height == 40)

    view.clear()
    Swag.assert(not view.hasContent())
    Swag.assert(not view.uploadedTexture.isValid())
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)

    let view  = ImageView.create(&host.root, {0, 0, 300, 200})
    var image = Image.create(100, 50, .RGBA8)
    image.fill(Argb.White)
    view.setImage(image)
    Swag.assert(view.isFitted)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 3, 0.001))

    // Two hundred columns across the same fifty rows: the fit halves.
    view.setDisplaySize(200, 50)
    Swag.assert(view.isFitted)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 1.5, 0.001))

    view.setDisplaySize(0, 0)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 3, 0.001))
}
