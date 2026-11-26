//! Format: Tagged Image File Format (TIFF) encoder component.
//! Supported: Little-endian baseline 8-bit grayscale, RGB, and RGBA in one strip using no compression, PackBits, or LZW.
//! Not supported: Big-endian, planar, tiled, multi-page, JPEG/Deflate, and non-8-bit output.
//! Role: This file owns IFD and strip emission, sample packing, and top-level encoding.
//
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

private func nextPackBitsRun(source: const [*] u8, first, limit, count: u64)->u64
{
    var result: #returntype = 1
    while result < 128 and index + result < count and src[index] == src[index + result]
    {
        result += 1
    }

    return result
}

func packBitsRow(result: *Array!{u8}, src: const [*] u8, count: u64)
{
    var index: u64
    while index < count
    {
        let limit = Math.min(index + 128, count)
        if count - index >= 3 and
           source[index] == source[index + 1] and
           source[index] == source[index + 2]
        {
            let length = countPackBitsRun(source, index, limit)
            result.add(cast(u8, (257 - length)))
            result.add(source[index])
            index += length
        }
        else
        {
            let nextRun = tiffRunLength(src, index, count)
            if nextRun >= 3
            {
                break
            }

            let available = 128 - (index - literalStart)
            index += Math.min(nextRun, available)
        }
    }
}

// The internal rows run bottom to top; TIFF stores them top to bottom in RGB(A) order.
private func encodeFileRows(image: Image, output: [*] u8, rowBytes: u64)
{
    let pixels = image.pixels.storage()
    for fileY in image.height
    {
        let source      = pixels + cast(u64, image.height - fileY - 1) * image.rowStride
        let destination = output + cast(u64, fileY) * rowBytes
        switch image.pixelFormat
        {
        case .BGR8:  PackedPixel.swapRedBlue24Row(source, destination, cast(u64, image.width))
        case .BGRA8: PackedPixel.swapRedBlue32Row(source, destination, cast(u64, image.width))
        default:     Memory.copy(destination, source, rowBytes)
        }
    }
}

