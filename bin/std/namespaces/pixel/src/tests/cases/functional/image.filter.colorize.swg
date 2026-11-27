#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        240_u8, 200_u8, 200_u8, 77_u8, 10_u8, 30_u8, 50_u8, 88_u8]

    var img = makeImage(2, 1, .RGBA8, pixels)
    img.colorize(0.3, 0.0, 1.0)
    assertImage(img, 2, 1, .RGBA8)

    let brightPixel = img.pixelColor(0, 0)
    Swag.require(brightPixel.a == 77)
    Swag.require(brightPixel.r > 200)
    Swag.require(brightPixel.r == brightPixel.g)
    Swag.require(brightPixel.g == brightPixel.b)

    let darkExpected = Color.fromHsl(0.3, 0.0, 30 / 255.0).withAlpha(88)
    assertPixel(img, 1, 0, darkExpected)
}
