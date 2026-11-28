#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const bgraPixels = [
        10_u8, 20_u8, 30_u8, 40_u8, 60_u8, 90_u8, 120_u8, 150_u8]

    var alphaImg = makeImage(2, 1, .BGRA8, bgraPixels)
    alphaImg.setAlpha(200)
    assertImage(alphaImg, 2, 1, .BGRA8)
    assertPixel(alphaImg, 0, 0, Color.fromArgb(200_u8, 30_u8, 20_u8, 10_u8))
    assertPixel(alphaImg, 1, 0, Color.fromArgb(200_u8, 120_u8, 90_u8, 60_u8))

    var meanImg = makeImage(2, 1, .BGRA8, bgraPixels)
    meanImg.setChannel(.RGBA, .MeanRGB)
    assertImage(meanImg, 2, 1, .BGRA8)
    assertPixel(meanImg, 0, 0, Color.fromArgb(20_u8, 20_u8, 20_u8, 20_u8))
    assertPixel(meanImg, 1, 0, Color.fromArgb(90_u8, 90_u8, 90_u8, 90_u8))

    const bgrPixels = [
        90_u8, 50_u8, 10_u8]

    var minImg = makeImage(1, 1, .BGR8, bgrPixels)
    minImg.setChannel(.Red, .MinRGB)
    assertImage(minImg, 1, 1, .BGR8)
    assertPixel(minImg, 0, 0, Color.fromArgb(255_u8, 10_u8, 50_u8, 90_u8))

    var guardedImg = makeImage(1, 1, .BGR8, bgrPixels)
    guardedImg.setChannel(.RGBA, .Alpha)
    assertImage(guardedImg, 1, 1, .BGR8)
    assertPixel(guardedImg, 0, 0, Color.fromArgb(255_u8, 10_u8, 50_u8, 90_u8))
}
