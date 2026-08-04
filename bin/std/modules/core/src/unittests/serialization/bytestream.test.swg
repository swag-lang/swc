#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertBytes(actual: const [..] u8, expected: const [..] u8)->bool
{
    if @countof(actual) != @countof(expected) do
        return false

    for @countof(actual)
    {
        if actual[@index] != expected[@index] do
            return false
    }

    return true
}

#test
{
    let input: [4] u8 = [0x10, 0x20, 0x30, 0x40]

    var stream = ByteStream.openRead(input)
    @assert(stream.length() == 4)
    @assert(stream.position() == 0)
    @assert(!stream.isEof())
    @assert(stream.peekU8() == 0x10)
    @assert(stream.readU8() == 0x10)
    @assert(stream.position() == 1)
    @assert(stream.peekU8() == 0x20)
    @assert(assertBytes(notnull stream.remainingBytes(), [0x20, 0x30, 0x40]))
    @assert(stream.remainingString() == "\x20\x30\x40")

    stream.advance(2)
    @assert(stream.position() == 3)
    @assert(!stream.isEof())
    @assert(stream.readU8() == 0x40)
    @assert(stream.position() == 4)
    @assert(stream.isEof())
    @assert(stream.peekU8() == 0)
}

#test
{
    var buffer: Array'u8
    var stream = ByteStream.openWrite(&buffer)
    stream.writeBytes([0xAB, 0xCD, 0xEF])

    @assert(stream.length() == 3)
    @assert(stream.position() == 3)
    @assert(assertBytes(buffer.toSlice(), [0xAB, 0xCD, 0xEF]))

    stream.setPosition(0)
    @assert(!stream.isEof())
    @assert(stream.peekU8() == 0xAB)
    @assert(stream.readU8() == 0xAB)
    @assert(assertBytes(notnull stream.remainingBytes(), [0xCD, 0xEF]))
}

#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    writer.writeLittleEndian(0x1234'u16)
    writer.writeLittleEndian(0xAABBCCDD'u32)
    writer.writeBigEndian(0xAABBCCDD'u32)

    // The bytes must be the declared order, not the host's.
    @assert(assertBytes(buffer.toSlice(), [0x34, 0x12, 0xDD, 0xCC, 0xBB, 0xAA, 0xAA, 0xBB, 0xCC, 0xDD]))

    var reader = ByteStream.openRead(buffer.toSlice())
    @assert(expect reader.readLittleEndian'u16() == 0x1234)
    @assert(expect reader.readLittleEndian'u32() == 0xAABBCCDD)
    @assert(expect reader.readBigEndian'u32() == 0xAABBCCDD)
    @assert(reader.position() == 10)
}

#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    writer.writeSizedString("sCrypt")
    writer.writeSizedString("")

    // A 32-bit little-endian byte count precedes the bytes.
    @assert(buffer.count == 4 + 6 + 4)
    @assert(assertBytes(buffer[0 until 4], [6, 0, 0, 0]))

    var reader = ByteStream.openRead(buffer.toSlice())
    @assert(expect reader.readSizedString() == "sCrypt")
    @assert((expect reader.readSizedString()).isEmpty())
    @assert(reader.isEof() or reader.position() == buffer.count)
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
    @assert(err != null)
}

// A truncated payload must fail rather than read past the end.
#test
{
    var buffer: Array'u8
    var writer = ByteStream.openWrite(&buffer)
    writer.writeSizedString("sCrypt")
    buffer.resize(buffer.count - 2)

    var reader = ByteStream.openRead(buffer.toSlice())
    let value  = catch reader.readSizedString() as err
    discard value
    @assert(err != null)
}
