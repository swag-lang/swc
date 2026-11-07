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
        curBits:  u32
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
        .curBits  |= cast(u32, code) << .bitCount
        .bitCount += codeSize

        while .bitCount >= 8
        {
            .bytes.add(cast(u8, (.curBits & 0xFF)))
            .curBits  >>= 8
            .bitCount -= 8
        }
    }

    mtd flush()
    {
        if .bitCount
        {
            .bytes.add(cast(u8, (.curBits & 0xFF)))
            .curBits  = 0
            .bitCount = 0
        }
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

        // One slot per (code, index) pair; zero means the longer string is not known yet.
        var dictionary: Array'u16
        dictionary.resize((MaxLzwCode + 1) * 256)
        var nextCode = cast(u32, enc.endCode) + 1

        enc.writeCode(enc.clearCode)
        var prefix = cast(u32, indexes[0])
        for i in 1 until indexes.count
        {
            let index = indexes[i]
            let slot  = prefix * 256 + index
            let known = dictionary[slot]
            if known
            {
                prefix = known
                continue
            }

            enc.writeCode(cast(u16, prefix))
            if nextCode < MaxLzwCode
            {
                dictionary[slot] = cast(u16, nextCode)
                nextCode         += 1
                if nextCode > (1'u32 << enc.codeSize) and enc.codeSize < 12 do
                    enc.codeSize += 1
            }
            else
            {
                enc.writeCode(enc.clearCode)
                Memory.clear(dictionary.storage(), dictionary.count * #sizeof(u16))
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
        var offset = 0'u64
        while offset < bytes.count
        {
            let blockSize = Math.min(255'u64, bytes.count - offset)
            result.addNative(cast(u8, blockSize))
            result.addBytes(Swag.makeSlice(bytes.buffer + offset, blockSize))
            offset += blockSize
        }

        result.addNative(0'u8)
    }
}
