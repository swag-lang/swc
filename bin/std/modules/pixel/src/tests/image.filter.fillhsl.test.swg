#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    var hue = Image.create(2, 2, .RGBA8)
    hue.fillHsl(.HueHorz)
    assertImage(hue, 2, 2, .RGBA8)

    let red  = Color.fromHsl(0.0, 1.0, 0.5).withAlpha(255)
    let cyan = Color.fromHsl(0.5, 1.0, 0.5).withAlpha(255)
    assertPixel(hue, 0, 1, red)
    assertPixel(hue, 1, 1, cyan)
    assertPixel(hue, 0, 0, red)
    assertPixel(hue, 1, 0, cyan)

    var redGreen = Image.create(2, 2, .BGRA8)
    redGreen.fillHsl(.RedGreen, Color.fromArgb(255'u8, 0'u8, 0'u8, 0'u8))
    assertImage(redGreen, 2, 2, .BGRA8)

    assertPixel(redGreen, 0, 1, Color.fromRgbf(0.0, 1.0, 0.0).withAlpha(255))
    assertPixel(redGreen, 1, 1, Color.fromRgbf(0.5, 1.0, 0.0).withAlpha(255))
    assertPixel(redGreen, 0, 0, Color.fromRgbf(0.0, 0.5, 0.0).withAlpha(255))
    assertPixel(redGreen, 1, 0, Color.fromRgbf(0.5, 0.5, 0.0).withAlpha(255))
}
