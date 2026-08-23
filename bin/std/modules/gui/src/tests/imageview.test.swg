#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

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

    @assert(view.isFitted)
    @assert(Math.isEqualEpsilon(view.effectiveZoom(), 3, 0.001))

    view.actualSize()
    @assert(!view.isFitted)
    @assert(Math.isEqualEpsilon(view.effectiveZoom(), 1, 0.001))

    view.zoomIn()
    @assert(Math.isEqualEpsilon(view.effectiveZoom(), 1.25, 0.001))

    view.zoomToFit()
    @assert(view.isFitted)
    @assert(view.panOffset == Math.Point{})

    let textureHandle = view.uploadedTexture.handle
    image.fill(Argb.Red)
    view.updateImage(&image)
    @assert(view.uploadedTexture.handle == textureHandle)
    @assert(view.image.pixels[0] == 255 and view.image.pixels[1] == 0)
    @assert(view.isFitted)

    view.clear()
    @assert(!view.uploadedTexture.isValid())
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
    @assert(view.uploadedTexture.handle == textureHandle)
    @assert(view.image.pixels.buffer == nextPixels)
    @assert(view.image.pixels[0] == 255 and view.image.pixels[1] == 0)
    @assert(next.pixels[0] == 255 and next.pixels[1] == 255)
    @assert(view.isFitted)

    // A different geometry falls back to a copy and leaves the caller's picture alone.
    var wider = Image.create(120, 50, .RGBA8)
    wider.fill(Argb.Blue)
    let widerPixels = wider.pixels.buffer
    view.exchangeImage(&wider)
    @assert(wider.pixels.buffer == widerPixels)
    @assert(view.image.width == 120)
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
    @assert(view.hasContent())
    @assert(!view.image.isValid())
    @assert(view.uploadedTexture.isValid() and view.uploadedTexture.pixelFormat == .Yuv420)
    @assert(view.contentSize().width == 100 and view.contentSize().height == 50)
    @assert(view.isFitted)
    @assert(Math.isEqualEpsilon(view.effectiveZoom(), 3, 0.001))

    // The next picture of a playing stream reuses the texture the first one created.
    let textureHandle = view.uploadedTexture.handle
    view.updateVideoFrame(&picture)
    @assert(view.uploadedTexture.handle == textureHandle)

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
    @assert(view.contentSize().width == 60 and view.contentSize().height == 40)

    view.clear()
    @assert(!view.hasContent())
    @assert(!view.uploadedTexture.isValid())
}
