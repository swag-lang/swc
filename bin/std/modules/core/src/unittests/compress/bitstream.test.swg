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
    // Cross-check varying-width reads (non-byte-aligned) against a manual LSB-first
    // extraction. 64 bytes forces many bulk-refill fast paths at assorted numBits.
    var input: [64] u8
    for i in 64 do
        input[i] = cast #bit (u8) (i * 173 + 41)

    var stream: Compress.BitStream
    stream.init(input)

    let widths: [8] u8 = [1, 3, 5, 7, 9, 11, 13, 2]
    var bitPos = 0'u64
    var wi     = 0
    while bitPos + 16 <= 64 * 8
    {
        let w = widths[wi % 8]
        wi += 1
        let got = stream.readBits(w)

        var exp = 0'u32
        for b in w
        {
            let byteIdx = (bitPos + b) >> 3
            let bitIdx  = (bitPos + b) & 7
            let bit     = (input[byteIdx] >> bitIdx) & 1
            exp |= cast(u32) bit << b
        }

        if got != exp do
            Console.println("BITSTREAM DIVERGE bitPos=", bitPos, " w=", w, " got=", got, " exp=", exp)
        @assert(got == exp)
        bitPos += w
    }
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
    var bytes:    [3] u8
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
    var direct:         [4] u8
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
