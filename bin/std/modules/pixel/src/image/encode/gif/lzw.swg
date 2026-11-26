//! Format: Graphics Interchange Format (GIF89a) encoder component.
//! Supported: One indexed frame with generated palette, LZW compression, and binary transparency.
//! Not supported: Interlaced output and partial alpha; animations are written by [[Gif.AnimationWriter]].
//! Role: This file owns GIF LZW dictionary encoding.
//
#global namespace Gif

using Swag, Core, Core.Errors

private
{
    struct BitWriter
    {
        bytes:    Array'u8
        curBits:  u64
        bitCount: u32
    }

    struct LzwEncoder
    {
        bits:        BitWriter
        minCodeSize: u8
        codeSize:    u8
        clearCode:   u16
        endCode:     u16
    }
}

impl BitWriter
{
    mtd write(code: u16, codeSize: u8)
    {
        .curBits  |= cast(u64, code) << .bitCount
        .bitCount += codeSize

        if .bitCount >= 32
        {
            cast([*] u32, .bytes.emplaceAddress(4))[0] = cast #wrap(u32, .curBits)
            .curBits  >>= 32
            .bitCount -= 32
        }
    }

    mtd flush()
    {
        let count  = (.bitCount + 7) >> 3
        let target = .bytes.emplaceAddress(count)
        for i in count do
            target[i] = cast #wrap(u8, .curBits >> (i * 8))
        .curBits  = 0
        .bitCount = 0
    }
}

impl LzwEncoder
{
    mtd resetDictionary()
    {
        .codeSize  = .minCodeSize + 1
        .clearCode = cast(u16, (1 << .minCodeSize))
        .endCode   = .clearCode + 1
    }

    mtd init(minCodeSize: u8)
    {
        .minCodeSize = minCodeSize
        .resetDictionary()
    }

    mtd writeCode(code: u16)
    {
        .bits.write(code, .codeSize)

        if code == .clearCode
        {
            .resetDictionary()
            return
        }
    }
}

impl Encoder
{
    // Largest code of the GIF dictionary, whose codes are at most 12 bits wide.
    const MaxLzwCode = 4095'u32

    // Compresses palette indexes into GIF LZW codes.
    //
    // The dictionary maps a known string, as its code, followed by one more index to the code of
    // the longer string. It is reset with a clear code once every 12-bit code is taken.
    func lzwCompress(indexes: const [..] u8, minCodeSize: u8)->Array'u8
    {
        var enc: LzwEncoder
        enc.init(minCodeSize)
        if indexes.count == 0
        {
            enc.writeCode(enc.clearCode)
            enc.writeCode(enc.endCode)
            enc.bits.flush()
            return enc.bits.bytes
        }

        // Pack the (prefix, index) key and its 12-bit code in a single table entry.
        // A zero entry is empty. Each dictionary cycle stays below half capacity.
        let capacity = Math.roundUpToPowerOf2(cast(u32, Math.min(indexes.count, 4096'u64)) * 2)
        let shift    = Math.leadingZeros(capacity - 1)
        var table: Array'u32
        table.resize(capacity)
        let dictionary = table.storage()
        var nextCode   = cast(u32, enc.endCode) + 1

        enc.writeCode(enc.clearCode)
        var prefix = cast(u32, indexes[0])
        for i in 1 until indexes.count
        {
            let index = indexes[i]
            let key   = (prefix << 8 | index) << 12
            var slot  = ((key >> 12) * #wrap 0x9E3779B9'u32) >> shift
            var entry = dictionary[slot]
            while entry and (entry & ~MaxLzwCode) != key
            {
                slot  = (slot + 1) & (capacity - 1)
                entry = dictionary[slot]
            }

            if entry
            {
                prefix = entry & MaxLzwCode
                continue
            }

            enc.writeCode(cast(u16, prefix))
            if nextCode < MaxLzwCode
            {
                dictionary[slot] = key | nextCode
                nextCode         += 1
                if nextCode > (1'u32 << enc.codeSize) and enc.codeSize < 12 do
                    enc.codeSize += 1
            }
            else
            {
                enc.writeCode(enc.clearCode)
                Memory.clear(dictionary, cast(u64, capacity) * #sizeof(u32))
                nextCode = cast(u32, enc.endCode) + 1
            }

            prefix = index
        }

        enc.writeCode(cast(u16, prefix))
        enc.writeCode(enc.endCode)
        enc.bits.flush()
        return enc.bits.bytes
    }

    func writeSubBlocks(result: *ConcatBuffer, bytes: const [..] u8)
    {
        let blocks      = (bytes.count + 254) / 255
        var destination = result.reserveInPlace(bytes.count + blocks + 1)
        var offset      = 0'u64
        while offset < bytes.count
        {
            let blockSize = Math.min(255'u64, bytes.count - offset)
            destination[0] = cast(u8, blockSize)
            Memory.copy(destination + 1, bytes.buffer + offset, blockSize)
            destination += 1 + blockSize
            offset      += blockSize
        }

        destination[0] = 0
    }
}
