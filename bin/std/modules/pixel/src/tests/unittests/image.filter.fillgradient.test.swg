#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var grad2 = Image.create(4, 2, .RGBA8)
    grad2.fillGradient(Color.fromArgb(40'u8, 0'u8, 20'u8, 40'u8), Color.fromArgb(200'u8, 80'u8, 100'u8, 120'u8))
    assertImage(grad2, 4, 2, .RGBA8)

    assertPixel(grad2, 0, 1, Color.fromArgb(40'u8, 0'u8, 20'u8, 40'u8))
    assertPixel(grad2, 1, 1, Color.fromArgb(93'u8, 26'u8, 46'u8, 66'u8))
    assertPixel(grad2, 2, 0, Color.fromArgb(146'u8, 53'u8, 73'u8, 93'u8))
    assertPixel(grad2, 3, 0, Color.fromArgb(200'u8, 80'u8, 100'u8, 120'u8))

    var grad4 = Image.create(2, 2, .RGBA8)
    grad4.fillGradient(
        Color.fromArgb(255'u8, 10'u8, 20'u8, 30'u8),
        Color.fromArgb(255'u8, 110'u8, 120'u8, 130'u8),
        Color.fromArgb(255'u8, 210'u8, 220'u8, 230'u8),
        Color.fromArgb(255'u8, 250'u8, 240'u8, 230'u8))
    assertImage(grad4, 2, 2, .RGBA8)

    assertPixel(grad4, 0, 1, Color.fromArgb(255'u8, 210'u8, 220'u8, 230'u8))
    assertPixel(grad4, 1, 1, Color.fromArgb(255'u8, 250'u8, 240'u8, 230'u8))
    assertPixel(grad4, 0, 0, Color.fromArgb(255'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(grad4, 1, 0, Color.fromArgb(255'u8, 110'u8, 120'u8, 130'u8))
}

// A horizontal gradient on an RGBA8 image must vary across X (a flat/gray fill
// would leave every column equal). This is the form the channel bars rely on.
#test
{
    var grad = Image.create(4, 1, .RGBA8)
    grad.fillGradient(Color.fromArgb(255'u8, 0'u8, 0'u8, 0'u8), Color.fromArgb(255'u8, 200'u8, 120'u8, 40'u8))
    assertPixel(grad, 0, 0, Color.fromArgb(255'u8, 0'u8, 0'u8, 0'u8))
    assertPixel(grad, 1, 0, Color.fromArgb(255'u8, 66'u8, 40'u8, 13'u8))
    assertPixel(grad, 2, 0, Color.fromArgb(255'u8, 133'u8, 80'u8, 26'u8))
    assertPixel(grad, 3, 0, Color.fromArgb(255'u8, 200'u8, 120'u8, 40'u8))
}
