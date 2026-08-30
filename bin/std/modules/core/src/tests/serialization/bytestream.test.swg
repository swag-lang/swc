#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertBytes(actual: const [..] u8, expected: const [..] u8)->bool
{
    if actual.count != expected.count do
        return false

    for actual.count
    {
        if actual[Swag.index] != expected[Swag.index] do
            return false
    }

    return true
}

#test
{
    let input: [4] u8 = [0x10, 0x20, 0x30, 0x40]

    var stream = ByteStream.openRead(input)
    Swag.assert(stream.length() == 4)
    Swag.assert(stream.position() == 0)
    Swag.assert(!stream.isEof())
    Swag.assert(stream.peekU8() == 0x10)
    Swag.assert(stream.readU8() == 0x10)
    Swag.assert(stream.position() == 1)
    Swag.assert(stream.peekU8() == 0x20)
    Swag.assert(assertBytes(stream.remainingBytes()!, [0x20, 0x30, 0x40]))
    Swag.assert(stream.remainingString() == "\x20\x30\x40")

    stream.advance(2)
    Swag.assert(stream.position() == 3)
    Swag.assert(!stream.isEof())
    Swag.assert(stream.readU8() == 0x40)
    Swag.assert(stream.position() == 4)
    Swag.assert(stream.isEof())
    Swag.assert(stream.peekU8() == 0)
}

#test
{
    var buffer: Array'u8
    var stream = ByteStream.openWrite(&buffer)
    stream.writeBytes([0xAB, 0xCD, 0xEF])

    Swag.assert(stream.length() == 3)
    Swag.assert(stream.position() == 3)
    Swag.assert(assertBytes(buffer.toSlice(), [0xAB, 0xCD, 0xEF]))

    stream.setPosition(0)
    Swag.assert(!stream.isEof())
    Swag.assert(stream.peekU8() == 0xAB)
    Swag.assert(stream.readU8() == 0xAB)
    Swag.assert(assertBytes(stream.remainingBytes()!, [0xCD, 0xEF]))
}

// LEB128 varints round-trip across the byte widths, and a truncated or over-long
// encoding is refused.
#test
{
    var buffer: Array'u8
    var writer          = ByteStream.openWrite(&buffer)
    let values: [7] u64 = [0, 1, 127, 128, 300, 0xFFFFFFFF, Swag.U64.Max]
    for v in values do
        writer.writeVarint(v)

    var reader = ByteStream.openRead(buffer.toSlice())
    for v in values do
        Swag.assert((expect reader.readVarint()) == v)
    Swag.assert(reader.position() == buffer.count)

    // A single-byte value encodes as itself.
    var small: Array'u8
    var sw = ByteStream.openWrite(&small)
    sw.writeVarint(0x45)
    Swag.assert(assertBytes(small.toSlice(), [0x45]))

    // Truncated in the middle of a continuation.
    let cut: [1] u8 = [0x80]
    var truncated   = ByteStream.openRead(cut)
    discard catch truncated.readVarint() as errcut
    Swag.assert(errcut != null)

    // More than 64 bits of payload is refused.
    let long: [11] u8 = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01]
    var overlong      = ByteStream.openRead(long)
    discard catch overlong.readVarint() as errlong
    Swag.assert(errlong != null)
}

#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    writer.writeLittleEndian(0x1234'u16)
    writer.writeLittleEndian(0xAABBCCDD'u32)
    writer.writeBigEndian(0xAABBCCDD'u32)

    // The bytes must be the declared order, not the host's.
    Swag.assert(assertBytes(buffer.toSlice(), [0x34, 0x12, 0xDD, 0xCC, 0xBB, 0xAA, 0xAA, 0xBB, 0xCC, 0xDD]))

    var reader = ByteStream.openRead(buffer.toSlice())
    Swag.assert(expect reader.readLittleEndian'u16() == 0x1234)
    Swag.assert(expect reader.readLittleEndian'u32() == 0xAABBCCDD)
    Swag.assert(expect reader.readBigEndian'u32() == 0xAABBCCDD)
    Swag.assert(reader.position() == 10)
}

#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    writer.writeSizedString("sample")
    writer.writeSizedString("")

    // A 32-bit little-endian byte count precedes the bytes.
    Swag.assert(buffer.count == 4 + 6 + 4)
    Swag.assert(assertBytes(buffer[0 until 4], [6, 0, 0, 0]))

    var reader = ByteStream.openRead(buffer.toSlice())
    Swag.assert(expect reader.readSizedString() == "sample")
    Swag.assert((expect reader.readSizedString()).isEmpty())
    Swag.assert(reader.isEof() or reader.position() == buffer.count)
}

// A stored count beyond the cap must fail instead of reserving it.
#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    writer.writeSizedString("too long")

    var reader = ByteStream.openRead(buffer.toSlice())
    let value  = catch reader.readSizedString(4) as err
    discard value
    Swag.assert(err != null)
}

// A truncated payload must fail rather than read past the end.
#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    writer.writeSizedString("sample")
    buffer.resize(buffer.count - 2)

    var reader = ByteStream.openRead(buffer.toSlice())
    let value  = catch reader.readSizedString() as err
    discard value
    Swag.assert(err != null)
}
