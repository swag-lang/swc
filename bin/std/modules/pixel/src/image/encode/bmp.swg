#global namespace Bmp
using Core, Core.Errors

public struct Encoder {}

public impl IImageEncoder for Encoder
{
    mtd impl canEncode(fileName: #nonull string)->bool
    {
        return Path.getExtensionLowerCase(fileName) == ".bmp"
    }

    mtd impl encode(result: #nonull *ConcatBuffer, image: Image, options: #null any) throw
    {
        if image.width <= 0 or image.height <= 0 or !image.pixels.buffer do
            throw InvalidFormatError{"invalid image"}
        if image.width > Swag.S32.Max / image.bpp8 or image.height > Swag.S32.Max / image.width do
            throw UnsupportedFormatError{"image is too big"}

        let rowBytes  = cast(u64) image.width * image.bpp8
        let stride    = rowStride(image.width, image.bpp)
        let imageSize = stride * cast(u64) image.height
        let fileSize  = cast(u64) #sizeof(FileHeader) + #sizeof(Header) + imageSize
        if fileSize > Swag.U32.Max do
            throw UnsupportedFormatError{"image is too big"}

        var fileHeader: FileHeader
        fileHeader.bfType    = 0x4d42
        fileHeader.bfSize    = cast(u32) fileSize
        fileHeader.bfOffBits = #sizeof(FileHeader) + #sizeof(Header)
        result.addStruct(fileHeader)

        var header: Header
        header.biSize        = #sizeof(Header)
        header.biWidth       = image.width
        header.biHeight      = image.height
        header.biPlanes      = 1
        header.biBitCount    = image.bpp
        header.biCompression = BI_RGB
        header.biSizeImage   = cast(u32) imageSize
        result.addStruct(header)

        var psrc = image.pixels.buffer
        for image.height
        {
            switch image.pf
            {
            case BGR8, BGRA8:
                result.addBytes(@mkslice(psrc, rowBytes))
                psrc += rowBytes

            case RGB8:
                for image.width
                {
                    result.addNative(psrc[2])
                    result.addNative(psrc[1])
                    result.addNative(psrc[0])
                    psrc += 3
                }

            case RGBA8:
                for image.width
                {
                    result.addNative(psrc[2])
                    result.addNative(psrc[1])
                    result.addNative(psrc[0])
                    result.addNative(psrc[3])
                    psrc += 4
                }
            }

            let padding = stride - rowBytes
            if padding
            {
                for padding do
                    result.addNative(0'u8)
            }
        }
    }
}
