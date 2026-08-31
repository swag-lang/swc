#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A movie decoded away from the widget is published by ownership exchange only.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()

    var image = Image.create(4, 2, .RGBA8)
    image.fill(Argb.White)
    let fileName = Testing.tempFilePath("gui-imageview-", ".gif")
    defer discard catch File.delete(fileName)
    let encoded = expect image.encode("prepared.gif")
    expect File.writeAllBytes(fileName, encoded.toSlice()!)
    var movie: Movie
    expect movie.load(fileName)

    let view = ImageView.create(&host.root, {0, 0, 300, 200})
    view.exchangeMovie(&movie)
    Swag.assert(view.movie.isValid() and !movie.isValid())
    Swag.assert(view.movie.frameCount == 1 and view.uploadedTexture.isValid())

    var replacement: Movie
    expect replacement.load(fileName)
    view.exchangeMovie(&replacement)
    Swag.assert(view.movie.isValid() and replacement.isValid())
}

// A still image starts fitted, supports explicit zoom, and releases its renderer texture cleanly.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()

    let view  = ImageView.create(&host.root, {0, 0, 300, 200})
    var image = Image.create(100, 50, .RGBA8)
    image.fill(Argb.White)
    view.setImage(image)

    Swag.assert(view.isFitted)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 3, 0.001))

    view.actualSize()
    Swag.assert(!view.isFitted)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 1, 0.001))

    view.zoomIn()
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 1.25, 0.001))

    view.zoomToFit()
    Swag.assert(view.isFitted)
    Swag.assert(view.panOffset == Math.Point{})

    view.rotateClockwise()
    Swag.assert(view.rotationQuarterTurns == 1 and !view.isMirrored)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 2, 0.001))
    view.mirrorHorizontally()
    Swag.assert(view.rotationQuarterTurns == 3 and view.isMirrored)
    view.mirrorVertically()
    Swag.assert(view.rotationQuarterTurns == 3 and !view.isMirrored)
    view.rotateCounterClockwise()
    Swag.assert(view.rotationQuarterTurns == 2)
    view.resetTransform()
    Swag.assert(view.rotationQuarterTurns == 0 and !view.isMirrored)

    let textureHandle = view.uploadedTexture.handle
    image.fill(Argb.Red)
    view.updateImage(&image)
    Swag.assert(view.uploadedTexture.handle == textureHandle)
    Swag.assert(view.image.pixels[0] == 255 and view.image.pixels[1] == 0)
    Swag.assert(view.isFitted)

    view.clear()
    Swag.assert(!view.uploadedTexture.isValid() and view.rotationQuarterTurns == 0 and !view.isMirrored)
}

// Exchanging a picture keeps the texture and the view, and hands the previous pixels back.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()

    let view  = ImageView.create(&host.root, {0, 0, 300, 200})
    var image = Image.create(100, 50, .RGBA8)
    image.fill(Argb.White)
    view.setImage(image)

    let textureHandle = view.uploadedTexture.handle
    var next          = Image.create(100, 50, .RGBA8)
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

// Rotation and reflection are paint-time view operations: the source keeps its dimensions and
// bytes while the asymmetric pattern proves that the composed transform reaches the renderer.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 160)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let pixels: [24] u8 = [
        255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255,
        255, 255, 0, 255, 255, 0, 255, 255, 0, 255, 255, 255]
    let source   = Image.create(3, 2, .RGBA8, pixels)
    let original = ImageView.create(&host.root, {0, 0, 130, 160})
    original.setImage(source)
    original.setDisplaySize(90, 60)
    original.actualSize()
    let view = ImageView.create(&host.root, {130, 0, 130, 160})
    view.setImage(source)
    view.setDisplaySize(90, 60)
    view.actualSize()
    view.rotateClockwise()
    view.mirrorHorizontally()

    Swag.assert(view.image.width == 3 and view.image.height == 2)
    Swag.assert(view.rotationQuarterTurns == 3 and view.isMirrored)
    var rendered = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&rendered, "imageview.transform")
}

// A video frame reaches the view as planes: the texture is kept across frames, the geometry comes
// from the picture even though the view holds no image, and the next size starts a new texture.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()

    let view = ImageView.create(&host.root, {0, 0, 300, 200})

    var planes: Array'u8
    planes.resize(100 * 50 + 50 * 25 * 2)
    Memory.set(planes.buffer!, 235, 100 * 50)
    Memory.set(planes.buffer! + 100 * 50, 128, 50 * 25 * 2)

    let picture = Yuv420View{
        luma: planes.buffer!,
        chromaB: planes.buffer! + 100 * 50,
        chromaR: planes.buffer! + 100 * 50 + 50 * 25,
        lumaStride: 100,
        chromaStride: 50,
        width: 100,
        height: 50}

    view.updateVideoFrame(&picture)
    Swag.assert(view.hasContent())
    Swag.assert(!view.image.isValid())
    Swag.assert(view.uploadedTexture.isValid() and view.uploadedTexture.pixelFormat == .Yuv420)
    Swag.assert(view.contentSize().width == 100 and view.contentSize().height == 50)
    Swag.assert(view.isFitted)
    Swag.assert(Math.isEqualEpsilon(view.effectiveZoom(), 3, 0.001))

    // The next picture of a playing stream reuses the texture the first one created.
    let textureHandle = view.uploadedTexture.handle
    view.updateVideoFrame(&picture)
    Swag.assert(view.uploadedTexture.handle == textureHandle)

    // A stream that changes size, or a view that is cleared, starts over.
    let smaller = Yuv420View{
        luma: planes.buffer!,
        chromaB: planes.buffer! + 100 * 50,
        chromaR: planes.buffer! + 100 * 50 + 50 * 25,
        lumaStride: 100,
        chromaStride: 50,
        width: 60,
        height: 40}
    view.updateVideoFrame(&smaller)
    Swag.assert(view.contentSize().width == 60 and view.contentSize().height == 40)

    view.clear()
    Swag.assert(!view.hasContent())
    Swag.assert(!view.uploadedTexture.isValid())
}

// A picture whose samples are not square is laid out and fitted with the size it is shown at,
// while the storage it was given keeps every column it holds.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()

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
