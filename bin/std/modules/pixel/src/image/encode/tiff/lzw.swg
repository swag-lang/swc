//! Format: Tagged Image File Format (TIFF) encoder component.
//! Supported: Little-endian baseline 8-bit grayscale, RGB, and RGBA in one strip using no compression, PackBits, or LZW.
//! Not supported: Big-endian, planar, tiled, multi-page, JPEG/Deflate, and non-8-bit output.
//! Role: This file owns TIFF LZW dictionary encoding.
//
#global namespace Tiff

using Core

struct LzwBitWriter
{
    result:      *Array'u8
    pending:     u64
    pendingBits: u32
}

impl LzwBitWriter
{
    mtd write(code, width: u32)
    {
        .pending     = (.pending << width) | code
        .pendingBits += width

        while .pendingBits >= 8
        {
            .pendingBits -= 8
            .result.add(cast(u8) (.pending >> .pendingBits))
            .pending &= (1'u64 << .pendingBits) - 1
        }
    }

    mtd finish()
    {
        if .pendingBits do
            .result.add(cast(u8) (.pending << (8 - .pendingBits)))
    }
}

// Encode one TIFF strip with MSB-first, early-transition LZW codes.
func packLzw(result: *Array'u8, src: const [*] u8, count: u64)
{
    var writer: LzwBitWriter = undefined
    writer.result      = result
    writer.pending     = 0
    writer.pendingBits = 0
    writer.write(LZW_CLEAR_CODE, 9)

    if !count
    {
        writer.write(LZW_EOI_CODE, 9)
        writer.finish()
        return
    }

    var dictionary: HashTable'(u32, u16)
    dictionary.reserve(4096)

    var width    = 9'u32
    var nextCode = LZW_FIRST_CODE
    var prefix   = cast(u32) src[0]

    for i in count - 1
    {
        let value = cast(u32) src[i + 1]
        let key   = (prefix << 8) | value
        let found = dictionary.tryFind(key)
        if found
        {
            prefix = found.value
            continue
        }

        writer.write(prefix, width)

        if nextCode <= LZW_MAX_CODE
        {
            dictionary.add(key, cast(u16) nextCode)
            nextCode += 1

            if width < 12 and nextCode > (1'u32 << width) - 1 do
                width += 1
        }
        else
        {
            writer.write(LZW_CLEAR_CODE, width)
            dictionary.clear()
            width    = 9
            nextCode = LZW_FIRST_CODE
        }

        prefix = value
    }

    writer.write(prefix, width)
    writer.write(LZW_EOI_CODE, width)
    writer.finish()
}

func applyHorizontalPredictor(data: [*] u8, rowBytes, rows, samples: u64)
{
    for y in rows
    {
        let row    = data + y * rowBytes
        var offset = rowBytes
        while offset > samples
        {
            offset      -= 1
            row[offset] -= #wrap row[offset - samples]
        }
    }
}
