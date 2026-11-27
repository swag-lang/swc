#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        0_u8, 64_u8, 255_u8, 101_u8, 25_u8, 100_u8, 225_u8, 102_u8]

    var img = makeImage(2, 1, .RGBA8, pixels)
    img.gamma(2.0)
    assertImage(img, 2, 1, .RGBA8)
    assertPixel(img, 0, 0, Color.fromArgb(101_u8, 0_u8, 127_u8, 255_u8))
    assertPixel(img, 1, 0, Color.fromArgb(102_u8, 79_u8, 159_u8, 239_u8))

    var identity = makeImage(2, 1, .RGBA8, pixels)
    identity.gamma(1.0)
    assertImage(identity, 2, 1, .RGBA8)
    assertPixel(identity, 0, 0, Color.fromArgb(101_u8, 0_u8, 64_u8, 255_u8))
    assertPixel(identity, 1, 0, Color.fromArgb(102_u8, 25_u8, 100_u8, 225_u8))
}
