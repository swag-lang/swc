#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Video, Gui, Viewers

// One cached preview can be framed in any display mode without decoding the source again.
#test
{
    var image = Image.create(128, 64, .RGB8)
    image.fill(Color.fromRgb(16, 16, 16))
    image.visitPixels()
    {
        if x >= 96 and y >= 8 and y < 56
        {
            let value = cast(u8, (x + y) % 2 == 0 ? 220 : 80)
            Memory.set(pix, value, 3)
        }
    }

    ThumbnailFraming.labelImage(&image)
    let path = Testing.tempFilePath("scope-framing-cache-", ".png")
    defer catch File.delete(path)
    expect ThumbnailCache.write(path, &image)
    let cached = ThumbnailCache.read(path)
    Swag.require(cached.isValid() and cached.width == 128 and cached.height == 64)
    let framing = ThumbnailFraming.fromImage(&cached)
    for mode in [Image.SmartCropMode.Attention, .Entropy]
    {
        let crop = framing.crop(128, 64, 1, .Square, mode)
        Swag.require(crop.x > 32 and crop.right() >= 120)
    }
    Swag.require(framing.crop(128, 64, 1, .Square, .Center) == Math.Rectangle{32, 0, 64, 64})
    Swag.require(framing.crop(128, 64, 1, .Square, .None) == Math.Rectangle{0, 0, 128, 64})
}

// Disabling the crop shows the edge of an existing preview without replacing its texture.
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, true, films: false, width: 880, height: 560)
    let explorer = unwrap window.explorer
    var image    = Image.create(160, 80, .RGB8)
    image.visitPixels()
    {
        pix[0] = x < 24 ? 220 : 0
        pix[1] = x < 24 ? 0 : 80
        pix[2] = x < 24 ? 0 : 140
    }

    let texture = host.app.renderer.addImage(&image)
    explorer.entries.add({name: "Preview.jpg", path: "Preview.jpg", texture: texture,
                          framing: ThumbnailFraming.analyze(&image), attempted: true})
    explorer.forceBoard(true, .Covers)
    showBoard(&host, window, "Pictures", "Scans")
    let grid = explorer.grid
    let tile = grid.tileRect(0)
    let left = grid.localToSurface(Math.Point{tile.x + grid.themeMetrics().fileTile_Inset + 3, tile.vertCenter()})
    let x    = cast(s32, left.x)
    let y    = cast(s32, left.y)

    window.sendCommandEvent(ViewerCommands.ThumbnailCrops[2])
    let cover = host.renderSettled(&host.surfaceWnd)
    Swag.require(cover.pixelColor(x, y).b > 100 and cover.pixelColor(x, y).r < 10)

    window.sendCommandEvent(ViewerCommands.ThumbnailCrops[3])
    let whole = host.renderSettled(&host.surfaceWnd)
    Swag.require(whole.pixelColor(x, y).r > 200 and whole.pixelColor(x, y).b < 10)
    Swag.require(explorer.entries[0].texture.handle == texture.handle)
}

// Portrait video inside a wide canvas can have bands wider than a quarter of the frame.
#test
{
    var image = Image.create(160, 90, .RGB8)
    image.fill(Color.fromRgb(8, 8, 8))
    for y in 90
    {
        for x in 55 until 105
        {
            let pixel = image.pixels.storage() + cast(u64, y * image.rowStride + x * 3)
            Memory.set(pixel, 160, 3)
        }
    }

    Film.trimLetterbox(&image)
    Swag.require(image.width == 50 and image.height == 90)
    var candidate: Film.ThumbnailCandidate
    candidate.image = Image.create(120, 90, .RGB8)
    candidate.image.fill(Color.fromRgb(56, 189, 248))
    candidate.prepare(320, 4.0 / 3.0)
    Swag.require(candidate.image.width == 160 and candidate.image.height == 90)
}

// When every cheap sample is black, the bounded exact-frame fallback still finds late content.
#test
{
    let path = Testing.tempFilePath("scope-late-thumbnail-", ".y4m")
    defer catch File.delete(path)
    for level in [0'u8, 13]
    {
        var clip = expect Clip.create(32, 24, expect FrameRate.create(24, 1))
        for index in 60
        {
            var image = Image.create(32, 24, .RGB8)
            image.fill(index == 59 ? Color.fromRgb(56, 189, 248) : Color.fromRgb(level, level, level))
            expect clip.addFrame(image)
        }

        expect clip.save(path)
        let thumbnail = expect Film.loadThumbnail(path)
        let colour    = thumbnail.pixelColor(16, 12)
        Swag.require(colour.g > 160 and colour.b > 200)
    }
}
