#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertBytes(actual: const [..] u8, expected: const [..] u8)->bool
{
    if actual.count != expected.count do
        return false

    for index in actual.count
    {
        if actual[index] != expected[index] do
            return false
    }

    return true
}

#test
{
    let input: [3] u8 = [0xCA, 0x74, 0x05]
    let start         = cast(const [*] u8) input.buffer

    var stream: Compress.BitStream
    stream.reset(input)

    Swag.assert(stream.size() == 3)
    Swag.assert(stream.currentPointer() == start)
    Swag.assert(stream.bytePosition() == 0)

    Swag.assert(stream.peekBits(4) == 0xA)
    Swag.assert(stream.readBits(4) == 0xA)
    Swag.assert(stream.peekBitsUnchecked(4) == 0xC)
    Swag.assert(stream.readBitsUnchecked(4) == 0xC)
    Swag.assert(stream.readBits(8) == 0x74)
    Swag.assert(stream.readBits(8) == 0x05)
    Swag.assert(stream.currentPointer() == start + 3)
    Swag.assert(stream.isEof())
}

#test
{
    // Cross-check varying-width reads (non-byte-aligned) against a manual LSB-first
    // extraction. 64 bytes forces many bulk-refill fast paths at assorted numBits.
    var input: [64] u8
    for i in 64 do
        input[i] = cast #bit (u8) (i * 173 + 41)

    var stream: Compress.BitStream
    stream.reset(input)

    let widths: [8] u8 = [1, 3, 5, 7, 9, 11, 13, 2]
    var bitPos         = 0'u64
    var wi             = 0
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
        Swag.assert(got == exp)
        bitPos += w
    }
}

#test
{
    let input: [2] u8 = [0b11010110, 0xAB]

    var stream: Compress.BitStream
    stream.reset(input)

    Swag.assert(stream.readBits(3) == 6)
    stream.discardToNextByte()
    Swag.assert(stream.readBits(8) == 0xAB)
}

#test
{
    let input: [3] u8 = [0xAA, 0xBB, 0xCC]
    let start         = cast(const [*] u8) input.buffer

    var stream: Compress.BitStream
    stream.reset(input)
    stream.refill(8)

    Swag.assert(stream.readBitsUnchecked(8) == 0xAA)
    stream.revert()

    Swag.assert(stream.currentPointer() == start + 1)
    Swag.assert(stream.readBits(8) == 0xBB)
    Swag.assert(stream.readBits(8) == 0xCC)
}

#test
{
    let input: [5] u8 = [0x10, 0x20, 0x30, 0x40, 0x50]

    var stream: Compress.BitStream
    stream.reset(input)

    let expected: [3] u8 = [0x10, 0x20, 0x30]
    var bytes:    [3] u8
    stream.peekBytes(3, &bytes[0])

    Swag.assert(assertBytes(bytes, expected))
    Swag.assert(stream.readBits(8) == 0x40)
    Swag.assert(stream.readBits(8) == 0x50)
}

#test
{
    let input: [4] u8 = [0x10, 0x20, 0x30, 0x40]

    var littleEndianView: Compress.BitStream
    littleEndianView.reset(input)
    let expectedDirect: [4] u8 = [0x10, 0x20, 0x30, 0x40]
    var direct:         [4] u8
    littleEndianView.peek32(&direct[0])
    Swag.assert(assertBytes(direct, expectedDirect))

    var bigEndianView: Compress.BitStream
    bigEndianView.reset(input)
    var converted: [4] u8
    bigEndianView.peek32Be(&converted[0])

    #static if BIG_ENDIAN do
        Swag.assert(assertBytes(converted, expectedDirect))
    else do
        Swag.assert(assertBytes(converted, [0x40, 0x30, 0x20, 0x10]))
}
