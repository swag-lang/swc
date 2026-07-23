#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    const rawPixels = [
        10'u8, 20'u8, 30'u8, 40'u8,      50'u8, 60'u8, 70'u8, 80'u8,
        90'u8, 100'u8, 110'u8, 120'u8,   130'u8, 140'u8, 150'u8, 160'u8,
        ]

    let rawSrc = makeImage(2, 2, .RGBA8, rawPixels)
    let rawOut = rawSrc.toResize(4, 0, .Raw)
    assertImage(rawOut, 4, 4, .RGBA8)

    assertPixel(rawOut, 0, 3, Color.fromArgb(40'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(rawOut, 1, 3, Color.fromArgb(40'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(rawOut, 2, 3, Color.fromArgb(80'u8, 50'u8, 60'u8, 70'u8))
    assertPixel(rawOut, 3, 3, Color.fromArgb(80'u8, 50'u8, 60'u8, 70'u8))
    assertPixel(rawOut, 0, 0, Color.fromArgb(120'u8, 90'u8, 100'u8, 110'u8))
    assertPixel(rawOut, 1, 0, Color.fromArgb(120'u8, 90'u8, 100'u8, 110'u8))
    assertPixel(rawOut, 2, 0, Color.fromArgb(160'u8, 130'u8, 140'u8, 150'u8))
    assertPixel(rawOut, 3, 0, Color.fromArgb(160'u8, 130'u8, 140'u8, 150'u8))

    const filteredPixels = [
        7'u8, 17'u8, 27'u8, 37'u8,
        ]

    let filteredSrc = makeImage(1, 1, .RGBA8, filteredPixels)
    let filteredOut = filteredSrc.toResize(3, 2, .Bicubic)
    assertImage(filteredOut, 3, 2, .RGBA8)
    assertPixel(filteredOut, 0, 1, Color.fromArgb(37'u8, 7'u8, 17'u8, 27'u8))
    assertPixel(filteredOut, 2, 1, Color.fromArgb(37'u8, 7'u8, 17'u8, 27'u8))
    assertPixel(filteredOut, 0, 0, Color.fromArgb(37'u8, 7'u8, 17'u8, 27'u8))
    assertPixel(filteredOut, 2, 0, Color.fromArgb(37'u8, 7'u8, 17'u8, 27'u8))
}