private func encodePackBitsRows(output: *Array'u8, image: Image, rowBytes: u64)
{
    let swizzled = image.pixelFormat == .BGR8 or image.pixelFormat == .BGRA8
    var converted: Array'u8
    if swizzled do
        converted.reserve(rowBytes)

    let pixels = image.pixels.storage()
    for fileY in image.height
    {
        let source = pixels + cast(u64, image.height - fileY - 1) * image.rowStride
        if swizzled
        {
            let destination = converted.storage()
            if image.pixelFormat == .BGR8 do
                PackedPixel.swapRedBlue24Row(source, destination, cast(u64, image.width))
            else do
                PackedPixel.swapRedBlue32Row(source, destination, cast(u64, image.width))
            packBitsRow(output, destination, rowBytes)
        }
        else
        {
            packBitsRow(output, source, rowBytes)
        }
    }
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"TIFF - Tagged Image File Format", ".tif;.tiff"}

    // Encode a little-endian, single-strip baseline RGB(A) TIFF.
    mtd impl encode(result: *ConcatBuffer, image: Image, options: any?) fail
    {
        var userOptions: EncodeOptions
        if options.buffer != null
        {
            if Swag.kindOf(options) != EncodeOptions
            {
                fail BadParameterError{"TIFF encoder options must be Tiff.EncodeOptions"}
            }

            userOptions = cast(const *EncodeOptions, unwrap options.buffer)[]
        }

        if image.width <= 0 or
           image.height <= 0 or
           not image.isValid() or
           image.pixels.count != image.byteCount
        {
            fail InvalidFormatError{"invalid image"}
        }

        if image.pixelFormat != .Gray8 and
           image.pixelFormat != .RGB8 and
           image.pixelFormat != .BGR8 and
           image.pixelFormat != .RGBA8 and
           image.pixelFormat != .BGRA8
        {
            fail UnsupportedFormatError{"unsupported pixel format"}
        }

        let width     = image.width
        let height    = image.height
        let hasAlpha  = image.pixelFormat.hasAlpha()
        let samples   = cast(u32, image.pixelFormat.channels())
        let grayscale = image.pixelFormat == .Gray8

        let rowBytes   = cast(u64, width) * samples
        let rawDataLen = rowBytes * cast(u64, height)
        if rawDataLen > Swag.U32.Max
        {
            fail UnsupportedFormatError{"image is too big"}
        }

        // Pixel data, top-down RGB(A). The internal buffer is bottom-up.
        var rawData: Array!{u8}
        rawData.reserve(rawDataLen)
        for fileY in height
        {
            let srcY = height - fileY - 1
            var psrc = cast(const [*] u8, image.pixels.storage()) + cast(u64, srcY) * image.rowStride

            for width
            {
                switch image.pixelFormat
                {
                case .Gray8:
                    rawData.add(psrc[0])

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

                default:
                    break
                }

                psrc += image.bytesPerPixel
            }
        }

        var packedData:   Array!{u8}
        var storedData     = cast(const [*] u8, rawData.storage())
        var storedLen      = rawData.count
        var compressionTag = COMPRESSION_NONE
        var hasPredictor: bool
        if userOptions.compression == .Lzw
        {
            var rawData: Array'u8
            rawData.reserve(rawDataLen)
            let raw = rawData.storage()
            encodeFileRows(image, raw, rowBytes)
            applyHorizontalPredictor(raw, rowBytes, cast(u64, height), samples)
            packLzw(&packedData, raw, rawDataLen)
            storedLen      = packedData.count
            compressionTag = COMPRESSION_LZW
            hasPredictor   = true
        }
        else if userOptions.compression == .PackBits
        {
            for y in height
            {
                packBitsRow(&packedData, storedData + cast(u64, y) * rowBytes, rowBytes)
            }

            storedData     = cast(const [*] u8, packedData.storage())
            storedLen      = packedData.count
            compressionTag = COMPRESSION_PACKBITS
        }

        // Layout: header(8) | pixel data | IFD | BitsPerSample array
        let dataPad    = storedLen & 1
        let ifdOffset  = 8 + storedLen + dataPad
        let numEntries = (hasAlpha ? 10_u32 : 9_u32) + cast(u32, hasPredictor)
        let ifdLen     = 2_u64 + cast(u64, numEntries) * 12 + 4
        let bpsOffset  = ifdOffset + ifdLen
        if bpsOffset + cast(u64, samples) * 2 > Swag.U32.Max
        {
            fail UnsupportedFormatError{"image is too big"}
        }

        // Header
        result.addNative(0x4949_u16)     // "II" little-endian
        result.addNative(42_u16)         // magic
        result.addNative(cast(u32, ifdOffset))     // offset to first IFD

        if compressionTag == COMPRESSION_NONE do
            encodeFileRows(image, result.reserveInPlace(storedLen), rowBytes)
        else do
            result.addBytes(packedData.toSlice())

        if dataPad
        {
            result.addNative(0_u8)
        }

        // IFD (entries must be in ascending tag order)
        result.addNative(cast(u16, numEntries))
        addEntry(result, TAG_IMAGE_WIDTH, TYPE_LONG, 1, cast(u32, width))
        addEntry(result, TAG_IMAGE_LENGTH, TYPE_LONG, 1, cast(u32, height))
        addEntry(result, TAG_BITS_PER_SAMPLE, TYPE_SHORT, samples, samples == 1 ? 8_u32 : cast(u32, bpsOffset))
        addEntry(result, TAG_COMPRESSION, TYPE_SHORT, 1, compressionTag)
        addEntry(result, TAG_PHOTOMETRIC, TYPE_SHORT, 1, grayscale ? PHOTO_BLACK_IS_ZERO : PHOTO_RGB)
        addEntry(result, TAG_STRIP_OFFSETS, TYPE_LONG, 1, 8)
        addEntry(result, TAG_SAMPLES_PER_PIXEL, TYPE_SHORT, 1, samples)
        addEntry(result, TAG_ROWS_PER_STRIP, TYPE_LONG, 1, cast(u32, height))
        addEntry(result, TAG_STRIP_BYTE_COUNTS, TYPE_LONG, 1, cast(u32, storedLen))
        if hasPredictor
        {
            addEntry(result, TAG_PREDICTOR, TYPE_SHORT, 1, 2)
        }

        if hasAlpha
        {
            addEntry(result, TAG_EXTRA_SAMPLES, TYPE_SHORT, 1, 2)
        }     // 2 = unassociated alpha

        result.addNative(0_u32)     // next IFD offset

        // BitsPerSample values
        for samples
        {
            result.addNative(8_u16)
        }
    }
}
