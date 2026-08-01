#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// An empty imagerect is a valid, hit-testable window.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)

    let img = ImageRect.create(&host.root, {20, 20, 120, 120})
    @assert(img != null)
    @assert(host.wndAt({40, 40}) == img)
    @assert(!img.movie.isValid())

    host.shutdown()
}

// Sprite-sheet geometry, exact-duration advancement, seeking, and pausing.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)

    let image = Pixel.Image.create(4, 2, .RGBA8)
    var texture = host.app.renderer.addImage(image)
    let atlas = ImageList.create(texture, frameWidth: 2, frameHeight: 2)

    @assert(atlas.isValid())
    @assert(atlas.columnCount() == 2)
    @assert(atlas.rowCount() == 1)
    @assert(atlas.frameCount == 2)

    var movie: Movie
    movie.setSpriteSheet(atlas)
    @assert(movie.isValid())
    @assert(movie.frameIndex == 0)
    @assert(movie.update(movie.frameDurationSeconds))
    @assert(movie.frameIndex == 1)

    movie.setPaused(true)
    @assert(!movie.update(movie.frameDurationSeconds))
    @assert(movie.frameIndex == 1)

    movie.setPaused(false)
    movie.setFrameIndex(-10)
    @assert(movie.frameIndex == 0)
    movie.setFrameIndex(10)
    @assert(movie.frameIndex == 1)

    movie.clear()
    @assert(!movie.isValid())
    @assert(movie.frameCount == 0)
    @assert(movie.cachesFrames)
    @assert(movie.loops)

    host.app.renderer.removeTexture(&texture)
    host.shutdown()
}

// ImageRect owns textures uploaded from Image values and releases them on clear.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)

    let view = ImageRect.create(&host.root, {20, 20, 120, 120})
    view.setImage(Pixel.Image.create(2, 2, .RGBA8))
    @assert(view.movie.isValid())
    @assert(view.movie.isPaused)
    @assert(view.uploadedTexture.isValid())

    view.clear()
    @assert(!view.movie.isValid())
    @assert(!view.uploadedTexture.isValid())

    host.shutdown()
}

// Image-list content is either a paused image or a playing sprite sheet, by explicit API choice.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)

    let image = Pixel.Image.create(4, 2, .RGBA8)
    var texture = host.app.renderer.addImage(image)
    let atlas = ImageList.create(texture, frameWidth: 2, frameHeight: 2)
    let view = ImageRect.create(&host.root, {20, 20, 120, 120})

    view.setImageList(atlas)
    @assert(view.movie.frameCount == 2)
    @assert(view.movie.frameIndex == 0)
    @assert(view.movie.isPaused)

    view.setSpriteSheet(atlas)
    @assert(!view.movie.isPaused)
    view.setFrameIndex(50)
    @assert(view.movie.frameIndex == 1)

    host.app.renderer.removeTexture(&texture)
    host.shutdown()
}
