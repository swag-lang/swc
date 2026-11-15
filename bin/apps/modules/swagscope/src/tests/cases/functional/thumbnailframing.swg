#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Video, Gui, Viewers

// A tall crop keeps an off-centre subject; a wide crop follows vertical attention.
#test
{
    var framing: ThumbnailFraming
    framing.horizontal[25] = 255
    framing.vertical[5]    = 255
    let portrait = framing.crop(320, 180, 0.7)
    Swag.require(portrait.x <= 250 and portrait.right() >= 260)
    Swag.require(portrait.x > 100)
    let landscape = framing.crop(180, 320, 2)
    Swag.require(landscape.y < 60 and landscape.bottom() >= 60)
    var image = Image.create(32, 24, .RGB8)
    image.fill(Color.fromRgb(16, 16, 16))
    framing.label(&image)
    let path = Testing.tempFilePath("scope-framing-cache-", ".png")
    defer catch File.delete(path)
    expect ThumbnailCache.write(path, &image)
    let cached = ThumbnailCache.read(path)
    Swag.require(cached.isValid())
    let restored = ThumbnailFraming.fromImage(&cached)
    Swag.require(restored.horizontal[25] == 255 and restored.vertical[5] == 255)
    Swag.require(restored.crop(320, 180, 0.7) == portrait)
}

// Analysis, rather than a fixed centre, locates detailed content near the edge of a photograph.
#test
{
    var image = Image.create(128, 64, .RGB8)
    image.fill(Color.fromRgb(16, 16, 16))
    for y in 8 until 56
    {
        for x in 96 until 120
        {
            let pixel = image.pixels.storage() + cast(u64, y * image.rowStride + x * 3)
            let value = cast(u8, (x + y) % 2 == 0 ? 220 : 80)
            Memory.set(pixel, value, 3)
        }
    }

    let framing = ThumbnailFraming.analyze(&image)
    let crop    = framing.crop(128, 64, 0.7)
    Swag.require(crop.x > 75 and crop.right() >= 120)
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
