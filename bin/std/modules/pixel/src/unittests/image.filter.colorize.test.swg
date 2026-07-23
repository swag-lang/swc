#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    const pixels = [
        240'u8, 200'u8, 200'u8, 77'u8,   10'u8, 30'u8, 50'u8, 88'u8,
        ]

    var img = makeImage(2, 1, .RGBA8, pixels)
    img.colorize(0.3, 0.0, 1.0)
    assertImage(img, 2, 1, .RGBA8)

    let brightPixel = img.getPixelColor(0, 0)
    @assert(brightPixel.a == 77)
    @assert(brightPixel.r > 200)
    @assert(brightPixel.r == brightPixel.g)
    @assert(brightPixel.g == brightPixel.b)

    let darkExpected = Color.fromHsl(0.3, 0.0, 30 / 255.0).withAlpha(88)
    assertPixel(img, 1, 0, darkExpected)
}
