#global namespace Ico

using Core, Core.Errors

public struct Encoder {}

public impl IImageEncoder for Encoder
{
    mtd impl canEncode(fileName: string)->bool
    {
        return Path.getExtensionLowerCase(fileName) == ".ico"
    }

    // Encode a single image as a 32-bit BGRA DIB icon entry with an empty AND mask.
    // The alpha channel carries transparency; the AND mask is left fully opaque.
    mtd impl encode(result: *ConcatBuffer, image: Image, options: #null any) throw
    {
        if image.width <= 0 or image.height <= 0 or !image.pixels.buffer do
            throw InvalidFormatError{"invalid image"}
        if image.width > 256 or image.height > 256 do
            throw UnsupportedFormatError{"icon dimensions must be <= 256"}

        let width  = image.width
        let height = image.height

        let xorStride = cast(u64) width * 4
        let andStride = (((cast(u64) width) + 31) / 32) * 4
        let xorBytes  = xorStride * cast(u64) height
        let andBytes  = andStride * cast(u64) height
        let dibBytes  = cast(u64) #sizeof(DibHeader) + xorBytes + andBytes

        // ICONDIR
        var dir: IconDir
        dir.reserved = 0
        dir.type     = 1
        dir.count    = 1
        result.addStruct(dir)

        // ICONDIRENTRY
        var entry: IconDirEntry
        entry.width       = cast(u8) (width == 256 ? 0 : width)
        entry.height      = cast(u8) (height == 256 ? 0 : height)
        entry.colorCount  = 0
        entry.reserved    = 0
        entry.planes      = 1
        entry.bitCount    = 32
        entry.bytesInRes  = cast(u32) dibBytes
        entry.imageOffset = #sizeof(IconDir) + #sizeof(IconDirEntry)
        result.addStruct(entry)

        // BITMAPINFOHEADER (height is doubled to account for the AND mask)
        var dib: DibHeader
        dib.size      = #sizeof(DibHeader)
        dib.width     = width
        dib.height    = height * 2
        dib.planes    = 1
        dib.bitCount  = 32
        dib.sizeImage = cast(u32) xorBytes
        result.addStruct(dib)

        // XOR (color) data, bottom-up BGRA - matches the internal buffer convention
        for y in height
        {
            var psrc = image.pixels.buffer + cast(u64) y * image.width8

            switch image.pf
            {
            case BGRA8:
                result.addBytes(@mkslice(psrc, xorStride))

            case BGR8:
                for width
                {
                    result.addNative(psrc[0])
                    result.addNative(psrc[1])
                    result.addNative(psrc[2])
                    result.addNative(255'u8)
                    psrc += 3
                }

            case RGBA8:
                for width
                {
                    result.addNative(psrc[2])
                    result.addNative(psrc[1])
                    result.addNative(psrc[0])
                    result.addNative(psrc[3])
                    psrc += 4
                }

            case RGB8:
                for width
                {
                    result.addNative(psrc[2])
                    result.addNative(psrc[1])
                    result.addNative(psrc[0])
                    result.addNative(255'u8)
                    psrc += 3
                }
            }
        }

        // AND (transparency) mask, fully opaque
        for andBytes do
            result.addNative(0'u8)
    }
}
