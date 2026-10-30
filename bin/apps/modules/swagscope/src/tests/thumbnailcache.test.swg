#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// Cleanup removes only old cache-shaped files and leaves unrelated files alone.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-cache-prune-%", Guid64.random()))
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)
    let cached = Path.combine(root, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.png")
    let other  = Path.combine(root, "unrelated.png")
    discard expect File.writeAllText(cached, "cache")
    discard expect File.writeAllText(other, "keep")
    let now = Time.Timestamp.utcNow().ticks
    expect ThumbnailCache.prune(root, now)
    Swag.assert(File.exists(cached) and File.exists(other))
    expect ThumbnailCache.prune(root, now + 121 * Time.TicksPerDay)
    Swag.assert(not File.exists(cached) and File.exists(other))
}

// Cache identity follows both the source and application, and separates archive members.
#test
{
    let source = Path.combine(Env.getSpecialDirectory(.Temp), "thumbnail-source.bin")
    let app    = Path.combine(Env.getSpecialDirectory(.Temp), "thumbnail-app.bin")
    defer catch File.delete(source)
    defer catch File.delete(app)
    discard expect File.writeAllText(source, "one")
    discard expect File.writeAllText(app, "app")
    let key = expect ThumbnailCache.key(source, executable: app)
    defer catch File.delete(key)
    Swag.assert(key == (expect ThumbnailCache.key(source, executable: app)))
    Swag.assert(key != (expect ThumbnailCache.key(source, "member", app)))

    var image = Image.create(32, 24, .RGB8)
    image.fill(Color.fromRgb(255, 0, 0))
    expect ThumbnailCache.write(key, &image)
    let cached = ThumbnailCache.read(key)
    Swag.assert(cached.width == 32 and
                cached.height == 24 and
                cached.pixelColor(0, 0) == Color.fromRgb(255, 0, 0))
    discard expect File.writeAllText(key, "damaged cache")
    Swag.assert(not ThumbnailCache.read(key).isValid())
    expect ThumbnailCache.write(key, &image)
    Swag.assert(ThumbnailCache.read(key).isValid())

    discard expect File.writeAllText(source, "changed source")
    let changed = expect ThumbnailCache.key(source, executable: app)
    Swag.assert(changed != key and not ThumbnailCache.read(changed).isValid())
    discard expect File.writeAllText(app, "changed application")
    Swag.assert(changed != (expect ThumbnailCache.key(source, executable: app)))
}

// A cached preview survives a fresh operation and avoids launching the renderer process.
#test
{
    var host: Testing.HeadlessHost
    host.setup(64, 64)
    let source = Path.combine(Env.getSpecialDirectory(.Temp), "thumbnail-cached.txt")
    discard expect File.writeAllText(source, "cached document")
    defer catch File.delete(source)
    let key = expect ThumbnailCache.key(source)
    defer catch File.delete(key)
    var image = Image.create(24, 18, .RGB8)
    image.fill(Color.fromRgb(0, 0, 255))
    expect ThumbnailCache.write(key, &image)
    for 2
    {
        var preview: ExplorerPreview
        preview.path = source
        preview.start(&host.surfaceWnd)
        preview.wait()
        host.pump()
        Swag.assert(preview.image.isValid() and preview.error.isEmpty())
        Swag.assert(not preview.service.process.isRunning())
    }
}

// A local film frame is published from cache while its online details are still due. Once the
// provider result is stamped, revisiting the folder has no network work to schedule.
#test
{
    var host: Testing.HeadlessHost
    host.setup(64, 64)
    let source = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-staged-%.mkv", Guid64.random()))
    discard expect File.writeAllText(source, "fixture")
    defer catch File.delete(source)
    var buffer: ConcatBuffer
    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    expect encoder.writeAll(&buffer, ThumbnailSettings{onlineMovies: true})
    let settings = buffer.toString()
    let key = expect ThumbnailCache.key(source, settings: settings)
    defer catch File.delete(key)
    var frame = Image.create(24, 18, .RGB8)
    expect ThumbnailCache.write(key, &frame)

    var preview: ExplorerPreview
    preview.path = source
    preview.settings = settings
    preview.start(&host.surfaceWnd)
    preview.wait()
    host.pump()
    Swag.assert(preview.image.isValid() and preview.needsOnline)
    Swag.assert(not preview.service.process.isRunning())

    stampMovieCache(&frame)
    expect ThumbnailCache.write(key, &frame)
    var visited: ExplorerPreview
    visited.path = source
    visited.settings = settings
    visited.start(&host.surfaceWnd)
    visited.wait()
    host.pump()
    Swag.assert(visited.image.isValid() and not visited.needsOnline)
}

#test
{
    let folder = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-album-%", Guid64.random()))
    expect Directory.create(folder)
    defer catch Directory.delete(folder, recurse: true)
    let song = Path.combine(folder, "01.flac")
    let cover = Path.combine(folder, "cover.jpg")
    discard expect File.writeAllText(song, "fixture")
    Swag.assert(localAlbumArtwork(song).isEmpty())
    discard expect File.writeAllText(cover, "artwork fixture")
    Swag.assert(localAlbumArtwork(song) == cover)
}
