#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// BMP and TGA only encode the four documented 8-bit RGB/BGR layouts.
#test
{
    let formats = [PixelFormat.Gray8, .GrayAlpha8, .Gray16, .GrayAlpha16, .GrayF16, .GrayAlphaF16, .GrayF32, .GrayAlphaF32, .RGB16, .RGBA16, .RGBF16, .RGBAF16, .RGBF32, .RGBAF32]
    for format in formats
    {
        var image = Image.create(3, 2, format)
        image.clear()
        discard catch image.encode("image.bmp") as bmpError
        Swag.assert(bmpError != null)
        discard catch image.encode("image.tga") as tgaError
        Swag.assert(tgaError != null)
        discard catch image.encode("image.tga", Tga.EncodeOptions{rle: true}) as rleError
        Swag.assert(rleError != null)
    }
}
