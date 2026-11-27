//! Format: Graphics Interchange Format (GIF89a) encoder component.
//! Supported: One 8-bit RGB, BGR, grayscale, or alpha frame with a generated palette, LZW compression, and binary transparency.
//! Not supported: Interlaced output and partial alpha; animations are written by [[Gif.AnimationWriter]].
//! Role: This file owns encoder state and top-level GIF emission.
//
#global namespace Gif

using Swag, Core, Core.Errors

private
{
    const MaxPaletteColors = 256_u32

    struct PaletteColor
    {
        r, g, b: u8
    }

    struct PaletteData
    {
        colors:           [256] PaletteColor
        count:            u32
        tableBits:        u8
        lzwMinCodeSize:   u8
        transparentIndex: s32 = -1
        indexes:          Array!{u8}
    }

    struct(T) HistogramCell
    {
        count: T
        red, green, blue: T
    }

    struct ColorBox
    {
        minRed, maxRed, minGreen, maxGreen, minBlue, maxBlue: s32
        pixels: u64
        redTotal, greenTotal, blueTotal: u64
    }
}

// Encodes a single GIF image using a generated palette and LZW compression.
internal struct Encoder {}

impl Encoder
{
    func writeU16(result: *ConcatBuffer, value: u16)
    {
        result.addNative(cast(u8, (value & 0xFF)))
        result.addNative(cast(u8, (value >> 8)))
    }
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"GIF - Graphics Interchange Format", ".gif"}

    mtd impl encode(result: *ConcatBuffer, image: Image, _: any?) fail
    {
        if image.width <= 0 or
           image.height <= 0 or
           not image.isValid() or
           image.pixels.count != image.byteCount
        {
            fail InvalidFormatError{"invalid image"}
        }

        if image.width > Swag.U16.Max
        {
            fail UnsupportedFormatError{"width is too big"}
        }

        if image.height > Swag.U16.Max
        {
            fail UnsupportedFormatError{"height is too big"}
        }

        if image.pixelFormat != .RGB8 and
           image.pixelFormat != .BGR8 and
           image.pixelFormat != .RGBA8 and
           image.pixelFormat != .BGRA8 and
           image.pixelFormat != .Gray8 and
           image.pixelFormat != .GrayAlpha8
        {
            fail UnsupportedFormatError{"unsupported pixel format"}
        }

        var palette:  PaletteData
        var literals: [256] u8
        let pixelCount = cast(u64, image.width) * image.height
        let uniform    = pixelCount >= 256 and tryBuildUniformPalette(&palette, image, pixelCount)
        let fullGray   = not uniform and
                         image.pixelFormat == .Gray8 and
                         image.width >= 256 and
                         tryBuildFullGrayPalette(&palette, image, &literals)
        if not uniform and not fullGray
        {
            palette = buildPalette(image)
        }

        let packed = 0x80_u8 | ((palette.tableBits - 1) << 4) | (palette.tableBits - 1)

        result.addBytes("GIF89a")
        Encoder.writeU16(result, cast(u16, image.width))
        Encoder.writeU16(result, cast(u16, image.height))
        result.addNative(packed)
        result.addNative(0_u8)
        result.addNative(0_u8)
        Encoder.writeColorTable(result, palette)

        if palette.transparentIndex >= 0
        {
            result.addNative(0x21_u8)
            result.addNative(0xF9_u8)
            result.addNative(0x04_u8)
            result.addNative(0x01_u8)
            Encoder.writeU16(result, 0)
            result.addNative(cast(u8, palette.transparentIndex))
            result.addNative(0_u8)
        }

        result.addNative(0x2C_u8)
        Encoder.writeU16(result, 0)
        Encoder.writeU16(result, 0)
        Encoder.writeU16(result, cast(u16, image.width))
        Encoder.writeU16(result, cast(u16, image.height))
        result.addNative(0_u8)
        result.addNative(palette.lzwMinCodeSize)

        var compressed: Array!{u8}
        if uniform
        {
            compressed = lzwCompressRepeat(0, pixelCount, palette.lzwMinCodeSize)
        }
        else if fullGray
        {
            compressed = lzwCompressGray(palette.indexes.toSlice(), &literals[0])
        }
        else
        {
            compressed = lzwCompress(palette.indexes.toSlice(), palette.lzwMinCodeSize, palette.count == 1)
        }

        Encoder.writeSubBlocks(result, compressed.toSlice())

        result.addNative(0x3B_u8)
    }
}
