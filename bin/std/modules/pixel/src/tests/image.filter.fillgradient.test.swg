#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    var grad2 = Image.create(4, 2, .RGBA8)
    grad2.fillGradient2(Color.fromArgb(40'u8, 0'u8, 20'u8, 40'u8), Color.fromArgb(200'u8, 80'u8, 100'u8, 120'u8))
    assertImage(grad2, 4, 2, .RGBA8)

    assertPixel(grad2, 0, 1, Color.fromArgb(40'u8, 0'u8, 20'u8, 40'u8))
    assertPixel(grad2, 1, 1, Color.fromArgb(80'u8, 20'u8, 40'u8, 60'u8))
    assertPixel(grad2, 2, 0, Color.fromArgb(120'u8, 40'u8, 60'u8, 80'u8))
    assertPixel(grad2, 3, 0, Color.fromArgb(160'u8, 60'u8, 80'u8, 100'u8))

    var grad4 = Image.create(2, 2, .RGBA8)
    grad4.fillGradient4(
        Color.fromArgb(255'u8, 10'u8, 20'u8, 30'u8),
        Color.fromArgb(255'u8, 110'u8, 120'u8, 130'u8),
        Color.fromArgb(255'u8, 210'u8, 220'u8, 230'u8),
        Color.fromArgb(255'u8, 250'u8, 240'u8, 230'u8))
    assertImage(grad4, 2, 2, .RGBA8)

    assertPixel(grad4, 0, 1, Color.fromArgb(255'u8, 210'u8, 220'u8, 230'u8))
    assertPixel(grad4, 1, 1, Color.fromArgb(255'u8, 230'u8, 230'u8, 230'u8))
    assertPixel(grad4, 0, 0, Color.fromArgb(255'u8, 110'u8, 120'u8, 130'u8))
    assertPixel(grad4, 1, 0, Color.fromArgb(255'u8, 145'u8, 150'u8, 155'u8))
}
