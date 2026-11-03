#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// An empty `ImageRect` is a valid, hit-testable window.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)
    let img = ImageRect.create(&host.root, {20, 20, 120, 120})
    Swag.require(img != null)
    Swag.require(host.wndAt({40, 40}) == img)
    Swag.require(not img.movie.isValid())
}

// Sprite-sheet geometry, exact-duration advancement, seeking, and pausing.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)
    let image   = Pixel.Image.create(4, 2, .RGBA8)
    var texture = host.app.renderer.addImage(image)
    defer host.app.renderer.removeTexture(&texture)
    let atlas = ImageList.create(texture, frameWidth: 2, frameHeight: 2)

    Swag.require(atlas.isValid())
    Swag.require(atlas.columnCount() == 2)
    Swag.require(atlas.rowCount() == 1)
    Swag.require(atlas.frameCount == 2)

    var movie: Movie
    movie.setSpriteSheet(atlas)
    Swag.require(movie.isValid())
    Swag.require(movie.frameIndex == 0)
    var advanced = movie.update(movie.frameDurationSeconds)
    Swag.require(advanced)
    Swag.require(movie.frameIndex == 1)

    movie.setPaused(true)
    advanced = movie.update(movie.frameDurationSeconds)
    Swag.require(not advanced)
    Swag.require(movie.frameIndex == 1)

    movie.setPaused(false)
    movie.setFrameIndex(-10)
    Swag.require(movie.frameIndex == 0)
    movie.setFrameIndex(10)
    Swag.require(movie.frameIndex == 1)

    movie.clear()
    Swag.require(not movie.isValid())
    Swag.require(movie.frameCount == 0)
    Swag.require(movie.cachesFrames)
    Swag.require(movie.loops)
}

// ImageRect owns textures uploaded from Image values and releases them on clear.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)
    let view = ImageRect.create(&host.root, {20, 20, 120, 120})
    view.setImage(Pixel.Image.create(2, 2, .RGBA8))
    Swag.require(view.movie.isValid())
    Swag.require(view.movie.isPaused)
    Swag.require(view.uploadedTexture.isValid())

    view.clear()
    Swag.require(not view.movie.isValid())
    Swag.require(not view.uploadedTexture.isValid())
}

// Image-list content is either a paused image or a playing sprite sheet, by explicit API choice.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)
    let image   = Pixel.Image.create(4, 2, .RGBA8)
    var texture = host.app.renderer.addImage(image)
    defer host.app.renderer.removeTexture(&texture)
    let atlas = ImageList.create(texture, frameWidth: 2, frameHeight: 2)
    let view  = ImageRect.create(&host.root, {20, 20, 120, 120})

    view.setImageList(atlas)
    Swag.require(view.movie.frameCount == 2)
    Swag.require(view.movie.frameIndex == 0)
    Swag.require(view.movie.isPaused)

    view.setSpriteSheet(atlas)
    Swag.require(not view.movie.isPaused)
    view.setFrameIndex(50)
    Swag.require(view.movie.frameIndex == 1)
}
