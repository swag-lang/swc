#global #if #command == Swag.CompilerCommand.Test
#global #[Swag.ExplicitNullability]
using Swag, Core

#test
{
    const pixels = [
        100'u8, 50'u8, 0'u8, 77'u8,      10'u8, 90'u8, 200'u8, 88'u8,
    ]

    var img = makeImage(2, 1, .RGBA8, pixels)
    img.grayScale()
    assertImage(img, 2, 1, .RGBA8)

    assertPixel(img, 0, 0, Color.fromArgb(77'u8, 56'u8, 56'u8, 56'u8))
    assertPixel(img, 1, 0, Color.fromArgb(88'u8, 81'u8, 81'u8, 81'u8))
}
