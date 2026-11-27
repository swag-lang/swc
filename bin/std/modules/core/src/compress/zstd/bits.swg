#global namespace Compress.Zstd
#global internal

using Core.Errors

#[Swag.Inline]
func readLe32(source: const [*] u8)->u32 => Math.littleEndianToNative(cast(const [*] u32, source)[0])

#[Swag.Inline]
func readLe64(source: const [*] u8)->u64 => Math.littleEndianToNative(cast(const [*] u64, source)[0])

func readLittle(source: const [*] u8, count: u32)->u64
{
    var value = 0_u64
    for index in count
    {
        value |= cast(u64, source[index]) << (index * 8)
    }

    return value
}

struct ForwardBits
{
    source:   const [..] u8?
    position: u32
}

impl ForwardBits
{
    mtd const peek(width: u32)->u32 fail
    {
        let bytes = unwrap .source
        if width > bytes.count * 8 - .position
        {
            fail InvalidFormatError{"truncated Zstandard entropy table"}
        }

        let shift = .position & 7
        let count = (shift + width + 7) >> 3
        let word  = readLittle(bytes.buffer + (.position >> 3), count)
        return cast(u32, (word >> shift) & ((1_u64 << width) - 1))
    }

    mtd read(width: u32)->u32 fail
    {
        let value = try .peek(width)
        .position += width
        return value
    }
}

struct ReverseBits
{
    source:    const [*] u8?
    remaining: u32
    start:     u32
    word:      u64
}

impl ReverseBits
{
    mtd init(bytes: const [..] u8) fail
    {
        if not bytes.count or not bytes[bytes.count - 1]
        {
            fail InvalidFormatError{"Zstandard bit stream has no end marker"}
        }

        let end = cast(u32, bytes[bytes.count - 1])
        .source    = bytes.buffer
        .remaining = cast(u32, (bytes.count - 1) * 8) + 31 - Math.leadingZeros(end)
        if bytes.count >= 8
        {
            let offset = bytes.count - 8
            .start = cast(u32, offset * 8)
            .word  = readLe64(bytes.buffer + offset)
        }
        else
        {
            .start = 0
            .word  = readLittle(bytes.buffer, cast(u32, bytes.count))
        }
    }

    #[Swag.Inline]
    private mtd window(position: u32)->u64
    {
        if position < .start
        {
            let endByte = (.remaining + 7) >> 3
            let offset  = Math.max(endByte, 8_u32) - 8
            .start = offset << 3
            .word  = readLe64((unwrap .source) + offset)
        }

        return .word >> (position - .start)
    }

    // Huffman lookup may pad the low end of its final index with zeros.
    #[Swag.Inline]
    mtd peek(width: u32)->u32
    {
        let count = Math.min(width, .remaining)
        let value = cast(u32, .window(.remaining - count) & ((1_u64 << count) - 1))
        return value << (width - count)
    }

    #[Swag.Inline]
    mtd read(width: u32)->u32 fail
    {
        return cast(u32, try .readGroup(width))
    }

    // A group of at most 56 bits fits in one word at any bit alignment.
    #[Swag.Inline]
    mtd readGroup(width: u32)->u64 fail
    {
        if width > .remaining
        {
            fail InvalidFormatError{"truncated Zstandard bit stream"}
        }

        let position = .remaining - width
        let word     = .window(position)
        .remaining = position
        return word & ((1_u64 << width) - 1)
    }
}
