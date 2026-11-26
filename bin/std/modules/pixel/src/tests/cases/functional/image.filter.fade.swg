#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        10_u8, 20_u8, 30_u8, 101_u8, 200_u8, 150_u8, 100_u8, 102_u8]

    var img = makeImage(2, 1, .RGBA8, pixels)
    img.fade(Color.fromArgb(255_u8, 110_u8, 210_u8, 10_u8), 0.25)
    assertImage(img, 2, 1, .RGBA8)

    assertPixel(img, 0, 0, Color.fromArgb(101_u8, 35_u8, 67_u8, 25_u8))
    assertPixel(img, 1, 0, Color.fromArgb(102_u8, 177_u8, 165_u8, 77_u8))
}
