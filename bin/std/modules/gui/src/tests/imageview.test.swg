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

    view.clear()
    @assert(!view.uploadedTexture.isValid())
}
