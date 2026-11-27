#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Only fully transparent pixels take the new color, and none of them changes alpha.
#test
{
    const pixels = [
        0_u8, 0_u8, 0_u8, 0_u8, 10_u8, 20_u8, 30_u8, 1_u8, 40_u8, 50_u8, 60_u8, 255_u8]

    var img = makeImage(3, 1, .RGBA8, pixels)
    img.setTransparentColor(Color.fromArgb(Argb.White))
    assertImage(img, 3, 1, .RGBA8)
    assertPixel(img, 0, 0, Color.fromArgb(0_u8, 255_u8, 255_u8, 255_u8))
    assertPixel(img, 1, 0, Color.fromArgb(1_u8, 10_u8, 20_u8, 30_u8))
    assertPixel(img, 2, 0, Color.fromArgb(255_u8, 40_u8, 50_u8, 60_u8))
}

// The channel order of the destination format is honored, not the memory order of the color.
#test
{
    const pixels = [
        0_u8, 0_u8, 0_u8, 0_u8]

    var img = makeImage(1, 1, .BGRA8, pixels)
    img.setTransparentColor(Color.fromArgb(255_u8, 10_u8, 20_u8, 30_u8))
    assertPixel(img, 0, 0, Color.fromArgb(0_u8, 10_u8, 20_u8, 30_u8))
}

// A format without alpha has no fully transparent pixel, so it is left untouched.
#test
{
    const pixels = [
        1_u8, 2_u8, 3_u8]

    var img = makeImage(1, 1, .BGR8, pixels)
    img.setTransparentColor(Color.fromArgb(Argb.White))
    assertPixel(img, 0, 0, Color.fromArgb(255_u8, 3_u8, 2_u8, 1_u8))
}

// Premultiplied input preserves visible logical colors and becomes straight alpha.
#test
{
    var img = Image.create(2, 1, .RGBA8, [200_u8, 100, 50, 128, 0, 0, 0, 0])
    img.convertAlphaTo(.Premultiplied)
    let visible = img.pixelColor(0, 0)

    img.setTransparentColor(Color.fromArgb(255_u8, 10, 20, 30))

    Swag.require(img.alphaMode == .Straight)
    assertPixel(img, 0, 0, visible)
    assertPixel(img, 1, 0, Color.fromArgb(0_u8, 10, 20, 30))
    Swag.require(img.pixels.storage()[7] == 0)
}
