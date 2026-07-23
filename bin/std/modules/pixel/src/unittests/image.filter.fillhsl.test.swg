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

// RGB plane modes as the ColorPicker actually uses them: RGBA8 format with a
// non-zero fixed third channel. These must produce a real gradient (not a flat
// gray fill), so assert the colored corners for every RGB plane.
#test
{
    // RedGreen keeps blue fixed (here full blue).
    var redGreen = Image.create(2, 2, .RGBA8)
    redGreen.fillHsl(.RedGreen, Color.fromArgb(255'u8, 0'u8, 0'u8, 255'u8))
    assertPixel(redGreen, 0, 1, Color.fromRgbf(0.0, 1.0, 1.0).withAlpha(255))
    assertPixel(redGreen, 1, 1, Color.fromRgbf(0.5, 1.0, 1.0).withAlpha(255))
    assertPixel(redGreen, 0, 0, Color.fromRgbf(0.0, 0.5, 1.0).withAlpha(255))
    assertPixel(redGreen, 1, 0, Color.fromRgbf(0.5, 0.5, 1.0).withAlpha(255))

    // RedBlue keeps green fixed.
    var redBlue = Image.create(2, 2, .RGBA8)
    redBlue.fillHsl(.RedBlue, Color.fromArgb(255'u8, 0'u8, 255'u8, 0'u8))
    assertPixel(redBlue, 0, 1, Color.fromRgbf(0.0, 1.0, 1.0).withAlpha(255))
    assertPixel(redBlue, 1, 1, Color.fromRgbf(0.5, 1.0, 1.0).withAlpha(255))
    assertPixel(redBlue, 0, 0, Color.fromRgbf(0.0, 1.0, 0.5).withAlpha(255))
    assertPixel(redBlue, 1, 0, Color.fromRgbf(0.5, 1.0, 0.5).withAlpha(255))

    // GreenBlue keeps red fixed.
    var greenBlue = Image.create(2, 2, .RGBA8)
    greenBlue.fillHsl(.GreenBlue, Color.fromArgb(255'u8, 255'u8, 0'u8, 0'u8))
    assertPixel(greenBlue, 0, 1, Color.fromRgbf(1.0, 0.0, 1.0).withAlpha(255))
    assertPixel(greenBlue, 1, 1, Color.fromRgbf(1.0, 0.5, 1.0).withAlpha(255))
    assertPixel(greenBlue, 0, 0, Color.fromRgbf(1.0, 0.0, 0.5).withAlpha(255))
    assertPixel(greenBlue, 1, 0, Color.fromRgbf(1.0, 0.5, 0.5).withAlpha(255))
}

// A larger image exercises the fill path the real ColorPicker widget uses (this is
// the "RGB modes" page that used to render blank/gray). fillHsl must fully fill it:
// opaque, colorful and a true 2D gradient.
//
// This is a regression guard for a compiler codegen bug: `parallelVisit` does
// `if !@countof(range) do return`, and `!@countof(slice)` was compiled as an 8-bit
// compare, so #null any byte count that is a multiple of 256 (e.g. 128*96*4 = 49152) was
// wrongly seen as zero and the visit returned without writing anything.
#test
{
    var big = Image.create(128, 96, .RGBA8)
    big.fillHsl(.RedGreen, Color.fromArgb(255'u8, 0'u8, 0'u8, 200'u8))
    assertImage(big, 128, 96, .RGBA8)

    let topLeft     = big.getPixelColor(1, 1)
    let bottomRight = big.getPixelColor(126, 94)
    let bottomLeft  = big.getPixelColor(1, 94)

    @assert(topLeft.a == 255)     // fill must write opaque alpha everywhere
    @assert(bottomRight.a == 255)
    @assert(topLeft.argb != bottomRight.argb)     // a real 2D gradient, not a flat fill
    @assert(topLeft.r != topLeft.g or bottomRight.r != bottomRight.g or bottomLeft.r != bottomLeft.g)
}

// Same large-image coverage for an HSL plane mode, to compare with the RGB modes.
#test
{
    var big = Image.create(128, 96, .RGBA8)
    big.fillHsl(.HueSaturation, Color.fromHsl(0.0, 1.0, 0.5))
    assertImage(big, 128, 96, .RGBA8)
    @assert(big.getPixelColor(1, 1).a == 255)
    @assert(big.getPixelColor(126, 94).a == 255)
    @assert(big.getPixelColor(1, 1).argb != big.getPixelColor(126, 94).argb)
}
