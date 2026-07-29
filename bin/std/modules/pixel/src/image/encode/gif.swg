#global namespace Gif

using Swag, Core, Core.Errors

private
{
    const MaxPaletteColors = 128'u32

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
}

// Encodes a single GIF image using a generated palette and LZW compression.
public struct Encoder {}

impl Encoder
{
    func writeU16(result: *ConcatBuffer, value: u16)
    {
        result.addNative(cast(u8) (value & 0xFF))
        result.addNative(cast(u8) (value >> 8))
    }
}

public impl IImageEncoder for Encoder
{
    mtd impl canEncode(fileName: string)->bool
    {
        return Path.getExtensionLowerCase(fileName) == ".gif"
    }

    mtd impl encode(result: *ConcatBuffer, image: Image, options: #null any) fail
    {
        if image.width <= 0 or image.height <= 0 or !image.pixels.buffer do
            fail InvalidFormatError{"invalid image"}
        if image.width > Swag.U16.Max do
            fail UnsupportedFormatError{"width is too big"}
        if image.height > Swag.U16.Max do
            fail UnsupportedFormatError{"height is too big"}

        let palette = buildPalette(image)
        let packed  = 0x80'u8 | ((palette.tableBits - 1) << 4) | (palette.tableBits - 1)

        result.addBytes("GIF89a")
        Encoder.writeU16(result, cast(u16) image.width)
        Encoder.writeU16(result, cast(u16) image.height)
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
            result.addNative(cast(u8) palette.transparentIndex)
            result.addNative(0'u8)
        }

        result.addNative(0x2C'u8)
        Encoder.writeU16(result, 0)
        Encoder.writeU16(result, 0)
        Encoder.writeU16(result, cast(u16) image.width)
        Encoder.writeU16(result, cast(u16) image.height)
        result.addNative(0'u8)
        result.addNative(palette.lzwMinCodeSize)

        let compressed = lzwCompress(palette.indexes.toSlice(), palette.lzwMinCodeSize)
        Encoder.writeSubBlocks(result, compressed.toSlice())

        result.addNative(0x3B'u8)
    }
}
