//! Format: DirectDraw Surface encoder.
//! Supported: One uncompressed 2D surface in grayscale or RGB(A), as 8/16-bit normalized, half, or full float.
//! Not supported: Block compression, mipmap generation, texture arrays, cubemaps, or volumes.
//! Role: This file serializes Pixel images using legacy DDS masks or explicit DX10 formats.
//
#global namespace Dds

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

func writeHeader(result: *ConcatBuffer, image: Image, dxgi: u32, flags, bits, redMask, greenMask, blueMask, alphaMask: u32)
{
    writeU32(result, Magic)
    writeU32(result, 124)
    writeU32(result, 0x0000100F)     // CAPS, HEIGHT, WIDTH, PITCH, PIXELFORMAT.
    writeU32(result, cast(u32) image.height)
    writeU32(result, cast(u32) image.width)
    writeU32(result, cast(u32) image.rowStride)
    writeU32(result, 0)
    writeU32(result, 0)
    for 11 do
        writeU32(result, 0)
    writeU32(result, 32)
    writeU32(result, dxgi ? FourCcFlag : flags)
    writeU32(result, dxgi ? 0x30315844'u32 : 0)     // DX10
    writeU32(result, bits)
    writeU32(result, redMask)
    writeU32(result, greenMask)
    writeU32(result, blueMask)
    writeU32(result, alphaMask)
    writeU32(result, 0x1000)     // DDSCAPS_TEXTURE.
    for 4 do
        writeU32(result, 0)

    if dxgi
    {
        writeU32(result, dxgi)
        writeU32(result, 3)     // DDS_DIMENSION_TEXTURE2D.
        writeU32(result, 0)
        writeU32(result, 1)
        writeU32(result, image.pixelFormat.hasAlpha() ? 1 : 3)
    }
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"DDS - DirectDraw Surface", ".dds"}

    mtd impl encode(result: *ConcatBuffer, image: Image, options: any?) fail
    {
        discard options
        if !image.isValid() do
            fail InvalidFormatError{"invalid image"}

        var converted: Image
        var source:    const *Image = &image
        var dxgi  = 0'u32
        var flags = RgbFlag
        var bits  = cast(u32) image.bitsPerPixel
        var redMask, greenMask, blueMask, alphaMask: u32
        switch #complete image.pixelFormat
        {
        case .Gray8:
            flags   = LumaFlag
            redMask = 0xFF

        case .GrayAlpha8:
            flags     = LumaFlag | AlphaFlag
            redMask   = 0xFF
            alphaMask = 0xFF00

        case .Gray16:
            dxgi = 56

        case .GrayAlpha16:
            dxgi = 35

        case .GrayF16:
            dxgi = 54

        case .GrayAlphaF16:
            dxgi = 34

        case .GrayF32:
            dxgi = 41

        case .GrayAlphaF32:
            dxgi = 16

        case .BGR8:
            redMask   = 0xFF0000
            greenMask = 0xFF00
            blueMask  = 0xFF

        case .BGRA8:
            flags     |= AlphaFlag
            redMask   = 0xFF0000
            greenMask = 0xFF00
            blueMask  = 0xFF
            alphaMask = 0xFF000000

        case .RGB8:
            redMask   = 0xFF
            greenMask = 0xFF00
            blueMask  = 0xFF0000

        case .RGBA8:
            flags     |= AlphaFlag
            redMask   = 0xFF
            greenMask = 0xFF00
            blueMask  = 0xFF0000
            alphaMask = 0xFF000000

        case .RGB16:
            converted = image.convertedTo(.RGBA16)
            source    = &converted
            dxgi      = 11

        case .RGBA16:
            dxgi = 11

        case .RGBF16:
            converted = image.convertedTo(.RGBAF16)
            source    = &converted
            dxgi      = 10

        case .RGBAF16:
            dxgi = 10

        case .RGBF32:
            converted = image.convertedTo(.RGBAF32)
            source    = &converted
            dxgi      = 2

        case .RGBAF32:
            dxgi = 2

        case .Yuv420:
            fail UnsupportedFormatError{"DDS encoding requires a packed pixel format"}
        }

        bits = source.bitsPerPixel
        writeHeader(result, source[], dxgi, flags, bits, redMask, greenMask, blueMask, alphaMask)
        for y in source.height
        {
            let storageY = source.height - y - 1
            result.addBytes(Swag.makeSlice(source.pixels.buffer! + cast(u64) storageY * source.rowStride, cast(u64) source.rowStride))
        }
    }
}
