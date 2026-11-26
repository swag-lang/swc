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
    #[Swag.Inline]
    mtd write(code, width: u32)
    {
        .pending = (.pending << width) | code
        let total = .pendingBits + width
        let bytes = total >> 3
        .pendingBits = total & 7
        let word = cast(u16, ((.pending >> .pendingBits) & 0xFFFF))

        let count = .result.count
        let end   = count + bytes
        if end > .result.capacity do
            .result.grow(end)
        let dst = .result.storage() + count
        if bytes == 2 do
            cast(*u16, dst)[] = Math.byteSwap(word)
        else do
            dst[0] = cast(u8, (word & 255))
        .result.count = end
    }

    mtd finish()
    {
        if .pendingBits do
            .result.add(cast(u8, ((.pending << (8 - .pendingBits)) & 255)))
    }
}

// Encode one TIFF strip with MSB-first, early-transition LZW codes.
func packLzw(result: *Array'u8, src: const [*] u8, count: u64)
{
    var writer: LzwBitWriter
    writer.result      = result
    writer.pending     = 0
    writer.pendingBits = 0
    writer.write(LZW_CLEAR_CODE, 9)

    if not count
    {
        writer.write(LZW_EOI_CODE, 9)
        writer.finish()
        return
    }

    // A 12-bit prefix plus the next byte and the 12-bit code fit in one slot.
    // The dictionary never holds more than 3838 entries at a time.
    const Capacity = 8192
    var dictionary: [Capacity] u32
    let slots = cast([*] u32, &dictionary[0])

    var width    = 9'u32
    var nextCode = LZW_FIRST_CODE
    var prefix   = cast(u32, src[0])

    for i in count - 1
    {
        let value = cast(u32, src[i + 1])
        let key   = (prefix << 8) | value
        var slot  = (key * #wrap 0x9E37_79B1'u32) >> 19
        var entry = slots[slot]
        while entry and entry >> 12 != key
        {
            slot  = (slot + 1) & (Capacity - 1)
            entry = slots[slot]
        }

        if entry
        {
            prefix = entry & LZW_MAX_CODE
            continue
        }

        writer.write(prefix, width)

        if nextCode <= LZW_MAX_CODE
        {
            slots[slot] = (key << 12) | nextCode
            nextCode    += 1

            if width < 12 and nextCode > (1'u32 << width) - 1 do
                width += 1
        }
        else
        {
            writer.write(LZW_CLEAR_CODE, width)
            Memory.clear(slots, Capacity * #sizeof(u32))
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
        while offset - samples >= 16
        {
            offset -= 16
            let current  = Math.Simd.load(row + offset)
            let previous = Math.Simd.load(row + offset - samples)
            Math.Simd.store(row + offset, current - previous)
        }

        while offset > samples
        {
            offset      -= 1
            row[offset] -= #wrap row[offset - samples]
        }
    }
}
