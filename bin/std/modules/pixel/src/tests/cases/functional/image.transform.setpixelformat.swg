#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func checkRgbToRgba(width: s32, sourceFormat, destinationFormat: PixelFormat)
{
    var source = Image.create(width, 1, sourceFormat)
    for x in width
    {
        let red   = cast(u8, (x * 13 + 11))
        let green = cast(u8, (x * 9 + 53))
        let blue  = cast(u8, (x * 7 + 97))
        let pixel = source.pixels.storage() + cast(u64, x) * 3
        if sourceFormat == .RGB8
        {
            pixel[0] = red
            pixel[1] = green
            pixel[2] = blue
        }
        else
        {
            pixel[0] = blue
            pixel[1] = green
            pixel[2] = red
        }
    }

    let converted = source.convertedTo(destinationFormat)
    for x in width
    {
        let red   = cast(u8, (x * 13 + 11))
        let green = cast(u8, (x * 9 + 53))
        let blue  = cast(u8, (x * 7 + 97))
        let pixel = converted.pixels.storage() + cast(u64, x) * 4
        if destinationFormat == .RGBA8
        {
            Swag.require(pixel[0] == red and pixel[1] == green and pixel[2] == blue)
        }
        else
        {
            Swag.require(pixel[0] == blue and pixel[1] == green and pixel[2] == red)
        }

        Swag.require(pixel[3] == 255)
    }

    let restored = converted.convertedTo(sourceFormat)
    Swag.require(Memory.compare(source.pixels.storage(), restored.pixels.storage(), source.byteCount) == 0)
}

#test
{
    const rgbaPixels = [
        10_u8, 20_u8, 30_u8, 40_u8, 50_u8, 60_u8, 70_u8, 80_u8]

    let rgba = makeImage(2, 1, .RGBA8, rgbaPixels)
    let bgr  = rgba.convertedTo(.BGR8)
    assertImage(bgr, 2, 1, .BGR8)
    assertPixel(bgr, 0, 0, Color.fromArgb(255_u8, 10_u8, 20_u8, 30_u8))
    assertPixel(bgr, 1, 0, Color.fromArgb(255_u8, 50_u8, 60_u8, 70_u8))

    const bgraPixels = [
        3_u8, 2_u8, 1_u8, 4_u8, 7_u8, 6_u8, 5_u8, 8_u8]

    let bgra = makeImage(2, 1, .BGRA8, bgraPixels)
    let rgb  = bgra.convertedTo(.RGB8)
    assertImage(rgb, 2, 1, .RGB8)
    assertPixel(rgb, 0, 0, Color.fromArgb(255_u8, 1_u8, 2_u8, 3_u8))
    assertPixel(rgb, 1, 0, Color.fromArgb(255_u8, 5_u8, 6_u8, 7_u8))

    const bgrPixels = [
        9_u8, 8_u8, 7_u8, 13_u8, 12_u8, 11_u8]

    var bgrSrc = makeImage(2, 1, .BGR8, bgrPixels)
    bgrSrc.convertTo(.RGBA8)
    assertImage(bgrSrc, 2, 1, .RGBA8)
    assertPixel(bgrSrc, 0, 0, Color.fromArgb(255_u8, 7_u8, 8_u8, 9_u8))
    assertPixel(bgrSrc, 1, 0, Color.fromArgb(255_u8, 11_u8, 12_u8, 13_u8))
}

#test
{
    for width in [5_s32, 6, 7, 10]
    {
        for sourceFormat in [PixelFormat.RGB8, PixelFormat.BGR8]
        {
            for destinationFormat in [PixelFormat.RGBA8, PixelFormat.BGRA8]
            {
                checkRgbToRgba(width, sourceFormat, destinationFormat)
            }
        }
    }
}

// Dropping alpha from a premultiplied byte image first restores its visible straight color.
#test
{
    const pixels = [255_u8, 0, 0, 128]
    let straight      = makeImage(1, 1, .RGBA8, pixels)
    let premultiplied = straight.convertedAlphaTo(.Premultiplied)

    let rgb = premultiplied.convertedTo(.RGB8)
    assertImage(rgb, 1, 1, .RGB8)
    Swag.require(rgb.alphaMode == .Straight)
    assertPixel(rgb, 0, 0, Color.fromRgb(255_u8, 0_u8, 0_u8))

    let gray = premultiplied.convertedTo(.Gray8)
    assertPixel(gray, 0, 0, Color.fromRgb(54_u8, 54_u8, 54_u8))

    var convertedInPlace = premultiplied
    convertedInPlace.convertTo(.RGB8)
    assertPixel(convertedInPlace, 0, 0, Color.fromRgb(255_u8, 0_u8, 0_u8))
    Swag.require(premultiplied.alphaMode == .Premultiplied)
    assertPixel(premultiplied, 0, 0, Color.fromArgb(128_u8, 255_u8, 0_u8, 0_u8))
}

// A value-returning pixel-format conversion preserves opaque format metadata.
#test
{
    var source = Image.create(1, 1, .RGB8)
    var record: ImageMetadata
    record.signature = 42
    record.tag       = "opaque"
    record.value.add(0xA5_u8)
    source.metadata.add(#move record)

    let converted = source.convertedTo(.RGBA8)
    Swag.require(converted.metadata.count == 1)
    Swag.require(converted.metadata[0].signature == 42 and converted.metadata[0].isTag("opaque"))
    Swag.require(converted.metadata[0].value.count == 1 and converted.metadata[0].value[0] == 0xA5)
}
