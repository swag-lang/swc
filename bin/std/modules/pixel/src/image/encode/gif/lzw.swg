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
        .curBits  |= cast(u32) code << .bitCount
        .bitCount += codeSize

        while .bitCount >= 8
        {
            .bytes.add(cast(u8) (.curBits & 0xFF))
            .curBits  >>= 8
            .bitCount -= 8
        }
    }

    mtd flush()
    {
        if .bitCount
        {
            .bytes.add(cast(u8) (.curBits & 0xFF))
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
        .clearCode = cast(u16) (1 << .minCodeSize)
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
    func lzwCompress(indexes: const [..] u8, minCodeSize: u8)->Array'u8
    {
        var enc: LzwEncoder
        enc.init(minCodeSize)
        enc.writeCode(enc.clearCode)

        for i in @countof(indexes)
        {
            if i do
                enc.writeCode(enc.clearCode)
            enc.writeCode(cast(u16) indexes[i])
        }

        enc.writeCode(enc.endCode)
        enc.bits.flush()
        return enc.bits.bytes
    }

    func writeSubBlocks(result: *ConcatBuffer, bytes: const [..] u8)
    {
        var offset = 0'u64
        while offset < @countof(bytes)
        {
            let blockSize = Math.min(255'u64, @countof(bytes) - offset)
            result.addNative(cast(u8) blockSize)
            result.addBytes(@mkslice(@dataof(bytes) + offset, blockSize))
            offset += blockSize
        }

        result.addNative(0'u8)
    }
}
