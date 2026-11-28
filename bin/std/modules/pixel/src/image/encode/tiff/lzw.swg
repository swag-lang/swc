//! Format: Tagged Image File Format (TIFF) encoder component.
//! Supported: Little-endian baseline 8-bit grayscale, RGB, and RGBA in one strip using no compression, PackBits, or LZW.
//! Not supported: Big-endian, planar, tiled, multi-page, JPEG/Deflate, and non-8-bit output.
//! Role: This file owns TIFF LZW dictionary encoding.
//
#global namespace Tiff

using Core

struct LzwBitWriter
{
    result:      *Array!{u8}
    pending:     u64
    pendingBits: u32
}

impl LzwBitWriter
{
    #[Swag.Inline]
    mtd write(code, width: u32)
    {
        let total = .pendingBits + width
        if total < 64
        {
            .pending     = (.pending << width) | code
            .pendingBits = total
            return
        }

        // Write a full big-endian word and carry the remaining low bits.
        let extra = total - 64
        let word  = (.pending << (width - extra)) | (code >> extra)
        let count = .result.count
        let end   = count + 8
        if end > .result.capacity
        {
            .result.grow(end)
        }

        cast(*u64, (.result.storage() + count))[] = Math.byteSwap(word)
        .result.count = end
        .pending      = code
        .pendingBits  = extra
    }

    mtd finish()
    {
        let bytes = (.pendingBits + 7) >> 3
        if not bytes
        {
            return
        }

        let word  = .pending << (bytes * 8 - .pendingBits)
        let count = .result.count
        let end   = count + bytes
        if end > .result.capacity
        {
            .result.grow(end)
        }

        let dst = .result.storage() + count
        for i in bytes
        {
            dst[i] = cast(u8, ((word >> ((bytes - i - 1) * 8)) & 255))
        }

        .result.count = end
    }
}

// Encode one TIFF strip with MSB-first, early-transition LZW codes.
private func(DIRECT_KEYS: bool) packLzwStrip(result: *Array!{u8}, src: const [*] u8, count: u64)
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

    // A one-byte prefix and its next sample form a directly addressable key.
    const ShortKeys     = 1 << 16
    const MaxGeneration = 1 << 20
    var shortWords: Array!{u32}
    #static if DIRECT_KEYS
    {
        shortWords.resize(ShortKeys)
    }

    let pairs      = shortWords.storage()
    var generation = 1_u32

    var width    = 9_u32
    var nextCode = LZW_FIRST_CODE
    var prefix   = cast(u32, src[0])

    for i in count - 1
    {
        let value         = cast(u32, src[i + 1])
        let key           = (prefix << 8) | value
        let hasDirectSlot = DIRECT_KEYS and key < ShortKeys
        var slot: u32
        if hasDirectSlot
        {
            let pair = pairs[key]
            if (pair >> 12) == generation
            {
                prefix = pair & LZW_MAX_CODE
                continue
            }
        }
        else
        {
            slot = (key * #wrap 0x9E37_79B1_u32) >> 19
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
        }

        writer.write(prefix, width)

        if nextCode <= LZW_MAX_CODE
        {
            if hasDirectSlot
            {
                pairs[key] = (generation << 12) | nextCode
            }
            else
            {
                slots[slot] = (key << 12) | nextCode
            }

            nextCode += 1

            if width < 12 and nextCode > (1_u32 << width) - 1
            {
                width += 1
            }
        }
        else
        {
            writer.write(LZW_CLEAR_CODE, width)
            Memory.clear(slots, Capacity * #sizeof(u32))
            #static if DIRECT_KEYS
            {
                generation += 1
                if generation == MaxGeneration
                {
                    Memory.clear(pairs, ShortKeys * #sizeof(u32))
                    generation = 1
                }
            }

            width    = 9
            nextCode = LZW_FIRST_CODE
        }

        prefix = value
    }

    writer.write(prefix, width)
    writer.write(LZW_EOI_CODE, width)
    writer.finish()
}

// A sparse dictionary is cheaper when sampled bytes form few different pairs.
private func hasVariedPairs(source: const [*] u8, count: u64)->bool
{
    const ProbeBytes  = 128
    const ProbeBlocks = 4
    const TargetPairs = 64
    let step = (count - ProbeBytes) / (ProbeBlocks - 1)
    var buckets:  [4] u64
    var occupied: u32
    for block in ProbeBlocks
    {
        let bytes = source + block * step
        for i in 1 until ProbeBytes
        {
            let pair = (cast(u32, bytes[i - 1]) << 8) | bytes[i]
            let key  = (pair * #wrap 0x9E37_79B1_u32) >> 24
            let bit  = 1_u64 << (key & 63)
            let word = &buckets[key >> 6]
            if not (word[] & bit)
            {
                word[]   |= bit
                occupied += 1
                if occupied == TargetPairs
                {
                    return true
                }
            }
        }
    }

    return false
}

func packLzw(result: *Array!{u8}, src: const [*] u8, count: u64)
{
    // Leave small strips in the compact hash table and sample large inputs once.
    if count >= 64 * 1024 and hasVariedPairs(src, count)
    {
        packLzwStrip!{true}(result, src, count)
    }
    else
    {
        packLzwStrip!{false}(result, src, count)
    }
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
