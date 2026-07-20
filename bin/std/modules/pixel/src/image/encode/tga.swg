#global namespace Tga
using Core, Core.Errors

public struct Encoder {}

public impl IImageEncoder for Encoder
{
    mtd impl canEncode(fileName: #nonull string)->bool
    {
        return Path.getExtensionLowerCase(fileName) == ".tga"
    }

    mtd impl encode(result: #nonull *ConcatBuffer, image: Image, options: #null any) throw
    {
        if image.width <= 0 or image.height <= 0 or !image.pixels.buffer do
            throw InvalidFormatError{"invalid image"}
        if image.width > Swag.U16.Max do
            throw UnsupportedFormatError{"width is too big"}
        if image.height > Swag.U16.Max do
            throw UnsupportedFormatError{"height is too big"}

        var header: Header
        header.imageTypeCode  = cast(u8) TYPE_RGB
        header.width          = cast(u16) image.width
        header.height         = cast(u16) image.height
        header.bpp            = image.bpp
        header.descriptorByte = image.pf.hasAlpha() ? 8'u8 : 0'u8
        result.addStruct(header)

        var psrc = image.pixels.buffer
        switch image.pf
        {
        case BGR8, BGRA8:
            result.addBytes(image.pixels.toSlice())

        case RGB8:
            for image.width * image.height
            {
                result.addNative(psrc[2])
                result.addNative(psrc[1])
                result.addNative(psrc[0])
                psrc += 3
            }

        case RGBA8:
            for image.width * image.height
            {
                result.addNative(psrc[2])
                result.addNative(psrc[1])
                result.addNative(psrc[0])
                result.addNative(psrc[3])
                psrc += 4
            }
        }
    }
}
