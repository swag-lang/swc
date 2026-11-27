#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    let ground     = Color.fromRgb(17, 83, 149)
    let foreground = Color.fromRgb(210, 160, 35)

    for format in [PixelFormat.RGBA8, .BGRA8, .RGBA16, .RGBAF32]
    {
        var keyed = Image.create(1, 1, format)
        keyed.fill(ground)
        keyed.keyOutGround(ground, foreground)
        assertPixel(keyed, 0, 0, foreground.withAlpha(0))

        var glyph = Image.create(1, 1, format)
        glyph.fill(foreground)
        glyph.keyOutGround(ground, foreground)
        assertPixel(glyph, 0, 0, foreground)
    }
}
