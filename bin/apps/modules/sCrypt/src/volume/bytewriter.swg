using Core

struct ByteWriter
{
    buffer: Array'u8
    cursor: u64
    limit:  u64
}

impl ByteWriter
{
    func create(capacity: u64)->ByteWriter
    {
        var result: retval
        result.limit = capacity
        result.buffer.reserve(Math.min(capacity, 64 * 1024))
        return result
    }

    mtd require(count: u64) fail
    {
        if .cursor > .limit or count > .limit - .cursor do
            failWith("The encrypted metadata area is full.", .DiskFull)
        let required = .cursor + count
        if required > .buffer.count do
            .buffer.resize(required)
    }

    mtd bytes(value: const [..] u8) fail
    {
        .require(@countof(value))
        @memcpy(.buffer.buffer + .cursor, @dataof(value), @countof(value))
        .cursor += @countof(value)
    }

    mtd writeU32(value: u32) fail
    {
        .require(4)
        Crypto.store32(notnull .buffer.buffer + .cursor, value)
        .cursor += 4
    }

    mtd writeU64(value: u64) fail
    {
        .writeU32(Crypto.low32(value))
        .writeU32(Crypto.low32(value >> 32))
    }

    mtd writeString(value: string) fail
    {
        if @countof(value) > Swag.U32.Max do
            failWith("A metadata string is too large.", .InvalidInput)
        .writeU32(cast(u32) @countof(value))
        .bytes(@mkslice(@dataof(value), @countof(value)))
    }
}
