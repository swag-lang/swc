#global #if #command == Swag.CompilerCommand.Test
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
    @assert(stream.getSeek() == 0)
    @assert(!stream.isEof())
    @assert(stream.peekU8() == 0x10)
    @assert(stream.readU8() == 0x10)
    @assert(stream.getSeek() == 1)
    @assert(stream.peekU8() == 0x20)
    @assert(assertBytes(assume stream.remainReadToSlice(), [0x20, 0x30, 0x40]))
    @assert(stream.remainReadToString() == "\x20\x30\x40")

    stream.moveSeek(2)
    @assert(stream.getSeek() == 3)
    @assert(!stream.isEof())
    @assert(stream.readU8() == 0x40)
    @assert(stream.getSeek() == 4)
    @assert(stream.isEof())
    @assert(stream.peekU8() == 0)
}

#test
{
    var buffer: Array'u8
    var stream = ByteStream.openWrite(&buffer)
    stream.writeBytes([0xAB, 0xCD, 0xEF])

    @assert(stream.length() == 3)
    @assert(stream.getSeek() == 3)
    @assert(assertBytes(buffer.toSlice(), [0xAB, 0xCD, 0xEF]))

    stream.setSeek(0)
    @assert(!stream.isEof())
    @assert(stream.peekU8() == 0xAB)
    @assert(stream.readU8() == 0xAB)
    @assert(assertBytes(assume stream.remainReadToSlice(), [0xCD, 0xEF]))
}
