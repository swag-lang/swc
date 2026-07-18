#global #if #command == Swag.CompilerCommand.Test
#global #[Swag.ExplicitNullability]
using Swag, Core

#test
{
    const bgraPixels = [
        10'u8, 20'u8, 30'u8, 40'u8,      60'u8, 90'u8, 120'u8, 150'u8,
    ]

    var alphaImg = makeImage(2, 1, .BGRA8, bgraPixels)
    alphaImg.setAlpha(200)
    assertImage(alphaImg, 2, 1, .BGRA8)
    assertPixel(alphaImg, 0, 0, Color.fromArgb(200'u8, 30'u8, 20'u8, 10'u8))
    assertPixel(alphaImg, 1, 0, Color.fromArgb(200'u8, 120'u8, 90'u8, 60'u8))

    var meanImg = makeImage(2, 1, .BGRA8, bgraPixels)
    meanImg.setChannel(.RGBA, .MeanRGB)
    assertImage(meanImg, 2, 1, .BGRA8)
    assertPixel(meanImg, 0, 0, Color.fromArgb(20'u8, 20'u8, 20'u8, 20'u8))
    assertPixel(meanImg, 1, 0, Color.fromArgb(90'u8, 90'u8, 90'u8, 90'u8))

    const bgrPixels = [
        90'u8, 50'u8, 10'u8,
    ]

    var minImg = makeImage(1, 1, .BGR8, bgrPixels)
    minImg.setChannel(.Red, .MinRGB)
    assertImage(minImg, 1, 1, .BGR8)
    assertPixel(minImg, 0, 0, Color.fromArgb(255'u8, 10'u8, 50'u8, 90'u8))

    var guardedImg = makeImage(1, 1, .BGR8, bgrPixels)
    guardedImg.setChannel(.RGBA, .Alpha)
    assertImage(guardedImg, 1, 1, .BGR8)
    assertPixel(guardedImg, 0, 0, Color.fromArgb(255'u8, 10'u8, 50'u8, 90'u8))
}
