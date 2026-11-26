#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        1_u8, 2_u8, 3_u8, 4_u8, 5_u8, 6_u8, 7_u8, 8_u8,
        9_u8, 10_u8, 11_u8, 12_u8, 13_u8, 14_u8, 15_u8, 16_u8]

    var img       = makeImage(2, 2, .RGBA8, pixels)
    let fillColor = Color.fromArgb(66_u8, 11_u8, 22_u8, 33_u8)
    img.fill(fillColor)
    assertImage(img, 2, 2, .RGBA8)

    assertPixel(img, 0, 1, fillColor)
    assertPixel(img, 1, 1, fillColor)
    assertPixel(img, 0, 0, fillColor)
    assertPixel(img, 1, 0, fillColor)
}

#test
{
    const pixels = [255_u8, 64, 32, 128]
    let source    = makeImage(1, 1, .RGBA8, pixels)
    let converted = source.convertedTo(.RGBAF32)
    assertPixel(converted, 0, 0, Color.fromArgb(128_u8, 255_u8, 64_u8, 32_u8))
}

#test
{
    const pixels = [255_u8, 64, 32, 128]
    let source      = makeImage(1, 1, .RGBA8, pixels)
    var transformed = source.convertedTo(.RGBAF32)
    transformed.invert()
    assertPixel(transformed, 0, 0, Color.fromArgb(128_u8, 0_u8, 191_u8, 223_u8))
}

#test
{
    var image = Image.create(1, 1, .RGBAF32)
    let color = Color.fromArgb(128_u8, 255_u8, 64_u8, 32_u8)
    image.fill(color)

    assertImage(image, 1, 1, .RGBAF32)
    assertPixel(image, 0, 0, color)
}
