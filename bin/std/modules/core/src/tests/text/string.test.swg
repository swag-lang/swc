#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertString(value: String, expected: string)->bool
{
    let text  = value.toString()
    let slice = value.toSlice()
    return value == expected and
           value.count == expected.count and
           text.count == expected.count and
           slice.count == expected.count and
           Memory.compare(text.buffer, expected.buffer, expected.count) == 0
}

func makePatternString(count: u64)->String
{
    var result: retval
    for i in count
    {
        let offset = cast(u8) (i % 26)
        result.append('a'u8 + offset)
    }

    return result
}

func reverseIndexOfByteAtLeast(value: String, minByte: u8)->u64
{
    for byte, index in value.reversed()
    {
        if byte < minByte do
            continue

        return index
    }

    return Swag.U64.Max
}

#test
{
    var value: String
    Swag.assert(value.isNull())
    Swag.assert(value.isEmpty())
    Swag.assert(value.isNullOrEmpty())
    Swag.assert(assertString(value, ""))

    value.ensureNotNull()
    Swag.assert(!value.isNull())
    Swag.assert(value.isEmpty())
    Swag.assert(value.isNullOrEmpty())
    Swag.assert(assertString(value, ""))

    value = " core "
    Swag.assert(!value.isNull())
    Swag.assert(!value.isEmpty())
    Swag.assert(!value.isNullOrEmpty())
    Swag.assert(assertString(value, " core "))

    value.trim()
    Swag.assert(assertString(value, "core"))

    value.insert(0, "[")
    value.append("]")
    Swag.assert(assertString(value, "[core]"))

    value.remove(0)
    value.removeBack()
    Swag.assert(assertString(value, "core"))

    value.clear()
    Swag.assert(value.isEmpty())
    Swag.assert(value.isNullOrEmpty())
    Swag.assert(assertString(value, ""))
    let emptyCstr = cast(#null cstring) value
    Swag.assert(emptyCstr.count == 0)

    value = "abc"
    Swag.assert(assertString(value, "abc"))
    let cstr = cast(#null cstring) value
    Swag.assert(cstr.count == 3)

    let nullText: #null string = null
    value = nullText
    Swag.assert(value.isEmpty())
    Swag.assert(assertString(value, ""))
    let nullCstr = cast(#null cstring) value
    Swag.assert(nullCstr.count == 0)
}

#test
{
    var value: String = "abcdef"
    Swag.assert(assertString(value, "abcdef"))

    Swag.assert(value[0] == 'a'u8)
    Swag.assert(value.back() == 'f'u8)
    Swag.assert(value[1 to 3] == "bcd")
    Swag.assert(value < "abcdeg")
    Swag.assert(value > "abcdee")
    Swag.assert((value <=> "abcdef") == 0)

    value[1] = 'Z'u8
    value[2] += 1'u8
    value[2] -= 1'u8
    Swag.assert(assertString(value, "aZcdef"))

    var sumBytes:   u32
    var sumIndexes: u64
    for byte, index in value
    {
        sumBytes   += cast(u32) byte
        sumIndexes += index
    }

    Swag.assert(sumBytes == cast(u32) 'a'u8 + cast(u32) 'Z'u8 + cast(u32) 'c'u8 + cast(u32) 'd'u8 + cast(u32) 'e'u8 + cast(u32) 'f'u8)
    Swag.assert(sumIndexes == 15)

    for &byte in value do
        byte[] += 1'u8

    Swag.assert(assertString(value, "b[defg"))

    Swag.assert(reverseIndexOfByteAtLeast(value, 'd'u8) == 5)
}

#test
{
    var value: String
    value.append('A'u8)
    value.append('B'rune)
    value.append("\u00E9")
    Swag.assert(assertString(value, "AB\u00E9"))

    value += "!"
    value += '?'rune
    value += '#'u8
    Swag.assert(assertString(value, "AB\u00E9!?#"))

    let strings: [3] string = ["-", "xy", "-"]
    value += strings
    Swag.assert(assertString(value, "AB\u00E9!?#-xy-"))

    let runes: [2] rune = ['\u00E9'rune, '!'rune]
    value += runes
    Swag.assert(assertString(value, "AB\u00E9!?#-xy-\u00E9!"))

    let bytes: [3] u8 = ['1'u8, '2'u8, '3'u8]
    value += bytes
    Swag.assert(assertString(value, "AB\u00E9!?#-xy-\u00E9!123"))

    value.appendFormat(":%/%/%%", "left", "right")
    Swag.assert(assertString(value, "AB\u00E9!?#-xy-\u00E9!123:left/right/%"))
}

#test
{
    var value: String = "core"

    value.insert(0, '['u8)
    value.insert(1, "std:")
    value.insert(value.count, ']'u8)
    value.insert(value.count, "")
    Swag.assert(assertString(value, "[std:core]"))

    value.remove(1, 4)
    Swag.assert(assertString(value, "[core]"))

    value.removeBack(1)
    value.remove(0, 1)
    Swag.assert(assertString(value, "core"))

    value.remove(2, 0)
    value.removeBack(0)
    Swag.assert(assertString(value, "core"))
}

#test
{
    var value: String = "1234"
    let tail          = value[1 to 3]
    value = tail
    Swag.assert(assertString(value, "234"))

    value = "1234"
    let middle = value[1 to 2]
    value.insert(0, middle)
    Swag.assert(assertString(value, "231234"))

    value = "1234"
    let repl = value[1 to 2]
    value.replace("1", repl)
    Swag.assert(assertString(value, "23234"))
}

#test
{
    var value: String = "  \tcore\r\n"
    value.trimStart()
    Swag.assert(assertString(value, "core\r\n"))

    value = "  \tcore\r\n"
    value.trimEnd()
    Swag.assert(assertString(value, "  \tcore"))

    value.trim()
    Swag.assert(assertString(value, "core"))

    value = "                \u00A0core\u00A0                "
    value.trimStart()
    Swag.assert(assertString(value, "core\u00A0                "))
    value.trimEnd()
    Swag.assert(assertString(value, "core"))

    value = "one fish, two fish, red fish"
    value.replace("fish", "cat")
    Swag.assert(assertString(value, "one cat, two cat, red cat"))

    value.replace("cat", "bird")
    Swag.assert(assertString(value, "one bird, two bird, red bird"))

    value.replace("bird", "")
    Swag.assert(assertString(value, "one , two , red "))

    value.replace("", "ignored")
    Swag.assert(assertString(value, "one , two , red "))

    value = "AaA"
    value.replace("a", "x", Utf8.ComparisonType.Latin1NoCase)
    Swag.assert(assertString(value, "xxx"))

    value = "a,b,,c"
    value.replace(','rune, "|")
    Swag.assert(assertString(value, "a|b||c"))

    value.replace('|'rune, "")
    Swag.assert(assertString(value, "abc"))
}

#test
{
    var value: String = "Core Caf\u00E9"

    Swag.assert(value.contains('C'u8))
    Swag.assert(value.contains('\u00E9'rune))
    Swag.assert(value.contains(cast(string) "Caf"))

    let needle: [3] u8 = ['a'u8, 'f'u8, 0xC3]
    Swag.assert(value.contains(cast(const [..] u8) needle))

    Swag.assert(value.startsWith("Core"))
    Swag.assert(value.startsWith("core", Utf8.ComparisonType.Latin1NoCase))
    Swag.assert(!value.startsWith("Cafe"))

    Swag.assert(value.endsWith("Café"))
    Swag.assert(!value.endsWith("Core"))
    Swag.assert(value.endsWith("café", Utf8.ComparisonType.Latin1NoCase))

    Swag.assert(value.indexOf("Core") == 0)
    Swag.assert(value.indexOf("Caf") == 5)
    Swag.assert(value.indexOf("core", comparisonType: Utf8.ComparisonType.Latin1NoCase) == 0)
    Swag.assert(value.indexOf("missing") == Swag.U64.Max)
    Swag.assert(value.indexOf('\u00E9'rune) == 8)
    Swag.assert(value.indexOf('\u00E9'rune, 10) == Swag.U64.Max)

    let runes = value.toRuneArray()
    Swag.assert(runes.count == 9)
    Swag.assert(runes[0] == 'C'rune)
    Swag.assert(runes[8] == '\u00E9'rune)
}

#test
{
    var value: String = "alpha"
    let ptr           = cast(const *String) &value

    Swag.assert(ptr.toString() == "alpha")
    Swag.assert(ptr[] == "alpha")
}

#test
{
    var value: String = "az\u00E9"
    value.makeUpper()
    Swag.assert(assertString(value, "AZ\u00C9"))

    value.makeLower()
    Swag.assert(assertString(value, "az\u00E9"))

    value = "az\u00E9"
    value.makeUpper(CharacterSet.Unicode)
    Swag.assert(assertString(value, "AZ\u00C9"))

    value.makeLower(CharacterSet.Unicode)
    Swag.assert(assertString(value, "az\u00E9"))

    Swag.assert(assertString(value.toUpper(), "AZ\u00C9"))
    Swag.assert(assertString(value.toLower(), "az\u00E9"))
    Swag.assert(assertString(String.toUpper("az\u00E9"), "AZ\u00C9"))
    Swag.assert(assertString(String.toLower("AZ\u00C9"), "az\u00E9"))
}

#test
{
    var small:     String = "small"
    var smallCopy: String
    smallCopy = small
    small[0]  = 'S'u8
    Swag.assert(assertString(small, "Small"))
    Swag.assert(assertString(smallCopy, "small"))

    var movedSmall: String
    movedSmall = #move smallCopy
    Swag.assert(assertString(movedSmall, "small"))

    var big                 = makePatternString(80)
    var expectedBig: String = big
    Swag.assert(big.capacity > StringSmallSize)

    var bigCopy: String
    bigCopy = big
    big[0]  = 'Z'u8
    Swag.assert(big[0] == 'Z'u8)
    Swag.assert(expectedBig[0] == 'a'u8)
    Swag.assert(assertString(bigCopy, expectedBig.toString()))

    var movedBig: String
    movedBig = #move bigCopy
    Swag.assert(assertString(movedBig, expectedBig.toString()))

    var reserved: String = "reserve"
    reserved.reserve(64)
    Swag.assert(reserved.capacity >= 64)
    Swag.assert(assertString(reserved, "reserve"))

    reserved.grow(128)
    Swag.assert(reserved.capacity >= 128)
    Swag.assert(assertString(reserved, "reserve"))
}

#test
{
    let fromValue = String.from("from")
    Swag.assert(assertString(fromValue, "from"))

    let fromNull = String.from(null)
    Swag.assert(assertString(fromNull, ""))

    let joined = String.join("a", "b", "c")
    Swag.assert(joined == "abc")
    Swag.assert(joined.count == 3)
    Swag.assert(assertString(joined, "abc"))

    let joinedWithSeparator = String.joinWith(",", "a", "b", "c")
    Swag.assert(assertString(joinedWithSeparator, "a,b,c"))

    let joinedWithoutSeparator = String.joinWith("", "a", "b", "c")
    Swag.assert(assertString(joinedWithoutSeparator, "abc"))

    var value: String = "123456789"
    Swag.assert(Hash.hash32(value) == Hash.hashBytes32(value.toSlice()))
}

#test
{
    var value: String = "caf\u00E9"
    Swag.assert(value.contains('\u00E9'rune))
    Swag.assert(value.indexOf('\u00E9'rune) == 3)
}

// Appending 'String' rvalues must accumulate intact content: the temporary's buffer has
// to stay alive until 'opAssign' consumed the view produced by the implicit cast.
#test
{
    var accumulator: String
    for i in 32 do
        accumulator += Format.toString("fragment-%-padded-beyond-the-small-string-size;", i)

    // 32 fragments of 46 bytes plus the decimal digits of 0..31.
    Swag.assert(accumulator.length == 32 * 46 + 10 + 22 * 2)
    Swag.assert(accumulator.startsWith("fragment-0-padded"))
    Swag.assert(accumulator.endsWith("fragment-31-padded-beyond-the-small-string-size;"))
}
