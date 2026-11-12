#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertUtf16(values: Array'u16, expected: const [..] u16)->bool => Slice.equals(values.toSlice(), expected)

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

    Swag.require(Utf16.encodeRune(buffer, 'A'rune) == 1)
    Swag.require(buffer[0] == 0x0041)

    Swag.require(Utf16.encodeRune(buffer, '\u20AC'rune) == 1)
    Swag.require(buffer[0] == 0x20AC)

    Swag.require(Utf16.encodeRune(buffer, '\U0001F642'rune) == 2)
    Swag.require(buffer[0] == 0xD83D)
    Swag.require(buffer[1] == 0xDE42)

    Swag.require(Utf16.encodeRune(buffer, 0xD800'rune) == 1)
    Swag.require(buffer[0] == 0xFFFD)
}

#test
{
    let values: [4] u16 = [0x0041, 0x20AC, 0xD83D, 0xDE42]

    var {c, eat} = Utf16.decodeRune(values)
    Swag.require(c == 'A'rune)
    Swag.require(eat == 1)

    {c, eat} = Utf16.decodeRune(values[1 until values.count])
    Swag.require(c == '\u20AC'rune)
    Swag.require(eat == 1)

    {c, eat} = Utf16.decodeRune(values[2 until values.count])
    Swag.require(c == '\U0001F642'rune)
    Swag.require(eat == 2)

    let loneHigh: [1] u16 = [0xD83D]
    {c, eat} = Utf16.decodeRune(loneHigh)
    Swag.require(c == Utf16.RuneError)
    Swag.require(eat == 1)

    let loneLow: [1] u16 = [0xDE42]
    {c, eat} = Utf16.decodeRune(loneLow)
    Swag.require(c == Utf16.RuneError)
    Swag.require(eat == 1)

    {c, eat} = Utf16.decodeRune(values[until 0])
    Swag.require(c == Utf16.RuneError)
    Swag.require(eat == 0)
}

#test
{
    let text = "A\u20AC\U0001F642"
    let expected: [4] u16 = [0x0041, 0x20AC, 0xD83D, 0xDE42]

    var dest: [8] u16
    let count = Utf16.fromUtf8(dest, text)
    Swag.require(count == 4)
    for i in count do
        Swag.require(dest[i] == expected[i])

    let result = Utf16.fromUtf8(text)
    Swag.require(assertUtf16(result, expected))
}

#test
{
    let runes:    [3] rune = ['A'rune, '\u20AC'rune, '\U0001F642'rune]
    let expected: [4] u16  = [0x0041, 0x20AC, 0xD83D, 0xDE42]

    var dest: [8] u16
    let count = Utf16.fromUnicode(dest, runes)
    Swag.require(count == 4)
    for i in count do
        Swag.require(dest[i] == expected[i])

    let result = Utf16.fromUnicode(runes)
    Swag.require(assertUtf16(result, expected))
}

#test
{
    let expected: [6] u16 = [0x0043, 0x0061, 0x0066, 0x00E9, 0xD83D, 0xDE42]
    let zero = Utf16.toZeroTerminated("Caf\u00E9\U0001F642")

    Swag.require(zero.count == 7)
    for i in expected.count do
        Swag.require(zero[i] == expected[i])
    Swag.require(zero[6] == 0)
    Swag.require(Utf16.lengthZeroTerminated(zero.buffer) == 6)
    Swag.require(Utf16.lengthUntilZero(zero.toSlice()) == 6)
}

// The bounded scan must find every lane and tail position around its eight-unit vector
// boundary, and report the slice extent when no terminator is present.
#test
{
    var values: [25] u16
    for i in values.count do
        values[i] = cast(u16, (i + 1))

    for count in values.count + 1
    {
        let bounded = values[until count]
        Swag.require(Utf16.lengthUntilZero(bounded) == count)
    }

    for terminator in values.count
    {
        values[terminator] = 0
        Swag.require(Utf16.lengthUntilZero(values) == terminator)
        values[terminator] = cast(u16, (terminator + 1))
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
        source[index] = cast(u8, ('a' + index % 26))

    for idx in 66
    {
        for index in actual.count
        {
            actual[index]   = 0xBEEF
            expected[index] = 0xBEEF
        }

        let src           = source[until idx]
        let actualCount   = Utf16.fromUtf8(actual, src)
        let expectedCount = scalarUtf16FromUtf8(expected, src)
        Swag.require(actualCount == expectedCount)
        Swag.require(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)
    }

    for index in 48
    {
        for idx in source.count do
            source[idx] = cast(u8, ('a' + idx % 26))
        source[index]     = 0xC3
        source[index + 1] = 0xA9
        for idx in actual.count
        {
            actual[idx]   = 0xBEEF
            expected[idx] = 0xBEEF
        }

        let src           = source[until 64]
        let actualCount   = Utf16.fromUtf8(actual, src)
        let expectedCount = scalarUtf16FromUtf8(expected, src)
        Swag.require(actualCount == expectedCount)
        Swag.require(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)
    }
}

// Malformed UTF-8 at a SIMD boundary must decode exactly like the scalar rune decoder.
#test
{
    var source:   [64] u8
    var actual:   [128] u16
    var expected: [128] u16
    let prefixes: [3] u64 = [15, 16, 17]

    for prefix in prefixes
    {
        for index in prefix do
            source[index] = cast(u8, (97 + index % 26))
        source[prefix] = 0x80

        for index in actual.count
        {
            actual[index]   = 0xBEEF
            expected[index] = 0xBEEF
        }

        let continuationSrc      = source[until prefix + 1]
        let continuationActual   = Utf16.fromUtf8(actual, continuationSrc)
        let continuationExpected = scalarUtf16FromUtf8(expected, continuationSrc)
        Swag.require(continuationActual == continuationExpected)
        Swag.require(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)

        for index in prefix do
            source[index] = cast(u8, (97 + index % 26))
        source[prefix]     = 0xE2
        source[prefix + 1] = 0x82

        for index in actual.count
        {
            actual[index]   = 0xBEEF
            expected[index] = 0xBEEF
        }

        let truncatedSrc      = source[until prefix + 2]
        let truncatedActual   = Utf16.fromUtf8(actual, truncatedSrc)
        let truncatedExpected = scalarUtf16FromUtf8(expected, truncatedSrc)
        Swag.require(truncatedActual == truncatedExpected)
        Swag.require(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)

        for index in prefix do
            source[index] = cast(u8, (97 + index % 26))
        source[prefix]     = 0xC0
        source[prefix + 1] = 0xAF

        for index in actual.count
        {
            actual[index]   = 0xBEEF
            expected[index] = 0xBEEF
        }

        let overlongSrc      = source[until prefix + 2]
        let overlongActual   = Utf16.fromUtf8(actual, overlongSrc)
        let overlongExpected = scalarUtf16FromUtf8(expected, overlongSrc)
        Swag.require(overlongActual == overlongExpected)
        Swag.require(Memory.compare(actual.buffer, expected.buffer, #sizeof(actual)) == 0)
    }
}
