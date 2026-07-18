#global #if #command == Swag.CompilerCommand.Test
#global #[Swag.ExplicitNullability]
using Swag, Core

#test
{
    const pixels = [
        1'u8, 2'u8, 3'u8, 4'u8,          5'u8, 6'u8, 7'u8, 8'u8,
        9'u8, 10'u8, 11'u8, 12'u8,       13'u8, 14'u8, 15'u8, 16'u8,
    ]

    var img = makeImage(2, 2, .RGBA8, pixels)
    let fillColor = Color.fromArgb(66'u8, 11'u8, 22'u8, 33'u8)
    img.fill(fillColor)
    assertImage(img, 2, 2, .RGBA8)

    assertPixel(img, 0, 1, fillColor)
    assertPixel(img, 1, 1, fillColor)
    assertPixel(img, 0, 0, fillColor)
    assertPixel(img, 1, 0, fillColor)
}
