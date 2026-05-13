#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
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
    let input: [3] u8 = [0xCA, 0x74, 0x05]
    let start = cast(const [*] u8) @dataof(input)

    var stream: Compress.BitStream
    stream.init(input)

    @assert(stream.size() == 3)
    @assert(stream.startPtr() == start)
    @assert(stream.curPtr() == start)

    @assert(stream.peekBits(4) == 0xA)
    @assert(stream.readBits(4) == 0xA)
    @assert(stream.peekBitsNoRefill(4) == 0xC)
    @assert(stream.readBitsNoRefill(4) == 0xC)
    @assert(stream.readBits(8) == 0x74)
    @assert(stream.readBits(8) == 0x05)
    @assert(stream.curPtr() == start + 3)
    @assert(stream.eof)
}

#test
{
    let input: [2] u8 = [0b11010110, 0xAB]

    var stream: Compress.BitStream
    stream.init(input)

    @assert(stream.readBits(3) == 6)
    stream.discardToNextByte()
    @assert(stream.readBits(8) == 0xAB)
}

#test
{
    let input: [3] u8 = [0xAA, 0xBB, 0xCC]
    let start = cast(const [*] u8) @dataof(input)

    var stream: Compress.BitStream
    stream.init(input)
    stream.refill(8)

    @assert(stream.readBitsNoRefill(8) == 0xAA)
    stream.revert()

    @assert(stream.curPtr() == start + 1)
    @assert(stream.readBits(8) == 0xBB)
    @assert(stream.readBits(8) == 0xCC)
}

#test
{
    let input: [5] u8 = [0x10, 0x20, 0x30, 0x40, 0x50]

    var stream: Compress.BitStream
    stream.init(input)

    let expected: [3] u8 = [0x10, 0x20, 0x30]
    var bytes: [3] u8
    stream.peekBytes(3, &bytes[0])

    @assert(assertBytes(bytes, expected))
    @assert(stream.readBits(8) == 0x40)
    @assert(stream.readBits(8) == 0x50)
}

#test
{
    let input: [4] u8 = [0x10, 0x20, 0x30, 0x40]

    var littleEndianView: Compress.BitStream
    littleEndianView.init(input)
    let expectedDirect: [4] u8 = [0x10, 0x20, 0x30, 0x40]
    var direct: [4] u8
    littleEndianView.peek32(&direct[0])
    @assert(assertBytes(direct, expectedDirect))

    var bigEndianView: Compress.BitStream
    bigEndianView.init(input)
    var converted: [4] u8
    bigEndianView.peek32Be(&converted[0])

    #if BIG_ENDIAN do
        @assert(assertBytes(converted, expectedDirect))
    #else do
        @assert(assertBytes(converted, [0x40, 0x30, 0x20, 0x10]))
}
