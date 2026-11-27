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
        bytes:    Array!{u8}
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
    #[Inline]
    mtd write(code: u16, codeSize: u8)
    {
        .curBits  |= cast(u64, code) << .bitCount
        .bitCount += codeSize

        if .bitCount >= 32
        {
            let end = .bytes.count + 4
            if end > .bytes.capacity
            {
                .bytes.grow(end)
            }

            cast([*] u32, .bytes.storage() + .bytes.count)[0] = cast #wrap(u32, .curBits)
            .bytes.count = end
            .curBits     >>= 32
            .bitCount    -= 32
        }
    }

    mtd flush()
    {
        let count  = (.bitCount + 7) >> 3
        let target = .bytes.emplaceAddress(count)
        for i in count
        {
            target[i] = cast #wrap(u8, .curBits >> (i * 8))
        }

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

    #[Inline]
    mtd growCodeSize(nextCode: u32)
    {
        if nextCode > (1_u32 << .codeSize) and .codeSize < 12
        {
            .codeSize += 1
        }
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
    const MaxLzwCode = 4095_u32

    // When all pixels have the same index, successive dictionary entries describe runs
    // of lengths two, three, and so on. Emit those codes without looking up each pixel.
    func lzwCompressRepeat(index: u8, count: u64, minCodeSize: u8)->Array!{u8}
    {
        var enc: LzwEncoder
        enc.init(minCodeSize)
        enc.writeCode(enc.clearCode)

        let firstCode = cast(u32, enc.endCode) + 1
        var nextCode  = firstCode
        var remaining = count
        var runLength = 1_u32
        while remaining > runLength
        {
            let prefix = runLength == 1 ? cast(u16, index) : cast(u16, firstCode + runLength - 2)
            enc.writeCode(prefix)
            remaining -= runLength
            if nextCode < MaxLzwCode
            {
                nextCode += 1
                enc.growCodeSize(nextCode)
                runLength += 1
            }
            else
            {
                enc.writeCode(enc.clearCode)
                nextCode  = firstCode
                runLength = 1
            }
        }

        let prefix = remaining == 1 ? cast(u16, index) : cast(u16, firstCode + remaining - 2)
        enc.writeCode(prefix)
        enc.writeCode(enc.endCode)
        enc.bits.flush()
        return enc.bits.bytes
    }

    func lzwCompress(indexes: const [..] u8, minCodeSize: u8, singleIndex: bool)->Array!{u8}
    {
        if singleIndex and indexes.count
        {
            return lzwCompressRepeat(indexes[0], indexes.count, minCodeSize)
        }

        return lzwCompressSelected!{false}(indexes, minCodeSize, null)
    }

    func lzwCompressGray(indexes: const [..] u8, literals: const [*] u8)->Array!{u8}
    {
        return lzwCompressSelected!{true}(indexes, 8, literals)
    }

    // Sample a sequence to see whether most indexes have a consistent successor.
    func sampleHasConsistentTransitions(source: const [*] u8)->bool
    {
        var successors: [256] u16
        var different:  u32
        var previous = source[0]
        for i in 1 until 512
        {
            let next     = source[i]
            let expected = cast(u16, next) + 1
            let slot     = &successors[previous]
            if not slot[]
            {
                slot[] = expected
            }
            else if slot[] != expected
            {
                different += 1
                if different >= 64
                {
                    return false
                }
            }

            previous = next
        }

        return true
    }

    func(RemapLiterals: bool) lzwCompressSelected(indexes: const [..] u8, minCodeSize: u8, literals: const [*] u8?)->Array!{u8}
    {
        if indexes.count >= 4096 and
           sampleHasConsistentTransitions(indexes.buffer) and
           sampleHasConsistentTransitions(indexes.buffer + indexes.count / 2) and
           sampleHasConsistentTransitions(indexes.buffer + indexes.count * 3 / 4)
        {
            return lzwCompressStream!{RemapLiterals, true}(indexes, minCodeSize, literals)
        }

        return lzwCompressStream!{RemapLiterals, false}(indexes, minCodeSize, literals)
    }

    // Compresses palette indexes into GIF LZW codes.
    //
    // The dictionary maps a known string, as its code, followed by one more index to the code of
    // the longer string. It is reset with a clear code once every 12-bit code is taken.
    func(RemapLiterals: bool, FirstTransition: bool) lzwCompressStream(indexes: const [..] u8, minCodeSize: u8, literals: const [*] u8?)->Array!{u8}
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
        let capacity = Math.roundUpToPowerOf2(cast(u32, Math.min(indexes.count, 4096_u64)) * 2)
        let shift    = Math.leadingZeros(capacity - 1)
        var table: Array!{u32}
        table.resize(capacity + (FirstTransition ? MaxLzwCode + 1 : 0))
        let dictionary = table.storage()
        var nextCode   = cast(u32, enc.endCode) + 1

        enc.writeCode(enc.clearCode)
        var prefix = cast(u32, indexes[0])
        for i in 1 until indexes.count
        {
            let index  = indexes[i]
            var slot: u32
            var key:  u32
            var search = true
            #static if FirstTransition
            {
                // The first extension of each prefix gets a direct slot. Other extensions
                // still share the compact hash table.
                slot = capacity + prefix
                key  = cast(u32, index) << 12
                let first = dictionary[slot]
                if first
                {
                    if (first & ~MaxLzwCode) == key
                    {
                        prefix = first & MaxLzwCode
                        continue
                    }
                }
                else
                {
                    search = false
                }
            }

            if search
            {
                key  = (prefix << 8 | index) << 12
                slot = ((key >> 12) * #wrap 0x9E3779B9_u32) >> shift
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
            }

            enc.bits.write(RemapLiterals and prefix < 256 ? cast(u16, (unwrap literals)[prefix]) : cast(u16, prefix), enc.codeSize)
            if nextCode < MaxLzwCode
            {
                dictionary[slot] = key | nextCode
                nextCode         += 1
                enc.growCodeSize(nextCode)
            }
            else
            {
                enc.writeCode(enc.clearCode)
                Memory.clear(dictionary, table.count * #sizeof(u32))
                nextCode = cast(u32, enc.endCode) + 1
            }

            prefix = index
        }

        enc.bits.write(RemapLiterals and prefix < 256 ? cast(u16, (unwrap literals)[prefix]) : cast(u16, prefix), enc.codeSize)
        enc.writeCode(enc.endCode)
        enc.bits.flush()
        return enc.bits.bytes
    }

    func writeSubBlocks(result: *ConcatBuffer, bytes: const [..] u8)
    {
        let blocks      = (bytes.count + 254) / 255
        var destination = result.reserveInPlace(bytes.count + blocks + 1)
        var offset      = 0_u64
        while offset < bytes.count
        {
            let blockSize = Math.min(255_u64, bytes.count - offset)
            destination[0] = cast(u8, blockSize)
            Memory.copy(destination + 1, bytes.buffer + offset, blockSize)
            destination += 1 + blockSize
            offset      += blockSize
        }

        destination[0] = 0
    }
}
