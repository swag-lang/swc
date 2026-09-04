//! Format: OpenEXR scanline encoder.
//! Supported: Single-part, uncompressed RGB or RGBA scanlines stored as half or full float.
//! Not supported: Compression, tiles, deep data, multipart files, auxiliary channels, or previews.
//! Role: This file writes fast, lossless HDR interchange from every packed Pixel image.
//
#global namespace Exr

using Core, Core.Errors

internal struct Encoder {}

#[Swag.Inline]
func writeU32(result: *ConcatBuffer, value: u32)
{
    result.addNative(cast(u8) (value & 0xFF))
    result.addNative(cast(u8) ((value >> 8) & 0xFF))
    result.addNative(cast(u8) ((value >> 16) & 0xFF))
    result.addNative(cast(u8) ((value >> 24) & 0xFF))
}

#[Swag.Inline]
func writeU64(result: *ConcatBuffer, value: u64)
{
    writeU32(result, cast(u32) (value & 0xFFFF_FFFF))
    writeU32(result, cast(u32) (value >> 32))
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
    writeU32(result, cast(u32) payload.count)
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

func channelOffset(name: string, grayscale: bool)->u64
{
    switch name
    {
    case "R": return 0
    case "G": return 1
    case "B": return 2
    case "A": return grayscale ? 1 : 3
    case "Y": return 0
    }

    return 0
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"EXR - OpenEXR", ".exr"}

    mtd impl encode(result: *ConcatBuffer, image: Image, options: any?) fail
    {
        discard options
        if !image.isValid() or !image.pixelFormat.isPacked() do
            fail InvalidFormatError{"invalid packed image"}

        let grayscale = image.pixelFormat.isGrayscale()
        let fullFloat = image.pixelFormat == .GrayF32 or image.pixelFormat == .GrayAlphaF32 or image.pixelFormat == .RGBF32 or image.pixelFormat == .RGBAF32
        let target    = fullFloat ?
                        (grayscale ? (image.pixelFormat.hasAlpha() ? PixelFormat.GrayAlphaF32 : PixelFormat.GrayF32) :
                         (image.pixelFormat.hasAlpha() ? PixelFormat.RGBAF32 : PixelFormat.RGBF32)) :
                        (grayscale ? (image.pixelFormat.hasAlpha() ? PixelFormat.GrayAlphaF16 : PixelFormat.GrayF16) :
                         (image.pixelFormat.hasAlpha() ? PixelFormat.RGBAF16 : PixelFormat.RGBF16))
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

        writeU32(result, Magic)
        writeU32(result, 2)
        var channels: ConcatBuffer
        for name in names do
            channelEntry(&channels, name, pixelType)
        channels.addNative(0'u8)
        writeAttribute(result, "channels", "chlist", channels.toSlice()!)
        const NoCompression: [1] u8 = [0]
        writeAttribute(result, "compression", "compression", NoCompression)

        var box: ConcatBuffer
        writeU32(&box, 0)
        writeU32(&box, 0)
        writeU32(&box, cast(u32) source.width - 1)
        writeU32(&box, cast(u32) source.height - 1)
        writeAttribute(result, "dataWindow", "box2i", box.toSlice()!)
        writeAttribute(result, "displayWindow", "box2i", box.toSlice()!)
        const IncreasingY: [1] u8 = [0]
        writeAttribute(result, "lineOrder", "lineOrder", IncreasingY)
        const One:   [4] u8 = [0, 0, 0x80, 0x3F]
        const Zero2: [8] u8 = [0, 0, 0, 0, 0, 0, 0, 0]
        writeAttribute(result, "pixelAspectRatio", "float", One)
        writeAttribute(result, "screenWindowCenter", "v2f", Zero2)
        writeAttribute(result, "screenWindowWidth", "float", One)
        result.addNative(0'u8)

        let rowBytes    = cast(u64) source.width * sampleBytes * names.count
        var chunkOffset = result.count() + cast(u64) source.height * 8
        for source.height
        {
            writeU64(result, chunkOffset)
            chunkOffset += 8 + rowBytes
        }

        for y in source.height
        {
            writeU32(result, cast(u32) y)
            writeU32(result, cast(u32) rowBytes)
            let storageY = source.height - y - 1
            for name in names
            {
                let component = channelOffset(name, grayscale)
                for x in source.width
                {
                    let pixel  = source.pixels.buffer! + cast(u64) storageY * source.rowStride + cast(u64) x * source.bytesPerPixel
                    let sample = pixel + component * sampleBytes
                    result.addBytes(Swag.makeSlice(sample, sampleBytes))
                }
            }
        }
    }
}
