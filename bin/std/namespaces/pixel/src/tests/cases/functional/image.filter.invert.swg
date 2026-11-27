#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        0_u8, 64_u8, 255_u8, 101_u8, 25_u8, 100_u8, 225_u8, 102_u8]

    var img = makeImage(2, 1, .RGBA8, pixels)
    img.invert()
    assertImage(img, 2, 1, .RGBA8)
    assertPixel(img, 0, 0, Color.fromArgb(101_u8, 255_u8, 191_u8, 0_u8))
    assertPixel(img, 1, 0, Color.fromArgb(102_u8, 230_u8, 155_u8, 30_u8))
}
