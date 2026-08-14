#global namespace Tiff

using Core, Core.Errors

// Encodes little-endian baseline TIFF images.
internal struct Encoder {}

// Selects the strip compression used by the TIFF encoder.
public enum Compression
{
    None         // Store uncompressed pixel bytes.
    PackBits     // Use PackBits run-length encoding.
    Lzw          // Use TIFF LZW compression with horizontal differencing.
}

// Configures TIFF strip compression.
public struct EncodeOptions
{
    public compression: Compression     // Compression applied to image strips; defaults to `.None`.
}

// Append one 12-byte IFD entry (little-endian).
func addEntry(result: *ConcatBuffer, tag, type: u16, count, value: u32)
{
    result.addNative(tag)
    result.addNative(type)
    result.addNative(count)
    result.addNative(value)
}

func tiffRunLength(src: const [*] u8, index, count: u64)->u64
{
    var result: retval = 1
    while result < 128 and index + result < count and src[index] == src[index + result] do
        result += 1
    return result
}

func packBitsRow(result: *Array'u8, src: const [*] u8, count: u64)
{
    var index: u64
    while index < count
    {
        let runLength = tiffRunLength(src, index, count)
        if runLength >= 3
        {
            result.add(cast(u8) (257 - runLength))
            result.add(src[index])
            index += runLength
            continue
        }

        let literalStart = index
        index += runLength
        while index < count and index - literalStart < 128
        {
            let nextRun = tiffRunLength(src, index, count)
            if nextRun >= 3 do
                break

            let available = 128 - (index - literalStart)
            index += Math.min(nextRun, available)
        }

        let literalCount = index - literalStart
        result.add(cast(u8) (literalCount - 1))
        result.add(@mkslice(src + literalStart, literalCount))
    }
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"TIFF - Tagged Image File Format", ".tif;.tiff"}

    // Encode a little-endian, single-strip baseline RGB(A) TIFF.
    mtd impl encode(result: *ConcatBuffer, image: Image, options: #null any) fail
    {
        var userOptions: EncodeOptions
        if @dataof(options) != null
        {
            Debug.assert(@kindof(options) == EncodeOptions)
            userOptions = (cast(*EncodeOptions) @dataof(options)!)[]
        }

        if image.width <= 0 or image.height <= 0 or !image.pixels.buffer do
            fail InvalidFormatError{"invalid image"}

        let width    = image.width
        let height   = image.height
        let hasAlpha = image.pixelFormat.hasAlpha()
        let samples  = hasAlpha ? 4'u32 : 3'u32

        let rowBytes   = cast(u64) width * samples
        let rawDataLen = rowBytes * cast(u64) height
        if rawDataLen > Swag.U32.Max do
            fail UnsupportedFormatError{"image is too big"}

        // Pixel data, top-down RGB(A). The internal buffer is bottom-up.
        var rawData: Array'u8
        rawData.reserve(rawDataLen)
        for fileY in height
        {
            let srcY = height - fileY - 1
            var psrc = image.pixels.buffer + cast(u64) srcY * image.rowStride

            for width
            {
                switch image.pixelFormat
                {
                case .RGB8:
                    rawData.add(psrc[0])
                    rawData.add(psrc[1])
                    rawData.add(psrc[2])

                case .BGR8:
                    rawData.add(psrc[2])
                    rawData.add(psrc[1])
                    rawData.add(psrc[0])

                case .RGBA8:
                    rawData.add(psrc[0])
                    rawData.add(psrc[1])
                    rawData.add(psrc[2])
                    rawData.add(psrc[3])

                case .BGRA8:
                    rawData.add(psrc[2])
                    rawData.add(psrc[1])
                    rawData.add(psrc[0])
                    rawData.add(psrc[3])
                }

                psrc += image.bytesPerPixel
            }
        }

        var packedData:   Array'u8
        var storedData     = cast(const [*] u8) rawData.buffer!
        var storedLen      = rawData.count
        var compressionTag = COMPRESSION_NONE
        var hasPredictor: bool
        if userOptions.compression == .Lzw
        {
            applyHorizontalPredictor(rawData.buffer!, rowBytes, cast(u64) height, samples)
            packLzw(&packedData, storedData, storedLen)
            storedData     = cast(const [*] u8) packedData.buffer!
            storedLen      = packedData.count
            compressionTag = COMPRESSION_LZW
            hasPredictor   = true
        }
        elif userOptions.compression == .PackBits
        {
            for y in height do
                packBitsRow(&packedData, storedData + cast(u64) y * rowBytes, rowBytes)
            storedData     = cast(const [*] u8) packedData.buffer!
            storedLen      = packedData.count
            compressionTag = COMPRESSION_PACKBITS
        }

        // Layout: header(8) | pixel data | IFD | BitsPerSample array
        let dataPad    = storedLen & 1
        let ifdOffset  = 8 + storedLen + dataPad
        let numEntries = (hasAlpha ? 10'u32 : 9'u32) + cast(u32) hasPredictor
        let ifdLen     = cast(u64) 2 + cast(u64) numEntries * 12 + 4
        let bpsOffset  = ifdOffset + ifdLen
        if bpsOffset + cast(u64) samples * 2 > Swag.U32.Max do
            fail UnsupportedFormatError{"image is too big"}

        // Header
        result.addNative(0x4949'u16)              // "II" little-endian
        result.addNative(42'u16)                  // magic
        result.addNative(cast(u32) ifdOffset)     // offset to first IFD

        result.addBytes(@mkslice(storedData, storedLen))

        if dataPad do
            result.addNative(0'u8)

        // IFD (entries must be in ascending tag order)
        result.addNative(cast(u16) numEntries)
        addEntry(result, TAG_IMAGE_WIDTH, TYPE_LONG, 1, cast(u32) width)
        addEntry(result, TAG_IMAGE_LENGTH, TYPE_LONG, 1, cast(u32) height)
        addEntry(result, TAG_BITS_PER_SAMPLE, TYPE_SHORT, samples, cast(u32) bpsOffset)
        addEntry(result, TAG_COMPRESSION, TYPE_SHORT, 1, compressionTag)
        addEntry(result, TAG_PHOTOMETRIC, TYPE_SHORT, 1, PHOTO_RGB)
        addEntry(result, TAG_STRIP_OFFSETS, TYPE_LONG, 1, 8)
        addEntry(result, TAG_SAMPLES_PER_PIXEL, TYPE_SHORT, 1, samples)
        addEntry(result, TAG_ROWS_PER_STRIP, TYPE_LONG, 1, cast(u32) height)
        addEntry(result, TAG_STRIP_BYTE_COUNTS, TYPE_LONG, 1, cast(u32) storedLen)
        if hasPredictor do
            addEntry(result, TAG_PREDICTOR, TYPE_SHORT, 1, 2)
        if hasAlpha do
            addEntry(result, TAG_EXTRA_SAMPLES, TYPE_SHORT, 1, 2)     // 2 = unassociated alpha

        result.addNative(0'u32)     // next IFD offset

        // BitsPerSample values
        for samples do
            result.addNative(8'u16)
    }
}
