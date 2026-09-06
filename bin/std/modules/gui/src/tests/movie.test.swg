#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

func movieFixture(name: string)->String => String.from(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas", name))

#test
{
    for name in ["imageset-animation.webp", "imageset-animation.apng"]
    {
        var movie: Movie
        expect movie.load(movieFixture(name).toString())
        Swag.assert(movie.isAnimated() and movie.frameCount == 3 and movie.frameIndex == 0)
        Swag.assert(!movie.isPaused and movie.currentFrameDuration() == 0.04)
        Swag.assert(movie.update(0.04) and movie.frameIndex == 1)
        Swag.assert(!movie.update(0.05) and movie.frameIndex == 1)
        Swag.assert(movie.update(0.071) and movie.frameIndex == 2)
        discard movie.update(0.08)
        Swag.assert(movie.isPaused and movie.frameIndex == 2)
        movie.setFrameIndex(0)
        movie.usesEncodedLoops = false
        movie.setPaused(false)
        discard movie.update(0.241)
        Swag.assert(!movie.isPaused and movie.frameIndex == 0)
        movie.setPaused(true)
        discard movie.update(0)
        Swag.assert(!movie.update(10) and movie.frameIndex == 0)
    }
}

#test
{
    var movie: Movie
    movie.maxCacheBytes = 64
    expect movie.load(movieFixture("imageset-animation.webp").toString())
    expect movie.prepareCache()
    Swag.assert(movie.cachedBytes == 64 and movie.cachedFrames.count == 1)
    movie.setFrameIndex(2)
    Swag.assert(movie.frameIndex == 2)

    // The independent WebP decoder places this frame's blue square in the lower left.
    // Disposal clears the rest of the canvas, including the upper-left pixel.
    for y in 4 do
        for x in 4 do
            Swag.assert(movie.frame.pixelColor(x, y).argb == (x < 2 and y >= 2 ? 0xFF0000FF : 0))
    movie.setFrameIndex(0)
    Swag.assert(movie.frameIndex == 0 and movie.frame.pixelColor(0, 0).r == 255)
    Swag.assert(movie.cachedBytes == 64)

    var host: Testing.HeadlessHost
    host.setup(300, 200)
    defer host.shutdown()
    let view = ImageView.create(&host.root, {0, 0, 300, 200})
    expect view.loadMovie(movieFixture("imageset-icons.ico").toString())
    Swag.assert(!view.movie.isAnimated() and view.movie.isPaused and view.movie.frameIndex == 1)
    Swag.assert(view.uploadedTexture.width == 4)
    view.setFrameIndex(0)
    Swag.assert(view.uploadedTexture.width == 2 and view.movie.frame.pixelColor(0, 0).r == 255)
    view.setFrameIndex(1)
    Swag.assert(view.uploadedTexture.width == 4 and view.movie.frame.pixelColor(0, 0).b == 255)
}
