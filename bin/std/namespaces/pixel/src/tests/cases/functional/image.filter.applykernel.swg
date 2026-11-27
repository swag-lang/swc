#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    const pixels = [
        10_u8, 10_u8, 10_u8, 20_u8, 20_u8, 20_u8, 30_u8, 30_u8, 30_u8,
        40_u8, 40_u8, 40_u8, 50_u8, 50_u8, 50_u8, 60_u8, 60_u8, 60_u8,
        70_u8, 70_u8, 70_u8, 80_u8, 80_u8, 80_u8, 90_u8, 90_u8, 90_u8]

    let src = makeImage(3, 3, .RGB8, pixels)
    let out = src.withKernelApplied(.BoxBlur3x3)
    assertImage(out, 3, 3, .RGB8)

    assertPixel(out, 0, 2, Color.fromRgb(23_u8, 23_u8, 23_u8))
    assertPixel(out, 1, 1, Color.fromRgb(50_u8, 50_u8, 50_u8))
    assertPixel(out, 2, 0, Color.fromRgb(76_u8, 76_u8, 76_u8))
}

// Kernel weights start with the top row of the picture: a dark top over a bright bottom gives a
// positive horizontal gradient, on the 8-bit path and on the generic path alike.
#test
{
    // The buffer is bottom-up, so its first row is the bright bottom of the picture.
    var pixels: [36] u8
    for index in pixels.count
    {
        if index % 4 == 3
        {
            pixels[index] = 255
        }
        else if index < 12
        {
            pixels[index] = 200
        }
    }

    let src = makeImage(3, 3, .RGBA8, pixels)
    assertPixel(src.withKernelApplied(.HorizontalGradient), 1, 1, Color.fromArgb(255_u8, 255_u8, 255_u8, 255_u8))
    assertPixel(src.withKernelApplied(.SobelHorizontal3x3), 1, 1, Color.fromArgb(255_u8, 0_u8, 0_u8, 0_u8))

    let wide = src.convertedTo(.RGBA16)
    assertPixel(wide.withKernelApplied(.HorizontalGradient), 1, 1, Color.fromArgb(255_u8, 255_u8, 255_u8, 255_u8))
    assertPixel(wide.withKernelApplied(.SobelHorizontal3x3), 1, 1, Color.fromArgb(255_u8, 0_u8, 0_u8, 0_u8))
}

// Positive blur kernels filter visible colors without letting hidden RGB from transparent pixels
// tint opaque neighbors. The output alpha remains the value of each destination pixel.
#test
{
    const pixels = [
        0_u8, 255, 0, 0, 255, 0, 0, 255,
        255_u8, 0, 0, 255, 255, 0, 0, 255]
    let straight = makeImage(2, 2, .RGBA8, pixels)
    let filtered = straight.withKernelApplied(.BoxBlur3x3)

    // All visible source pixels are red; the transparent pixel's green byte must not bleed.
    assertPixel(filtered, 1, 1, Color.fromArgb(255_u8, 255_u8, 0_u8, 0_u8))
    for y in 2
    {
        for x in 2
        {
            Swag.require(filtered.pixelColor(x, y).a == straight.pixelColor(x, y).a)
        }
    }

    assertPixel(straight.withKernelApplied(.GaussianBlur3x3Strong), 1, 1, Color.fromArgb(255_u8, 255_u8, 0_u8, 0_u8))

    var inPlace = straight
    inPlace.applyKernel(.BoxBlur3x3)
    assertPixel(inPlace, 1, 1, Color.fromArgb(255_u8, 255_u8, 0_u8, 0_u8))

    let wide         = straight.convertedTo(.RGBAF32)
    let filteredWide = wide.withKernelApplied(.BoxBlur3x3)
    Swag.require(filteredWide.alphaMode == .Straight)
    assertPixel(filteredWide, 1, 1, Color.fromArgb(255_u8, 255_u8, 0_u8, 0_u8))

    let premultiplied         = straight.convertedAlphaTo(.Premultiplied)
    let filteredPremultiplied = premultiplied.withKernelApplied(.BoxBlur3x3)
    Swag.require(filteredPremultiplied.alphaMode == .Premultiplied)
    assertPixel(filteredPremultiplied, 1, 1, Color.fromArgb(255_u8, 255_u8, 0_u8, 0_u8))
}
