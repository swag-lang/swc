#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertUtf16(values: Array'u16, expected: const [..] u16)->bool
{
    if values.count != expected.count do
        return false

    for i in values.count
    {
        if values[i] != expected[i] do
            return false
    }

    return true
}

func scalarUtf16FromUtf8(dest: [..] u16, src: const [..] u8)->u64
{
    var count      = 0'u64
    var srcPtr     = src.buffer
    var destPtr    = dest.buffer
    var srcLength  = src.count
    var destLength = dest.count
    while srcLength
    {
        let {c, eat} = Utf8.decodeRune(Swag.makeSlice(srcPtr, srcLength))
        let eatDest  = Utf16.encodeRune(Swag.makeSlice(destPtr, destLength), c)
        srcPtr     += eat
        srcLength  -= eat
        destPtr    += eatDest
        destLength -= eatDest
        count      += eatDest
    }

    return count
}

#test
{
    var buffer: [2] u16

    Swag.assert(Utf16.encodeRune(buffer, 'A'rune) == 1)
    Swag.assert(buffer[0] == 0x0041)

    Swag.assert(Utf16.encodeRune(buffer, '\u20AC'rune) == 1)
    Swag.assert(buffer[0] == 0x20AC)

    Swag.assert(Utf16.encodeRune(buffer, '\U0001F642'rune) == 2)
    Swag.assert(buffer[0] == 0xD83D)
    Swag.assert(buffer[1] == 0xDE42)

    Swag.assert(Utf16.encodeRune(buffer, 0xD800'rune) == 1)
    Swag.assert(buffer[0] == 0xFFFD)
}

#test
{
    let values: [4] u16 = [0x0041, 0x20AC, 0xD83D, 0xDE42]

    var {c, eat} = Utf16.decodeRune(values)
    Swag.assert(c == 'A'rune)
    Swag.assert(eat == 1)

    {c, eat} = Utf16.decodeRune(values[1 until values.count])
    Swag.assert(c == '\u20AC'rune)
    Swag.assert(eat == 1)

    {c, eat} = Utf16.decodeRune(values[2 until values.count])
    Swag.assert(c == '\U0001F642'rune)
    Swag.assert(eat == 2)

    let loneHigh: [1] u16 = [0xD83D]
    {c, eat} = Utf16.decodeRune(loneHigh)
    Swag.assert(c == Utf16.RuneError)
    Swag.assert(eat == 1)

    let loneLow: [1] u16 = [0xDE42]
    {c, eat} = Utf16.decodeRune(loneLow)
    Swag.assert(c == Utf16.RuneError)
    Swag.assert(eat == 1)

    {c, eat} = Utf16.decodeRune(Swag.makeSlice(values.buffer, 0))
    Swag.assert(c == Utf16.RuneError)
    Swag.assert(eat == 0)
}

#test
{
    let text              = "A\u20AC\U0001F642"
    let expected: [4] u16 = [0x0041, 0x20AC, 0xD83D, 0xDE42]

    var dest: [8] u16
    let count = Utf16.fromUtf8(dest, text)
    Swag.assert(count == 4)
    for i in count do
        Swag.assert(dest[i] == expected[i])

    let result = Utf16.fromUtf8(text)
    Swag.assert(assertUtf16(result, expected))
}

#test
{
    let runes:    [3] rune = ['A'rune, '\u20AC'rune, '\U0001F642'rune]
    let expected: [4] u16  = [0x0041, 0x20AC, 0xD83D, 0xDE42]

    var dest: [8] u16
    let count = Utf16.fromUnicode(dest, runes)
    Swag.assert(count == 4)
    for i in count do
        Swag.assert(dest[i] == expected[i])

    let result = Utf16.fromUnicode(runes)
    Swag.assert(assertUtf16(result, expected))
}

#test
{
    let expected: [6] u16 = [0x0043, 0x0061, 0x0066, 0x00E9, 0xD83D, 0xDE42]
    let zero              = Utf16.toZeroTerminated("Caf\u00E9\U0001F642")

    Swag.assert(zero.count == 7)
    for i in expected.count do
        Swag.assert(zero[i] == expected[i])
    Swag.assert(zero[6] == 0)
    Swag.assert(Utf16.lengthZeroTerminated(zero.buffer) == 6)
    Swag.assert(Utf16.lengthUntilZero(zero.toSlice()) == 6)
}

// The bounded scan must find every lane and tail position around its eight-unit vector
// boundary, and report the slice extent when no terminator is present.
#test
{
    var values: [25] u16
    for i in values.count do
        values[i] = cast(u16) (i + 1)

    for count in values.count + 1
    {
        let bounded = Swag.makeSlice(values.buffer, count)
        Swag.assert(Utf16.lengthUntilZero(bounded) == count)
    }

    for terminator in values.count
    {
        values[terminator] = 0
        Swag.assert(Utf16.lengthUntilZero(values) == terminator)
        values[terminator] = cast(u16) (terminator + 1)
    }
}

// Every length around the vector boundary, and every position where a non-ASCII sequence can
// interrupt an ASCII run, must stay identical to the scalar conversion.
#test
{
    var source:   [80] u8
    var actual:   [160] u16
    var expected: [160] u16
    for index in source.count do
        source[index] = cast(u8) ('a' + index % 26)

    for idx in 66
    {
        for index in actual.count
        {
            actual[index]   = 0xBEEF
            expected[index] = 0xBEEF
        }

        let src           = Swag.makeSlice(source.buffer, idx)
        let actualCount   = Utf16.fromUtf8(actual, src)
        let expectedCount = scalarUtf16FromUtf8(expected, src)
        Swag.assert(actualCount == expectedCount)
        Swag.assert(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)
    }

    for index in 48
    {
        for idx in source.count do
            source[idx] = cast(u8) ('a' + idx % 26)
        source[index]     = 0xC3
        source[index + 1] = 0xA9
        for idx in actual.count
        {
            actual[idx]   = 0xBEEF
            expected[idx] = 0xBEEF
        }

        let src           = Swag.makeSlice(source.buffer, 64)
        let actualCount   = Utf16.fromUtf8(actual, src)
        let expectedCount = scalarUtf16FromUtf8(expected, src)
        Swag.assert(actualCount == expectedCount)
        Swag.assert(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)
    }
}
