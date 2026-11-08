#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A screen-like frame: opaque colours stored with a zero alpha channel, as a desktop grab gives
// them, and a square of another colour at `squareX`.
func animationFrame(squareX: s32, square: Color)->Image
{
    var result = Image.create(40, 30, .BGRA8)
    for y in 30
    {
        for x in 40
        {
            let inside = x >= squareX and x < squareX + 8 and y >= 10 and y < 18
            let color  = inside ? square : Color.fromArgb(255, 20, 90, 160)
            let at     = cast(u64, (29 - y) * result.rowStride + x * 4)
            let pixels = result.pixels.storage()
            pixels[at]     = color.b
            pixels[at + 1] = color.g
            pixels[at + 2] = color.r
            pixels[at + 3] = 0
        }
    }

    return result
}

func sameColors(decoded: Image, source: Image)->bool
{
    for y in source.height
    {
        for x in source.width
        {
            let a = decoded.pixelColor(x, y)
            let b = source.pixelColor(x, y)
            if a.r != b.r or a.g != b.g or a.b != b.b do
                return false
        }
    }

    return true
}

// An animation written frame by frame decodes back with its frames, its timing and its looping;
// an unchanged frame lengthens the one before it.
#test
{
    let folder = Path.combine(Env.getSpecialDirectory(.Temp).toString(), "swag-tests")
    if not Directory.exists(folder) do
        expect Directory.create(folder)
    var name = String.from("animation-")
    name += Guid64.random().toString()
    name += ".gif"
    let path = Path.combine(folder, name)
    defer catch File.delete(path)

    let red    = Color.fromArgb(255, 220, 40, 40)
    let yellow = Color.fromArgb(255, 240, 220, 0)
    var frames: [4] Image
    frames[0] = animationFrame(2, red)
    frames[1] = animationFrame(12, red)
    frames[2] = animationFrame(12, red)
    frames[3] = animationFrame(20, yellow)

    var writer = expect Gif.AnimationWriter.create(path, 40, 30)
    for frame in frames do
        expect writer.addFrame(frame, 100_000)
    expect writer.end()

    let bytes  = expect File.readAllBytes(path)
    var reader = expect ImageReader.decode("animation.gif", bytes.toSlice())
    Swag.require(reader.info.frames.count == 3)
    Swag.require(reader.info.loopCount == 0)
    Swag.require(reader.info.canvasWidth == 40 and reader.info.canvasHeight == 30)
    Swag.require(Math.abs(reader.info.frames[0].durationSeconds - 0.1) < 0.001)
    Swag.require(Math.abs(reader.info.frames[1].durationSeconds - 0.2) < 0.001)
    Swag.require(Math.abs(reader.info.frames[2].durationSeconds - 0.1) < 0.001)

    Swag.require(sameColors(expect reader.read(0), frames[0]))
    Swag.require(sameColors(expect reader.read(1), frames[1]))
    Swag.require(sameColors(expect reader.read(2), frames[3]))
}

// A still GIF compresses repeated colours instead of storing one code per pixel.
#test
{
    var image = Image.create(256, 256, .RGB8)
    image.fill(Color.fromArgb(255, 30, 60, 90))
    let bytes = expect image.encodeToBytes("flat.gif")
    Swag.require(bytes.count < 4096)

    let decoded = expect Image.decode("flat.gif", bytes.toSlice())
    Swag.require(sameColors(decoded, image))
}

// Ordered dithering is an explicit animation choice for frames with more than 256 colours.
#test
{
    var frame  = Image.create(32, 16, .RGB8)
    let pixels = frame.pixels.storage()
    for y in frame.height
    {
        for x in frame.width
        {
            let at = cast(u64, (frame.height - 1 - y) * frame.rowStride + x * 3)
            pixels[at]     = cast(u8, x * 8)
            pixels[at + 1] = cast(u8, y * 15)
            pixels[at + 2] = cast(u8, (x * 7 + y * 11) & 255)
        }
    }

    var plainName = String.from("gif-plain-")
    plainName += Guid64.random().toString()
    plainName += ".gif"
    var ditherName = String.from("gif-dither-")
    ditherName += Guid64.random().toString()
    ditherName += ".gif"
    let plainPath  = Path.combine(Env.getSpecialDirectory(.Temp).toString(), plainName)
    let ditherPath = Path.combine(Env.getSpecialDirectory(.Temp).toString(), ditherName)
    defer catch File.delete(plainPath)
    defer catch File.delete(ditherPath)

    var plain = expect Gif.AnimationWriter.create(plainPath, 32, 16)
    expect plain.addFrame(frame, 100_000)
    expect plain.end()

    var options: Gif.AnimationOptions
    options.dither = true
    var dithered = expect Gif.AnimationWriter.create(ditherPath, 32, 16, options)
    expect dithered.addFrame(frame, 100_000)
    expect dithered.end()

    let plainBytes  = expect File.readAllBytes(plainPath)
    let ditherBytes = expect File.readAllBytes(ditherPath)
    Swag.require(plainBytes.count != ditherBytes.count or
                 Memory.compare(plainBytes.storage(), ditherBytes.storage(), plainBytes.count) != 0)
}
