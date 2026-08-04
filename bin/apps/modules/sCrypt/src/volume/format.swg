using Core

const BlockSize              = 4096'u64
const BlockRecordSize        = BlockSize + Crypto.NonceSize + Crypto.TagSize
const HeaderSlotSize         = #command == Swag.CompilerCommand.Test ? 256'u64 * 1024 : 8'u64 * 1024 * 1024
const LegacyHeaderPlainSize  = HeaderSlotSize - Crypto.NonceSize - Crypto.TagSize
const HeaderLocatorCheckSize = 12'u64
const HeaderRecordPrefixSize = Crypto.RecordLocatorSize + Crypto.NonceSize
const HeaderPlainSize        = HeaderSlotSize - HeaderRecordPrefixSize - Crypto.TagSize
const HeaderSlotCount        = 2'u64
const DataOffset             = Crypto.SaltSize + HeaderSlotCount * HeaderSlotSize
const MinimumBlocks          = 16'u64
const MinimumSize            = DataOffset + MinimumBlocks * BlockRecordSize
const LegacyFormatVersion    = 1'u32
const FormatVersion          = 2'u32
const HeaderKind             = 1'u32
const DataKind               = 2'u32
const HeaderLocatorKind      = 3'u32

const HeaderMagic: [16] u8 = [
    0x73, 0x43, 0x72, 0x79, 0x70, 0x74, 0x2D, 0x56,
    0x6F, 0x6C, 0x75, 0x6D, 0x65, 0x2D, 0x31, 0x00]

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

struct HeaderCandidate
{
    valid:    bool
    sequence: u64
    plain:    Array'u8
}
