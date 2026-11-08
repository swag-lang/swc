//! Format: Graphics Interchange Format (GIF89a) encoder component.
//! Supported: One indexed frame with generated palette, LZW compression, and binary transparency.
//! Not supported: Interlaced output and partial alpha; animations are written by [[Gif.AnimationWriter]].
//! Role: This file owns encoder state and top-level GIF emission.
//
#global namespace Gif

using Swag, Core, Core.Errors

private
{
    const MaxPaletteColors = 256'u32

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
        indexes:          Array'u8
    }

    struct HistogramCell
    {
        count: u64
        red, green, blue: u64
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
        if image.width <= 0 or image.height <= 0 or not image.pixels.buffer do
            fail InvalidFormatError{"invalid image"}
        if image.width > Swag.U16.Max do
            fail UnsupportedFormatError{"width is too big"}
        if image.height > Swag.U16.Max do
            fail UnsupportedFormatError{"height is too big"}

        let palette = buildPalette(image)
        let packed  = 0x80'u8 | ((palette.tableBits - 1) << 4) | (palette.tableBits - 1)

        result.addBytes("GIF89a")
        Encoder.writeU16(result, cast(u16, image.width))
        Encoder.writeU16(result, cast(u16, image.height))
        result.addNative(packed)
        result.addNative(0'u8)
        result.addNative(0'u8)
        Encoder.writeColorTable(result, palette)

        if palette.transparentIndex >= 0
        {
            result.addNative(0x21'u8)
            result.addNative(0xF9'u8)
            result.addNative(0x04'u8)
            result.addNative(0x01'u8)
            Encoder.writeU16(result, 0)
            result.addNative(cast(u8, palette.transparentIndex))
            result.addNative(0'u8)
        }

        result.addNative(0x2C'u8)
        Encoder.writeU16(result, 0)
        Encoder.writeU16(result, 0)
        Encoder.writeU16(result, cast(u16, image.width))
        Encoder.writeU16(result, cast(u16, image.height))
        result.addNative(0'u8)
        result.addNative(palette.lzwMinCodeSize)

        let compressed = lzwCompress(palette.indexes.toSlice(), palette.lzwMinCodeSize)
        Encoder.writeSubBlocks(result, compressed.toSlice())

        result.addNative(0x3B'u8)
    }
}
