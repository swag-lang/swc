//! Format: OpenEXR scanline encoder.
//! Supported: Single-part, uncompressed Y, YA, RGB, and RGBA scanlines in half or full float.
//! Not supported: Compression, tiles, deep data, multipart files, auxiliary channels, or previews.
//! Role: This file writes fast, lossless HDR interchange from every packed Pixel image.
//
#global namespace Exr

using Core, Core.Errors

internal struct Encoder {}

#[Swag.Inline]
func writeU32(result: *ConcatBuffer, value: u32)
{
    result.addNative(cast(u8, (value & 0xFF)))
    result.addNative(cast(u8, ((value >> 8) & 0xFF)))
    result.addNative(cast(u8, ((value >> 16) & 0xFF)))
    result.addNative(cast(u8, ((value >> 24) & 0xFF)))
}

func writeText(result: *ConcatBuffer, value: string)
{
    result.addBytes(value)
    result.addNative(0'u8)
}

func writeAttribute(result: *ConcatBuffer, name, type: string, payload: const [..] u8)
{
    writeText(result, name)
    writeText(result, type)
    writeU32(result, cast(u32, payload.count))
    result.addBytes(payload)
}

func channelEntry(result: *ConcatBuffer, name: string, pixelType: u32)
{
    writeText(result, name)
    writeU32(result, pixelType)
    writeU32(result, 0)
    writeU32(result, 1)
    writeU32(result, 1)
}

#[Swag.Inline]
func(T, CHANNELS: u64) writeScanlinePlanes(destination: [*] u8, source: const [*] u8, width: u64)
{
    #static if CHANNELS == 1 do
        Memory.copy(destination, source, width * #sizeof(T))
    else
    {
        let packed = cast(const [*] T, source)
        let planes = cast([*] T, destination)
        for x in width
        {
            let pixel = packed + x * CHANNELS
            planes[x]         = pixel[CHANNELS - 1]
            planes[width + x] = pixel[CHANNELS - 2]
            #static if CHANNELS >= 3 do
                planes[2 * width + x] = pixel[CHANNELS - 3]
            #static if CHANNELS == 4 do
                planes[3 * width + x] = pixel[0]
        }
    }
}

func(T, CHANNELS: u64) writeScanlines(destination: [*] u8, source: const *Image, fileOffset: u64)
{
    let width      = cast(u64, source.width)
    let rows       = cast(u64, source.height)
    let rowBytes   = width * #sizeof(T) * CHANNELS
    let chunkBytes = rowBytes + 8
    let offsets    = cast([*] u64, destination)
    let tableBytes = 8 * rows
    let chunks     = destination + tableBytes
    let pixels     = source.pixels.storage()
    let stride     = cast(u64, source.rowStride)

    for y in rows
    {
        let chunkOffset = y * chunkBytes
        offsets[y] = Math.nativeToLittleEndian(fileOffset + tableBytes + chunkOffset)
        let chunk  = chunks + chunkOffset
        let header = cast([*] u32, chunk)
        header[0] = Math.nativeToLittleEndian(cast(u32, y))
        header[1] = Math.nativeToLittleEndian(cast(u32, rowBytes))
        let row = pixels + (rows - y - 1) * stride
        writeScanlinePlanes'(T, CHANNELS)(chunk + 8, row, width)
    }
}

func(T) writeChannelLayout(destination: [*] u8, source: const *Image, fileOffset: u64)
{
    switch source.pixelFormat.channels()
    {
    case 1:  writeScanlines'(T, 1)(destination, source, fileOffset)
    case 2:  writeScanlines'(T, 2)(destination, source, fileOffset)
    case 3:  writeScanlines'(T, 3)(destination, source, fileOffset)
    default: writeScanlines'(T, 4)(destination, source, fileOffset)
    }
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"EXR - OpenEXR", ".exr"}

    mtd impl encode(result: *ConcatBuffer, image: Image, _: any?) fail
    {
        if not image.isValid() or not image.pixelFormat.isPacked() do
            fail InvalidFormatError{"invalid packed image"}

        let grayscale = image.pixelFormat.isGrayscale()
        let fullFloat = image.pixelFormat == .GrayF32 or
                        image.pixelFormat == .GrayAlphaF32 or
                        image.pixelFormat == .RGBF32 or
                        image.pixelFormat == .RGBAF32
        var target: PixelFormat
        if fullFloat
        {
            if grayscale
            {
                target = image.pixelFormat.hasAlpha() ? PixelFormat.GrayAlphaF32 : PixelFormat.GrayF32
            }
            else
            {
                target = image.pixelFormat.hasAlpha() ? PixelFormat.RGBAF32 : PixelFormat.RGBF32
            }
        }
        else
        {
            if grayscale
            {
                target = image.pixelFormat.hasAlpha() ? PixelFormat.GrayAlphaF16 : PixelFormat.GrayF16
            }
            else
            {
                target = image.pixelFormat.hasAlpha() ? PixelFormat.RGBAF16 : PixelFormat.RGBF16
            }
        }

        var converted: Image
        var source:    const *Image = &image
        if image.pixelFormat != target
        {
            converted = image.convertedTo(target)
            source    = &converted
        }

        let pixelType   = fullFloat ? 2'u32 : 1'u32
        let sampleBytes = pixelType == 2 ? 4'u64 : 2'u64
        const RgbNames:       [3] string = ["B", "G", "R"]
        const RgbaNames:      [4] string = ["A", "B", "G", "R"]
        const GrayNames:      [1] string = ["Y"]
        const GrayAlphaNames: [2] string = ["A", "Y"]
        var names: const [..] string
        if grayscale do
            names = source.pixelFormat.hasAlpha() ? GrayAlphaNames : GrayNames
        else do
            names = source.pixelFormat.hasAlpha() ? RgbaNames : RgbNames

        let rowBytes = cast(u64, source.width) * sampleBytes * names.count
        if rowBytes > Swag.U32.Max do
            fail InvalidFormatError{"OpenEXR scanline exceeds its packed size field"}
        let scanlineBytes = cast(u64, source.height) * (rowBytes + 16)

        // Leave room for the fixed attributes and the complete scanline data in one bucket.
        if not result.count() do
            result.grow(512 + scanlineBytes)

        writeU32(result, Magic)
        writeU32(result, 2)
        var channels: ConcatBuffer
        for name in names do
            channelEntry(&channels, name, pixelType)
        channels.addNative(0'u8)
        writeAttribute(result, "channels", "chlist", unwrap channels.toSlice())
        const NoCompression: [1] u8 = [0]
        writeAttribute(result, "compression", "compression", NoCompression)

        var box: ConcatBuffer
        writeU32(&box, 0)
        writeU32(&box, 0)
        writeU32(&box, cast(u32, source.width) - 1)
        writeU32(&box, cast(u32, source.height) - 1)
        writeAttribute(result, "dataWindow", "box2i", unwrap box.toSlice())
        writeAttribute(result, "displayWindow", "box2i", unwrap box.toSlice())
        const IncreasingY: [1] u8 = [0]
        writeAttribute(result, "lineOrder", "lineOrder", IncreasingY)
        const One:   [4] u8 = [0, 0, 0x80, 0x3F]
        const Zero2: [8] u8 = [0, 0, 0, 0, 0, 0, 0, 0]
        writeAttribute(result, "pixelAspectRatio", "float", One)
        writeAttribute(result, "screenWindowCenter", "v2f", Zero2)
        writeAttribute(result, "screenWindowWidth", "float", One)
        result.addNative(0'u8)

        let fileOffset = result.count()
        let scanlines  = result.reserveInPlace(scanlineBytes)
        if fullFloat do
            writeChannelLayout'u32(scanlines, source, fileOffset)
        else do
            writeChannelLayout'u16(scanlines, source, fileOffset)
    }
}
