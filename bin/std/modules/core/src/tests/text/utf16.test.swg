#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func assertUtf16(values: const &Array'u16, expected: const [..] u16)->bool
{
    if values.count != @countof(expected) do
        return false

    for i in values.count
    {
        if values[i] != expected[i] do
            return false
    }

    return true
}

#test
{
    var buffer: [2] u16

    @assert(Utf16.encodeRune(buffer, 'A''rune) == 1)
    @assert(buffer[0] == 0x0041)

    @assert(Utf16.encodeRune(buffer, '\u20AC''rune) == 1)
    @assert(buffer[0] == 0x20AC)

    @assert(Utf16.encodeRune(buffer, '\U0001F642''rune) == 2)
    @assert(buffer[0] == 0xD83D)
    @assert(buffer[1] == 0xDE42)

    @assert(Utf16.encodeRune(buffer, 0xD800'rune) == 1)
    @assert(buffer[0] == 0xFFFD)
}

#test
{
    let values: [4] u16 = [0x0041, 0x20AC, 0xD83D, 0xDE42]

    var (c, eat) = Utf16.decodeRune(values)
    @assert(c == 'A''rune)
    @assert(eat == 1)

    (c, eat) = Utf16.decodeRune(values[1 until @countof(values)])
    @assert(c == '\u20AC''rune)
    @assert(eat == 1)

    (c, eat) = Utf16.decodeRune(values[2 until @countof(values)])
    @assert(c == '\U0001F642''rune)
    @assert(eat == 2)

    let loneHigh: [1] u16 = [0xD83D]
    (c, eat) = Utf16.decodeRune(loneHigh)
    @assert(c == Utf16.RuneError)
    @assert(eat == 1)

    let loneLow: [1] u16 = [0xDE42]
    (c, eat) = Utf16.decodeRune(loneLow)
    @assert(c == Utf16.RuneError)
    @assert(eat == 1)

    (c, eat) = Utf16.decodeRune(@mkslice(@dataof(values), 0))
    @assert(c == Utf16.RuneError)
    @assert(eat == 0)
}

#test
{
    let text = "A\u20AC\U0001F642"
    let expected: [4] u16 = [0x0041, 0x20AC, 0xD83D, 0xDE42]

    var dest: [8] u16
    let count = Utf16.fromUtf8(dest, text)
    @assert(count == 4)
    for i in count do
        @assert(dest[i] == expected[i])

    let result = Utf16.fromUtf8(text)
    @assert(assertUtf16(result, expected))
}

#test
{
    let runes: [3] rune = ['A''rune, '\u20AC''rune, '\U0001F642''rune]
    let expected: [4] u16 = [0x0041, 0x20AC, 0xD83D, 0xDE42]

    var dest: [8] u16
    let count = Utf16.fromUnicode(dest, runes)
    @assert(count == 4)
    for i in count do
        @assert(dest[i] == expected[i])

    let result = Utf16.fromUnicode(runes)
    @assert(assertUtf16(result, expected))
}

#test
{
    let expected: [6] u16 = [0x0043, 0x0061, 0x0066, 0x00E9, 0xD83D, 0xDE42]
    let zero = Utf16.toZeroTerminated("Caf\u00E9\U0001F642")

    @assert(zero.count == 7)
    for i in @countof(expected) do
        @assert(zero[i] == expected[i])
    @assert(zero[6] == 0)
    @assert(Utf16.lengthZeroTerminated(@dataof(zero)) == 6)
}

