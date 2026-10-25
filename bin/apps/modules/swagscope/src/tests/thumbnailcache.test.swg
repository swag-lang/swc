#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

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
