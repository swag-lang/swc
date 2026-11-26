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
    let stop = Math.min(limit, count > 2 ? count - 2 : 0)
    var i    = first
    while i + 16 <= stop
    {
        let values = Math.Simd.load(source + i)
        let pairs  = values == Math.Simd.load(source + i + 1)
        let triple = pairs & (values == Math.Simd.load(source + i + 2))
        let mask   = Math.Simd.bitmask(triple)
        if mask do
            return i + Math.trailingZeros(mask)
        i += 16
    }

    while i < stop
    {
        if source[i] == source[i + 1] and source[i] == source[i + 2] do
            return i
        i += 1
    }

    return limit
}

private func countPackBitsRun(source: const [*] u8, start, limit: u64)->u64
{
    let value = source[start]
    let group = Math.Simd.splat(value)
    var end   = start + 3
    while end + 16 <= limit
    {
        let mask = Math.Simd.bitmask(Math.Simd.load(source + end) != group)
        if mask do
            return end + Math.trailingZeros(mask) - start
        end += 16
    }

    while end < limit and source[end] == value do
        end += 1
    return end - start
}

func packBitsRow(result: *Array'u8, source: const [*] u8, count: u64)
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
            let end    = nextPackBitsRun(source, index + 1, limit, count)
            let length = end - index
            result.add(cast(u8, (length - 1)))
            result.add(Swag.makeSlice(source + index, length))
            index = end
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

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"TIFF - Tagged Image File Format", ".tif;.tiff"}

    // Encode a little-endian, single-strip baseline RGB(A) TIFF.
    mtd impl encode(result: *ConcatBuffer, image: Image, options: any?) fail
    {
        var userOptions: EncodeOptions
        if options.buffer != null
        {
            if Swag.kindOf(options) != EncodeOptions do
                fail BadParameterError{"TIFF encoder options must be Tiff.EncodeOptions"}
            userOptions = cast(const *EncodeOptions, unwrap options.buffer)[]
        }

        if image.width <= 0 or
           image.height <= 0 or
           not image.isValid() or
           image.pixels.count != image.byteCount do
            fail InvalidFormatError{"invalid image"}
        if image.pixelFormat != .Gray8 and
           image.pixelFormat != .RGB8 and
           image.pixelFormat != .BGR8 and
           image.pixelFormat != .RGBA8 and
           image.pixelFormat != .BGRA8 do
            fail UnsupportedFormatError{"unsupported pixel format"}

        let width     = image.width
        let height    = image.height
        let hasAlpha  = image.pixelFormat.hasAlpha()
        let samples   = cast(u32, image.pixelFormat.channels())
        let grayscale = image.pixelFormat == .Gray8

        let rowBytes   = cast(u64, width) * samples
        let rawDataLen = rowBytes * cast(u64, height)
        if rawDataLen > Swag.U32.Max do
            fail UnsupportedFormatError{"image is too big"}

        var packedData:   Array'u8
        var storedLen      = rawDataLen
        var compressionTag = COMPRESSION_NONE
        var hasPredictor: bool
        if userOptions.compression == .Lzw or userOptions.compression == .PackBits
        {
            var rawData: Array'u8
            rawData.reserve(rawDataLen)
            encodeFileRows(image, rawData.storage(), rowBytes)
            if userOptions.compression == .Lzw
            {
                applyHorizontalPredictor(rawData.storage(), rowBytes, cast(u64, height), samples)
                packLzw(&packedData, rawData.storage(), rawDataLen)
                compressionTag = COMPRESSION_LZW
                hasPredictor   = true
            }
            else
            {
                for y in height do
                    packBitsRow(&packedData, rawData.storage() + cast(u64, y) * rowBytes, rowBytes)
                compressionTag = COMPRESSION_PACKBITS
            }

            storedLen = packedData.count
        }

        // Layout: header(8) | pixel data | IFD | BitsPerSample array
        let dataPad    = storedLen & 1
        let ifdOffset  = 8 + storedLen + dataPad
        let numEntries = (hasAlpha ? 10'u32 : 9'u32) + cast(u32, hasPredictor)
        let ifdLen     = 2'u64 + cast(u64, numEntries) * 12 + 4
        let bpsOffset  = ifdOffset + ifdLen
        if bpsOffset + cast(u64, samples) * 2 > Swag.U32.Max do
            fail UnsupportedFormatError{"image is too big"}

        // Header
        result.addNative(0x4949'u16)     // "II" little-endian
        result.addNative(42'u16)         // magic
        result.addNative(cast(u32, ifdOffset))     // offset to first IFD

        if compressionTag == COMPRESSION_NONE do
            encodeFileRows(image, result.reserveInPlace(storedLen), rowBytes)
        else do
            result.addBytes(packedData.toSlice())

        if dataPad do
            result.addNative(0'u8)

        // IFD (entries must be in ascending tag order)
        result.addNative(cast(u16, numEntries))
        addEntry(result, TAG_IMAGE_WIDTH, TYPE_LONG, 1, cast(u32, width))
        addEntry(result, TAG_IMAGE_LENGTH, TYPE_LONG, 1, cast(u32, height))
        addEntry(result, TAG_BITS_PER_SAMPLE, TYPE_SHORT, samples, samples == 1 ? 8'u32 : cast(u32, bpsOffset))
        addEntry(result, TAG_COMPRESSION, TYPE_SHORT, 1, compressionTag)
        addEntry(result, TAG_PHOTOMETRIC, TYPE_SHORT, 1, grayscale ? PHOTO_BLACK_IS_ZERO : PHOTO_RGB)
        addEntry(result, TAG_STRIP_OFFSETS, TYPE_LONG, 1, 8)
        addEntry(result, TAG_SAMPLES_PER_PIXEL, TYPE_SHORT, 1, samples)
        addEntry(result, TAG_ROWS_PER_STRIP, TYPE_LONG, 1, cast(u32, height))
        addEntry(result, TAG_STRIP_BYTE_COUNTS, TYPE_LONG, 1, cast(u32, storedLen))
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
