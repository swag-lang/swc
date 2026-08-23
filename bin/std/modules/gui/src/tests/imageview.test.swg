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
