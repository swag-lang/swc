#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var grad2 = Image.create(4, 2, .RGBA8)
    grad2.fillGradient(Color.fromArgb(40_u8, 0_u8, 20_u8, 40_u8), Color.fromArgb(200_u8, 80_u8, 100_u8, 120_u8))
    assertImage(grad2, 4, 2, .RGBA8)

    assertPixel(grad2, 0, 1, Color.fromArgb(40_u8, 0_u8, 20_u8, 40_u8))
    assertPixel(grad2, 1, 1, Color.fromArgb(93_u8, 26_u8, 46_u8, 66_u8))
    assertPixel(grad2, 2, 0, Color.fromArgb(146_u8, 53_u8, 73_u8, 93_u8))
    assertPixel(grad2, 3, 0, Color.fromArgb(200_u8, 80_u8, 100_u8, 120_u8))

    var grad4 = Image.create(2, 2, .RGBA8)
    grad4.fillGradient(Color.fromArgb(255_u8, 10_u8, 20_u8, 30_u8),
                       Color.fromArgb(255_u8, 110_u8, 120_u8, 130_u8),
                       Color.fromArgb(255_u8, 210_u8, 220_u8, 230_u8),
                       Color.fromArgb(255_u8, 250_u8, 240_u8, 230_u8))
    assertImage(grad4, 2, 2, .RGBA8)

    assertPixel(grad4, 0, 1, Color.fromArgb(255_u8, 210_u8, 220_u8, 230_u8))
    assertPixel(grad4, 1, 1, Color.fromArgb(255_u8, 250_u8, 240_u8, 230_u8))
    assertPixel(grad4, 0, 0, Color.fromArgb(255_u8, 10_u8, 20_u8, 30_u8))
    assertPixel(grad4, 1, 0, Color.fromArgb(255_u8, 110_u8, 120_u8, 130_u8))
}

// A horizontal gradient on an RGBA8 image must vary across X (a flat/gray fill
// would leave every column equal). This is the form the channel bars rely on.
#test
{
    var grad = Image.create(4, 1, .RGBA8)
    grad.fillGradient(Color.fromArgb(255_u8, 0_u8, 0_u8, 0_u8), Color.fromArgb(255_u8, 200_u8, 120_u8, 40_u8))
    assertPixel(grad, 0, 0, Color.fromArgb(255_u8, 0_u8, 0_u8, 0_u8))
    assertPixel(grad, 1, 0, Color.fromArgb(255_u8, 66_u8, 40_u8, 13_u8))
    assertPixel(grad, 2, 0, Color.fromArgb(255_u8, 133_u8, 80_u8, 26_u8))
    assertPixel(grad, 3, 0, Color.fromArgb(255_u8, 200_u8, 120_u8, 40_u8))
}

#test
{
    var grad = Image.create(2, 1, .RGBAF32)
    grad.fillGradient(Color.fromArgb(255_u8, 0_u8, 0_u8, 0_u8), Color.fromArgb(255_u8, 255_u8, 0_u8, 0_u8))
    assertPixel(grad, 0, 0, Color.fromArgb(255_u8, 0_u8, 0_u8, 0_u8))
    assertPixel(grad, 1, 0, Color.fromArgb(255_u8, 255_u8, 0_u8, 0_u8))
}
