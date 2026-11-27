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
