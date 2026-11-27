#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Core.Errors

func pngAnimationPath()->String
{
    let name = Format.toString("png-animation-%.apng", Guid64.random())
    return Path.combine(Env.getSpecialDirectory(.Temp).toString(), name)
}

// Check both a pending control chunk and one already committed to the file.
#test
{
    for interlace in [false, true]
    {
        let width  = interlace ? 19 : 257
        let height = interlace ? 11 : 129
        let path   = pngAnimationPath()
        defer discard catch File.delete(path)

        var first = Image.create(width, height, .RGBA8)
        for index in first.pixels.count
        {
            first.pixels[index] = cast(u8, ((index * 13 + index / 23) % 256))
        }

        var second = first.convertedTo(.BGRA8)
        second.pixels[2] ^= 255
        second.pixels[3] ^= 127
        var third = first.convertedTo(.RGB8)
        third.pixels[0] ^= 29

        let frames   = [&first, &second, &third]
        let times    = [17_u16, 1001, 0]
        let rates    = [1000_u16, 30000, 1000]
        let loop     = interlace ? 4_u32 : 0_u32
        let level    = interlace ? Compress.Deflate.CompressionLevel.Default : .NoCompression
        var writer = expect Png.AnimationWriter.create(path, width, height, {
            loopCount: loop, png: {compressionLevel: level, interlace: interlace}})
        for index in frames.count
        {
            expect writer.addFrame(frames[index][], times[index], rates[index])
        }

        expect writer.end()
        expect writer.end()

        let still = expect Image.load(path)
        Swag.require(still.width == width and still.height == height and still.pixelFormat == .RGBA8)
        Swag.require(Slice.equals(still.pixels.toSlice(), first.pixels.toSlice()))

        var reader = expect ImageReader.load(path)
        Swag.require(reader.info.canvasWidth == width and reader.info.canvasHeight == height)
        Swag.require(reader.info.loopCount == loop and reader.info.frames.count == frames.count)
        for index in [2_u32, 0, 1, 2]
        {
            let actual = expect reader.read(index)
            let expected = frames[index].convertedTo(.RGBA8)
            Swag.require(Slice.equals(actual.pixels.toSlice(), expected.pixels.toSlice()))
            let info = reader.info.frames[index]
            Swag.require(info.width == width and info.height == height)
            Swag.require(info.disposal == .Keep and info.blend == .Replace)
            Swag.require(info.durationSeconds == cast(f64, times[index]) / rates[index])
        }
    }
}

// Alpha-only changes and repeated frames keep exact pixels and timing after cropping.
#test
{
    for interlace in [false, true]
    {
        const Width = 37
        const Height = 17
        let path = pngAnimationPath()
        defer discard catch File.delete(path)

        var first = Image.create(Width, Height, .RGBA8)
        first.fill(Color.fromArgb(61, 25, 83, 132))
        var second = first
        second.pixels[(Height - 1 - 3) * second.rowStride + 7 * 4 + 3] = 0
        second.pixels[(Height - 1 - 8) * second.rowStride + 19 * 4 + 3] = 255
        var writer = expect Png.AnimationWriter.create(path, Width, Height, {png: {interlace: interlace}})
        expect writer.addFrame(first, 13)
        expect writer.addFrame(second, 17)
        expect writer.addFrame(second, 43)
        expect writer.addFrame(first, 19)
        expect writer.end()

        var reader = expect ImageReader.load(path)
        Swag.require(reader.info.frames.count == 4)
        let firstRect = reader.info.frames[0]
        Swag.require(firstRect.x == 0 and firstRect.y == 0 and firstRect.width == Width and firstRect.height == Height)
        for index in [1, 3]
        {
            let rectangle = reader.info.frames[index]
            Swag.require(rectangle.x == 7 and rectangle.y == 3 and rectangle.width == 13 and rectangle.height == 6)
        }

        let unchanged = reader.info.frames[2]
        Swag.require(unchanged.x == 0 and unchanged.y == 0 and unchanged.width == 1 and unchanged.height == 1)
        Swag.require(unchanged.durationSeconds == 0.043)
        for index in [1_u32, 3, 0, 2]
        {
            let image = expect reader.read(index)
            let expected = index == 0 or index == 3 ? &first : &second
            Swag.require(Slice.equals(image.pixels.toSlice(), expected.pixels.toSlice()))
        }
    }
}

