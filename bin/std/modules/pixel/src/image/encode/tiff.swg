#global namespace Tiff

using Core, Core.Errors

public struct Encoder {}

// Append one 12-byte IFD entry (little-endian).
func addEntry(result: *ConcatBuffer, tag, type: u16, count, value: u32)
{
    result.addNative(tag)
    result.addNative(type)
    result.addNative(count)
    result.addNative(value)
}

public impl IImageEncoder for Encoder
{
    mtd impl canEncode(fileName: string)->bool
    {
        let ext = Path.getExtensionLowerCase(fileName)
        return ext == ".tif" or ext == ".tiff"
    }

    // Encode an uncompressed, little-endian, single-strip baseline RGB(A) TIFF.
    mtd impl encode(result: *ConcatBuffer, image: Image, options: #null any) throw
    {
        if image.width <= 0 or image.height <= 0 or !image.pixels.buffer do
            throw InvalidFormatError{"invalid image"}

        let width    = image.width
        let height   = image.height
        let hasAlpha = image.pf.hasAlpha()
        let samples  = hasAlpha ? 4'u32 : 3'u32

        let dataLen = cast(u64) width * cast(u64) height * samples
        if dataLen > Swag.U32.Max do
            throw UnsupportedFormatError{"image is too big"}

        // Layout: header(8) | pixel data | IFD | BitsPerSample array
        let dataPad     = dataLen & 1
        let ifdOffset   = 8 + dataLen + dataPad
        let numEntries  = hasAlpha ? 10'u32 : 9'u32
        let ifdLen      = cast(u64) 2 + cast(u64) numEntries * 12 + 4
        let bpsOffset   = ifdOffset + ifdLen
        if bpsOffset + cast(u64) samples * 2 > Swag.U32.Max do
            throw UnsupportedFormatError{"image is too big"}

        // Header
        result.addNative(0x4949'u16)              // "II" little-endian
        result.addNative(42'u16)                  // magic
        result.addNative(cast(u32) ifdOffset)     // offset to first IFD

        // Pixel data, top-down RGB(A). The internal buffer is bottom-up.
        for [fileY] in height
        {
            let srcY = height - fileY - 1
            var psrc = image.pixels.buffer + cast(u64) srcY * image.width8

            switch image.pf
            {
            case RGB8:
                for width
                {
                    result.addNative(psrc[0])
                    result.addNative(psrc[1])
                    result.addNative(psrc[2])
                    psrc += 3
                }

            case BGR8:
                for width
                {
                    result.addNative(psrc[2])
                    result.addNative(psrc[1])
                    result.addNative(psrc[0])
                    psrc += 3
                }

            case RGBA8:
                for width
                {
                    result.addNative(psrc[0])
                    result.addNative(psrc[1])
                    result.addNative(psrc[2])
                    result.addNative(psrc[3])
                    psrc += 4
                }

            case BGRA8:
                for width
                {
                    result.addNative(psrc[2])
                    result.addNative(psrc[1])
                    result.addNative(psrc[0])
                    result.addNative(psrc[3])
                    psrc += 4
                }
            }
        }

        if dataPad do
            result.addNative(0'u8)

        // IFD (entries must be in ascending tag order)
        result.addNative(cast(u16) numEntries)
        addEntry(result, TAG_IMAGE_WIDTH,       TYPE_LONG,  1,       cast(u32) width)
        addEntry(result, TAG_IMAGE_LENGTH,      TYPE_LONG,  1,       cast(u32) height)
        addEntry(result, TAG_BITS_PER_SAMPLE,   TYPE_SHORT, samples, cast(u32) bpsOffset)
        addEntry(result, TAG_COMPRESSION,       TYPE_SHORT, 1,       COMPRESSION_NONE)
        addEntry(result, TAG_PHOTOMETRIC,       TYPE_SHORT, 1,       PHOTO_RGB)
        addEntry(result, TAG_STRIP_OFFSETS,     TYPE_LONG,  1,       8)
        addEntry(result, TAG_SAMPLES_PER_PIXEL, TYPE_SHORT, 1,       samples)
        addEntry(result, TAG_ROWS_PER_STRIP,    TYPE_LONG,  1,       cast(u32) height)
        addEntry(result, TAG_STRIP_BYTE_COUNTS, TYPE_LONG,  1,       cast(u32) dataLen)
        if hasAlpha do
            addEntry(result, TAG_EXTRA_SAMPLES, TYPE_SHORT, 1, 2)     // 2 = unassociated alpha

        result.addNative(0'u32)     // next IFD offset

        // BitsPerSample values
        for samples do
            result.addNative(8'u16)
    }
}
