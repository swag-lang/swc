#global #if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const rgbaPixels = [
        10'u8, 20'u8, 30'u8, 40'u8,      50'u8, 60'u8, 70'u8, 80'u8,
        ]

    let rgba = makeImage(2, 1, .RGBA8, rgbaPixels)
    let bgr  = rgba.toSetPixelFormat(.BGR8)
    assertImage(bgr, 2, 1, .BGR8)
    assertPixel(bgr, 0, 0, Color.fromArgb(255'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(bgr, 1, 0, Color.fromArgb(255'u8, 50'u8, 60'u8, 70'u8))

    const bgraPixels = [
        3'u8, 2'u8, 1'u8, 4'u8,          7'u8, 6'u8, 5'u8, 8'u8,
        ]

    let bgra = makeImage(2, 1, .BGRA8, bgraPixels)
    let rgb  = bgra.toSetPixelFormat(.RGB8)
    assertImage(rgb, 2, 1, .RGB8)
    assertPixel(rgb, 0, 0, Color.fromArgb(255'u8, 1'u8, 2'u8, 3'u8))
    assertPixel(rgb, 1, 0, Color.fromArgb(255'u8, 5'u8, 6'u8, 7'u8))

    const bgrPixels = [
        9'u8, 8'u8, 7'u8,                13'u8, 12'u8, 11'u8,
        ]

    var bgrSrc = makeImage(2, 1, .BGR8, bgrPixels)
    bgrSrc.setPixelFormat(.RGBA8)
    assertImage(bgrSrc, 2, 1, .RGBA8)
    assertPixel(bgrSrc, 0, 0, Color.fromArgb(255'u8, 7'u8, 8'u8, 9'u8))
    assertPixel(bgrSrc, 1, 0, Color.fromArgb(255'u8, 11'u8, 12'u8, 13'u8))
}