// Sixteen-bit animation preserves low sample bits in full and cropped frames.
#test
{
    for interlace in [false, true]
    {
        const Width = 35
        const Height = 12
        let path = pngAnimationPath()
        defer discard catch File.delete(path)

        var first = Image.create(Width, Height, .RGBA16)
        let samples = cast([*] u16, first.pixels.storage())
        for index in first.pixels.count / 2
        {
            samples[index] = cast(u16, ((index * 541 + 0xAA31) & 0xFFFF))
        }

        var second = first
        let changed = cast([*] u16, second.pixels.storage())
        changed[((Height - 1 - 4) * Width + 8) * 4 + 3] ^= 0x5001
        changed[((Height - 1 - 8) * Width + 20) * 4] ^= 0x00E3
        let third = first.convertedTo(.RGB16)

        var writer = expect Png.AnimationWriter.create(path, Width, Height, {
            loopCount: 7, pixelFormat: .RGBA16, png: {interlace: interlace}})
        var badDepth: Swag.Error
        discard catch writer.addFrame(Image.create(Width, Height, .RGBA8), 50) as badDepth
        Swag.require(badDepth.value() is UnsupportedFormatError)
        expect writer.addFrame(first, 17)
        expect writer.addFrame(second, 1001, 30000)
        expect writer.addFrame(third, 21)
        expect writer.end()

        let poster = expect Image.load(path)
        Swag.require(poster.pixelFormat == .RGBA16)
        Swag.require(Slice.equals(poster.pixels.toSlice(), first.pixels.toSlice()))

        var reader = expect ImageReader.load(path)
        Swag.require(reader.info.loopCount == 7 and reader.info.frames.count == 3)
        let area = reader.info.frames[1]
        Swag.require(area.pixelFormat == .RGBA16 and area.x == 8 and area.y == 4)
        Swag.require(area.width == 13 and area.height == 5)
        Swag.require(area.durationSeconds == 1001.0 / 30000.0)

        let pixels = expect reader.read(1)
        Swag.require(Slice.equals(pixels.pixels.toSlice(), second.pixels.toSlice()))
        let opaque = expect reader.read(2)
        let rgb = cast(const [*] u16, third.pixels.storage())
        let rgba = cast(const [*] u16, opaque.pixels.storage())
        for index in Width * Height
        {
            for channel in 3
            {
                Swag.require(rgb[index * 3 + channel] == rgba[index * 4 + channel])
            }

            Swag.require(rgba[index * 4 + 3] == 65535)
        }
        let replay = expect reader.read(0)
        Swag.require(Slice.equals(replay.pixels.toSlice(), first.pixels.toSlice()))
    }
}

// A rejected frame or empty finalization leaves the writer open for valid frames.
#test
{
    let path = pngAnimationPath()
    defer discard catch File.delete(path)
    var image = Image.create(7, 5, .RGBA8)
    image.fill(Color.fromArgb(93, 177, 53, 113))
    image.convertAlphaTo(.Premultiplied)
    let straight = image.convertedAlphaTo(.Straight)
    var writer = expect Png.AnimationWriter.create(path, image.width, image.height)

    var empty: Swag.Error
    discard catch writer.end() as empty
    Swag.require(empty.value() is InvalidFormatError)
    var delay: Swag.Error
    discard catch writer.addFrame(image, 10, 0) as delay
    Swag.require(delay.value() is BadParameterError)
    var geometry: Swag.Error
    discard catch writer.addFrame(Image.create(3, 5, .RGBA8), 25) as geometry
    Swag.require(geometry.value() is InvalidFormatError)
    var format: Swag.Error
    discard catch writer.addFrame(Image.create(7, 5, .Gray8), 35) as format
    Swag.require(format.value() is UnsupportedFormatError)

    expect writer.addFrame(image, 33)
    expect writer.end()

    var closed: Swag.Error
    discard catch writer.addFrame(image, 33) as closed
    Swag.require(closed.value() is BadParameterError)

    var reader = expect ImageReader.load(path)
    Swag.require(reader.info.frames.count == 1)
    Swag.require(reader.info.frames[0].durationSeconds == 0.033)
    let decoded = expect reader.read(0)
    Swag.require(Slice.equals(decoded.pixels.toSlice(), straight.pixels.toSlice()))
}
