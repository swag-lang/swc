#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func assertString(value: const &String, expected: string)->bool
{
    let text  = value.toString()
    let slice = value.toSlice()
    return value == expected and
        @countof(value) == @countof(expected) and
        @countof(text) == @countof(expected) and
        @countof(slice) == @countof(expected) and
        Memory.compare(@dataof(text), @dataof(expected), @countof(expected)) == 0
}

func makePatternString(count: u64)->String
{
    var result: retval
    for i in count
    {
        let offset = cast(u8) (i % 26)
        result.append('a''u8 + offset)
    }

    return result
}

func reverseIndexOfByteAtLeast(value: const &String, minByte: u8)->u64
{
    foreach #reverse byte, index in value
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
    @assert(value.isNull())
    @assert(value.isEmpty())
    @assert(value.isNullOrEmpty())
    @assert(assertString(value, ""))

    value.ensureNotNull()
    @assert(!value.isNull())
    @assert(value.isEmpty())
    @assert(value.isNullOrEmpty())
    @assert(assertString(value, ""))

    value = " core "
    @assert(!value.isNull())
    @assert(!value.isEmpty())
    @assert(!value.isNullOrEmpty())
    @assert(assertString(value, " core "))

    value.trim()
    @assert(assertString(value, "core"))

    value.insert(0, "[")
    value.append("]")
    @assert(assertString(value, "[core]"))

    value.remove(0)
    value.removeBack()
    @assert(assertString(value, "core"))

    value.clear()
    @assert(value.isEmpty())
    @assert(value.isNullOrEmpty())
    @assert(assertString(value, ""))
    let emptyCstr = cast(cstring) value
    @assert(@countof(emptyCstr) == 0)

    value = "abc"
    @assert(assertString(value, "abc"))
    let cstr = cast(cstring) value
    @assert(@countof(cstr) == 3)

    let nullText: string = null
    value = nullText
    @assert(value.isEmpty())
    @assert(assertString(value, ""))
    let nullCstr = cast(cstring) value
    @assert(@countof(nullCstr) == 0)
}

#test
{
    var value: String = "abcdef"
    @assert(assertString(value, "abcdef"))

    @assert(value[0] == 'a''u8)
    @assert(value.back() == 'f''u8)
    @assert(value[1 to 3] == "bcd")
    @assert(value < "abcdeg")
    @assert(value > "abcdee")
    @assert((value <=> "abcdef") == 0)

    value[1] = 'Z''u8
    value[2] += 1'u8
    value[2] -= 1'u8
    @assert(assertString(value, "aZcdef"))

    var sumBytes: u32
    var sumIndexes: u64
    foreach byte, index in value
    {
        sumBytes += cast(u32) byte
        sumIndexes += index
    }

    @assert(sumBytes == cast(u32) 'a''u8 + cast(u32) 'Z''u8 + cast(u32) 'c''u8 + cast(u32) 'd''u8 + cast(u32) 'e''u8 + cast(u32) 'f''u8)
    @assert(sumIndexes == 15)

    foreach &byte in value do
        dref byte += 1'u8

    @assert(assertString(value, "b[defg"))

    @assert(reverseIndexOfByteAtLeast(value, 'd''u8) == 5)
}

#test
{
    var value: String
    value.append('A''u8)
    value.append('B''rune)
    value.append("\u00E9")
    @assert(assertString(value, "AB\u00E9"))

    value += "!"
    value += '?''rune
    value += '#''u8
    @assert(assertString(value, "AB\u00E9!?#"))

    let strings: [3] string = ["-", "xy", "-"]
    value += strings
    @assert(assertString(value, "AB\u00E9!?#-xy-"))

    let runes: [2] rune = ['\u00E9''rune, '!''rune]
    value += runes
    @assert(assertString(value, "AB\u00E9!?#-xy-\u00E9!"))

    let bytes: [3] u8 = ['1''u8, '2''u8, '3''u8]
    value += bytes
    @assert(assertString(value, "AB\u00E9!?#-xy-\u00E9!123"))

    value.appendFormat(":%/%/%%", "left", "right")
    @assert(assertString(value, "AB\u00E9!?#-xy-\u00E9!123:left/right/%"))
}

#test
{
    var value: String = "core"

    value.insert(0, '[''u8)
    value.insert(1, "std:")
    value.insert(@countof(value), ']''u8)
    value.insert(@countof(value), "")
    @assert(assertString(value, "[std:core]"))

    value.remove(1, 4)
    @assert(assertString(value, "[core]"))

    value.removeBack(1)
    value.remove(0, 1)
    @assert(assertString(value, "core"))

    value.remove(2, 0)
    value.removeBack(0)
    @assert(assertString(value, "core"))
}

#test
{
    var value: String = "  \tcore\r\n"
    value.trimStart()
    @assert(assertString(value, "core\r\n"))

    value = "  \tcore\r\n"
    value.trimEnd()
    @assert(assertString(value, "  \tcore"))

    value.trim()
    @assert(assertString(value, "core"))

    value = "one fish, two fish, red fish"
    value.replace("fish", "cat")
    @assert(assertString(value, "one cat, two cat, red cat"))

    value.replace("cat", "bird")
    @assert(assertString(value, "one bird, two bird, red bird"))

    value.replace("bird", "")
    @assert(assertString(value, "one , two , red "))

    value.replace("", "ignored")
    @assert(assertString(value, "one , two , red "))

    value = "AaA"
    value.replace("a", "x", Utf8.ComparisonType.Latin1NoCase)
    @assert(assertString(value, "xxx"))

    value = "a,b,,c"
    value.replace(',''rune, "|")
    @assert(assertString(value, "a|b||c"))

    value.replace('|''rune, "")
    @assert(assertString(value, "abc"))
}

#test
{
    var value: String = "Core Caf\u00E9"

    @assert(value.contains('C''u8))
    @assert(value.contains('\u00E9''rune))
    @assert(value.contains("Caf"))

    let needle: [3] u8 = ['a''u8, 'f''u8, 0xc3]
    @assert(value.contains(cast(const [..] u8) needle))

    @assert(value.startsWith("Core"))
    @assert(value.startsWith("core", Utf8.ComparisonType.Latin1NoCase))
    @assert(!value.startsWith("Cafe"))

    @assert(value.indexOf("Core") == 0)
    @assert(value.indexOf("Caf") == 5)
    @assert(value.indexOf("core", comparisonType: Utf8.ComparisonType.Latin1NoCase) == 0)
    @assert(value.indexOf("missing") == Swag.U64.Max)
    @assert(value.indexOf('\u00E9''rune) == 8)
    @assert(value.indexOf('\u00E9''rune, 10) == Swag.U64.Max)

    let runes = value.toRuneArray()
    @assert(runes.count == 9)
    @assert(runes[0] == 'C''rune)
    @assert(runes[8] == '\u00E9''rune)
}

#test
{
    var value: String = "alpha"
    let ref = cast(const &String) value

    @assert(ref.toString() == "alpha")
    @assert(ref == "alpha")
}

#test
{
    var value: String = "az\u00E9"
    value.makeUpper()
    @assert(assertString(value, "AZ\u00C9"))

    value.makeLower()
    @assert(assertString(value, "az\u00E9"))

    value = "az\u00E9"
    value.makeUpper(CharacterSet.Unicode)
    @assert(assertString(value, "AZ\u00C9"))

    value.makeLower(CharacterSet.Unicode)
    @assert(assertString(value, "az\u00E9"))

    @assert(assertString(value.toUpper(), "AZ\u00C9"))
    @assert(assertString(value.toLower(), "az\u00E9"))
    @assert(assertString(String.toUpper("az\u00E9"), "AZ\u00C9"))
    @assert(assertString(String.toLower("AZ\u00C9"), "az\u00E9"))
}

#test
{
    var small: String = "small"
    var smallCopy: String
    smallCopy = small
    small[0] = 'S''u8
    @assert(assertString(small, "Small"))
    @assert(assertString(smallCopy, "small"))

    var movedSmall: String
    movedSmall = #move smallCopy
    @assert(assertString(movedSmall, "small"))

    var big = makePatternString(80)
    var expectedBig: String = big
    @assert(big.capacity > StringSmallSize)

    var bigCopy: String
    bigCopy = big
    big[0] = 'Z''u8
    @assert(big[0] == 'Z''u8)
    @assert(expectedBig[0] == 'a''u8)
    @assert(assertString(bigCopy, expectedBig.toString()))

    var movedBig: String
    movedBig = #move bigCopy
    @assert(assertString(movedBig, expectedBig.toString()))

    var reserved: String = "reserve"
    reserved.reserve(64)
    @assert(reserved.capacity >= 64)
    @assert(assertString(reserved, "reserve"))

    reserved.grow(128)
    @assert(reserved.capacity >= 128)
    @assert(assertString(reserved, "reserve"))
}

#test
{
    let fromValue = String.from("from")
    @assert(assertString(fromValue, "from"))

    let fromNull = String.from(null)
    @assert(assertString(fromNull, ""))

    let joined = String.join("a", "b", "c")
    @assert(joined == "abc")
    @assert(@countof(joined) == 3)
    @assert(assertString(joined, "abc"))

    let joinedWithSeparator = String.joinWith(",", "a", "b", "c")
    @assert(assertString(joinedWithSeparator, "a,b,c"))

    let joinedWithoutSeparator = String.joinWith("", "a", "b", "c")
    @assert(assertString(joinedWithoutSeparator, "abc"))

    var value: String = "123456789"
    @assert(Hash.hash32(value) == Hash.Crc32.compute(value.toSlice()))
}

#test
{
    var value: String = "caf\u00E9"
    @assert(value.contains('\u00E9''rune))
    @assert(value.indexOf('\u00E9''rune) == 3)
}
