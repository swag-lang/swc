#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Only fully transparent pixels take the new color, and none of them changes alpha.
#test
{
    const pixels = [
        0'u8, 0'u8, 0'u8, 0'u8, 10'u8, 20'u8, 30'u8, 1'u8, 40'u8, 50'u8, 60'u8, 255'u8]

    var img = makeImage(3, 1, .RGBA8, pixels)
    img.setTransparentColor(Color.fromArgb(Argb.White))
    assertImage(img, 3, 1, .RGBA8)
    assertPixel(img, 0, 0, Color.fromArgb(0'u8, 255'u8, 255'u8, 255'u8))
    assertPixel(img, 1, 0, Color.fromArgb(1'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(img, 2, 0, Color.fromArgb(255'u8, 40'u8, 50'u8, 60'u8))
}

// The channel order of the destination format is honored, not the memory order of the color.
#test
{
    const pixels = [
        0'u8, 0'u8, 0'u8, 0'u8]

    var img = makeImage(1, 1, .BGRA8, pixels)
    img.setTransparentColor(Color.fromArgb(255'u8, 10'u8, 20'u8, 30'u8))
    assertPixel(img, 0, 0, Color.fromArgb(0'u8, 10'u8, 20'u8, 30'u8))
}

// A format without alpha has no fully transparent pixel, so it is left untouched.
#test
{
    const pixels = [
        1'u8, 2'u8, 3'u8]

    var img = makeImage(1, 1, .BGR8, pixels)
    img.setTransparentColor(Color.fromArgb(Argb.White))
    assertPixel(img, 0, 0, Color.fromArgb(255'u8, 3'u8, 2'u8, 1'u8))
}

// Premultiplied input preserves visible logical colors and becomes straight alpha.
#test
{
    var img = Image.create(2, 1, .RGBA8, [200'u8, 100, 50, 128, 0, 0, 0, 0])
    img.convertAlphaTo(.Premultiplied)
    let visible = img.pixelColor(0, 0)

    img.setTransparentColor(Color.fromArgb(255'u8, 10, 20, 30))

    Swag.require(img.alphaMode == .Straight)
    assertPixel(img, 0, 0, visible)
    assertPixel(img, 1, 0, Color.fromArgb(0'u8, 10, 20, 30))
    Swag.require(img.pixels.storage()[7] == 0)
}
