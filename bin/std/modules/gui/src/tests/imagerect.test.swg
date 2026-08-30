#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// An empty imagerect is a valid, hit-testable window.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)
    defer host.shutdown()
    let img = ImageRect.create(&host.root, {20, 20, 120, 120})
    Swag.assert(img != null)
    Swag.assert(host.wndAt({40, 40}) == img)
    Swag.assert(!img.movie.isValid())
}

// Sprite-sheet geometry, exact-duration advancement, seeking, and pausing.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)
    defer host.shutdown()
    let image   = Pixel.Image.create(4, 2, .RGBA8)
    var texture = host.app.renderer.addImage(image)
    let atlas   = ImageList.create(texture, frameWidth: 2, frameHeight: 2)

    Swag.assert(atlas.isValid())
    Swag.assert(atlas.columnCount() == 2)
    Swag.assert(atlas.rowCount() == 1)
    Swag.assert(atlas.frameCount == 2)

    var movie: Movie
    movie.setSpriteSheet(atlas)
    Swag.assert(movie.isValid())
    Swag.assert(movie.frameIndex == 0)
    Swag.assert(movie.update(movie.frameDurationSeconds))
    Swag.assert(movie.frameIndex == 1)

    movie.setPaused(true)
    Swag.assert(!movie.update(movie.frameDurationSeconds))
    Swag.assert(movie.frameIndex == 1)

    movie.setPaused(false)
    movie.setFrameIndex(-10)
    Swag.assert(movie.frameIndex == 0)
    movie.setFrameIndex(10)
    Swag.assert(movie.frameIndex == 1)

    movie.clear()
    Swag.assert(!movie.isValid())
    Swag.assert(movie.frameCount == 0)
    Swag.assert(movie.cachesFrames)
    Swag.assert(movie.loops)

    host.app.renderer.removeTexture(&texture)
}

// ImageRect owns textures uploaded from Image values and releases them on clear.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)
    defer host.shutdown()
    let view = ImageRect.create(&host.root, {20, 20, 120, 120})
    view.setImage(Pixel.Image.create(2, 2, .RGBA8))
    Swag.assert(view.movie.isValid())
    Swag.assert(view.movie.isPaused)
    Swag.assert(view.uploadedTexture.isValid())

    view.clear()
    Swag.assert(!view.movie.isValid())
    Swag.assert(!view.uploadedTexture.isValid())
}

// Image-list content is either a paused image or a playing sprite sheet, by explicit API choice.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)
    defer host.shutdown()
    let image   = Pixel.Image.create(4, 2, .RGBA8)
    var texture = host.app.renderer.addImage(image)
    let atlas   = ImageList.create(texture, frameWidth: 2, frameHeight: 2)
    let view    = ImageRect.create(&host.root, {20, 20, 120, 120})

    view.setImageList(atlas)
    Swag.assert(view.movie.frameCount == 2)
    Swag.assert(view.movie.frameIndex == 0)
    Swag.assert(view.movie.isPaused)

    view.setSpriteSheet(atlas)
    Swag.assert(!view.movie.isPaused)
    view.setFrameIndex(50)
    Swag.assert(view.movie.frameIndex == 1)

    host.app.renderer.removeTexture(&texture)
}
