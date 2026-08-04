using Core

struct ByteReader
{
    data:   const [..] u8
    cursor: u64
    valid = true
}

impl ByteReader
{
    mtd has(count: u64)->bool => .valid and .cursor <= @countof(.data) and count <= @countof(.data) - .cursor

    mtd readU32()->u32
    {
        if !.has(4)
        {
            .valid = false
            return 0
        }

        let result = Crypto.load32(@dataof(.data) + .cursor)
        .cursor += 4
        return result
    }

    mtd readU64()->u64
    {
        let low  = .readU32()
        let high = .readU32()
        return low | (cast(u64) high << 32)
    }

    mtd readString(maxLength = 1'u64 * 1024 * 1024)->String
    {
        let length = .readU32()
        if length > maxLength or !.has(length)
        {
            .valid = false
            return {}
        }

        var result: retval
        result  = @mkstring(@dataof(.data) + .cursor, length)
        .cursor += length
        return result
    }

    mtd matches(value: const [..] u8)->bool
    {
        if !.has(@countof(value)) do
            return false
        let result = @memcmp(@dataof(.data) + .cursor, @dataof(value), @countof(value)) == 0
        .cursor += @countof(value)
        return result
    }
}
