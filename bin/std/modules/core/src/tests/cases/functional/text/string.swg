#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertConstStringByteBorrows(value: const *String)->u64
{
    var count = 0'u64
    for &byte, index in value[]
    {
        #assert(#typeof(byte) == const *u8)
        Swag.require(byte[] == value[][index])
        count += 1
    }
    return count
}

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
    var result: #returntype
    for i in count
    {
        let offset = cast(u8, (i % 26))
        result.append('a'u8 + offset)
    }

    return result
}

func reverseIndexOfByteAtLeast(value: String, minByte: u8)->u64
{
    for byte, index in value.reversed() where byte >= minByte do
        return index
    return Swag.U64.Max
}

#test
{
    let owned:  String = "middle"
    let equal:  string = "middle"
    let before: string = "before"
    let after:  string = "zebra"

    Swag.require(equal == owned)
    Swag.require(not (equal != owned))
    Swag.require(before != owned)
    Swag.require(before < owned)
    Swag.require(before <= owned)
    Swag.require(equal <= owned)
    Swag.require(after > owned)
    Swag.require(after >= owned)
    Swag.require(equal >= owned)
    Swag.require((before <=> owned) < 0)
    Swag.require((equal <=> owned) == 0)
    Swag.require((after <=> owned) > 0)
}

#test
{
    let text = String.from("A\u00E9\U0001F642")
    let expectedRunes:       [3] rune = ['A'rune, '\u00E9'rune, '\U0001F642'rune]
    let expectedByteIndices: [3] u64  = [0, 1, 3]

    var nextCharIndex = 0'u64
    for value, charIndex, byteIndex in text.runes()
    {
        Swag.require(charIndex == nextCharIndex)
        Swag.require(value == expectedRunes[nextCharIndex])
        Swag.require(byteIndex == expectedByteIndices[nextCharIndex])
        nextCharIndex += 1
    }

    Swag.require(nextCharIndex == expectedRunes.count)

    var empty: String
    var emptyCount = 0'u64
    for value, charIndex, byteIndex in empty.runes()
    {
        Swag.require(value == 0 and charIndex == emptyCount and byteIndex == 0)
        emptyCount += 1
    }

    Swag.require(emptyCount == 0)
}

#test
{
    var value: String
    Swag.require(value.isNull())
    Swag.require(value.isEmpty())
    Swag.require(value.isNullOrEmpty())
    Swag.require(assertString(value, ""))

    value.ensureNotNull()
    Swag.require(not value.isNull())
    Swag.require(value.isEmpty())
    Swag.require(value.isNullOrEmpty())
    Swag.require(assertString(value, ""))

    value = " core "
    Swag.require(not value.isNull())
    Swag.require(not value.isEmpty())
    Swag.require(not value.isNullOrEmpty())
    Swag.require(assertString(value, " core "))

    value.trim()
    Swag.require(assertString(value, "core"))

    value.insert(0, "[")
    value.append("]")
    Swag.require(assertString(value, "[core]"))

    value.remove(0)
    value.removeBack()
    Swag.require(assertString(value, "core"))

    value.clear()
    Swag.require(value.isEmpty())
    Swag.require(value.isNullOrEmpty())
    Swag.require(assertString(value, ""))
    let emptyCstr = cast(cstring?, value)
    Swag.require(emptyCstr.count == 0)

    value = "abc"
    Swag.require(assertString(value, "abc"))
    let cstr = cast(cstring?, value)
    Swag.require(cstr.count == 3)

    let nullText: string? = null
    value = nullText
    Swag.require(value.isEmpty())
    Swag.require(assertString(value, ""))
    let nullCstr = cast(cstring?, value)
    Swag.require(nullCstr.count == 0)
}

#test
{
    var value: String = "abcdef"
    Swag.require(assertString(value, "abcdef"))

    Swag.require(value[0] == 'a'u8)
    Swag.require(value.back() == 'f'u8)
    Swag.require(value[1 to 3] == "bcd")
    Swag.require(not (value == value[0 to 2]))
    Swag.require(value == value[0 to 5])
    Swag.require(value < "abcdeg")
    Swag.require(value > "abcdee")
    Swag.require((value <=> "abcdef") == 0)

    value[1] = 'Z'u8
    value[2] += 1'u8
    value[2] -= 1'u8
    let expectedText: string = "aZcdef"
    Swag.require(assertString(value, expectedText))

    var visitedCount = 0'u64
    for byte, index in value
    {
        Swag.require(index < expectedText.count)
        Swag.require(byte == expectedText[index])
        visitedCount += 1
    }

    Swag.require(visitedCount == expectedText.count)
    Swag.require(assertConstStringByteBorrows(&value) == expectedText.count)

    for &byte in value do
        byte[] += 1'u8

    Swag.require(assertString(value, "b[defg"))

    Swag.require(reverseIndexOfByteAtLeast(value, 'd'u8) == 5)
}

#test
{
    var value: String
    value.append('A'u8)
    value.append('B'rune)
    value.append("\u00E9")
    Swag.require(assertString(value, "AB\u00E9"))

    value += "!"
    value += '?'rune
    value += '#'u8
    Swag.require(assertString(value, "AB\u00E9!?#"))

    let strings: [3] string = ["-", "xy", "-"]
    value += strings
    Swag.require(assertString(value, "AB\u00E9!?#-xy-"))

    let runes: [2] rune = ['\u00E9'rune, '!'rune]
    value += runes
    Swag.require(assertString(value, "AB\u00E9!?#-xy-\u00E9!"))

    let bytes: [3] u8 = ['1'u8, '2'u8, '3'u8]
    value += bytes
    Swag.require(assertString(value, "AB\u00E9!?#-xy-\u00E9!123"))

    value.appendFormat(":%/%/%%", "left", "right")
    Swag.require(assertString(value, "AB\u00E9!?#-xy-\u00E9!123:left/right/%"))
}

#test
{
    var value: String = "core"

    value.insert(0, '['u8)
    value.insert(1, "std:")
    value.insert(value.count, ']'u8)
    value.insert(value.count, "")
    Swag.require(assertString(value, "[std:core]"))

    value.remove(1, 4)
    Swag.require(assertString(value, "[core]"))

    value.removeBack(1)
    value.remove(0, 1)
    Swag.require(assertString(value, "core"))

    value.remove(2, 0)
    value.removeBack(0)
    Swag.require(assertString(value, "core"))
}

#test
{
    var value: String = "1234"
    let tail = value[1 to 3]
    value = tail
    Swag.require(assertString(value, "234"))

    value = "1234"
    let middle = value[1 to 2]
    value.insert(0, middle)
    Swag.require(assertString(value, "231234"))

    value = "1234"
    let repl = value[1 to 2]
    value.replace("1", repl)
    Swag.require(assertString(value, "23234"))
}

#test
{
    var value: String = "  \tcore\r\n"
    value.trimStart()
    Swag.require(assertString(value, "core\r\n"))

    value = "  \tcore\r\n"
    value.trimEnd()
    Swag.require(assertString(value, "  \tcore"))

    value.trim()
    Swag.require(assertString(value, "core"))

    value = "                \u00A0core\u00A0                "
    value.trimStart()
    Swag.require(assertString(value, "core\u00A0                "))
    value.trimEnd()
    Swag.require(assertString(value, "core"))

    value = "one fish, two fish, red fish"
    value.replace("fish", "cat")
    Swag.require(assertString(value, "one cat, two cat, red cat"))

    value.replace("cat", "bird")
    Swag.require(assertString(value, "one bird, two bird, red bird"))

    value.replace("bird", "")
    Swag.require(assertString(value, "one , two , red "))

    value.replace("", "ignored")
    Swag.require(assertString(value, "one , two , red "))

    value = "AaA"
    value.replace("a", "x", Utf8.ComparisonType.Latin1NoCase)
    Swag.require(assertString(value, "xxx"))

    value = "a,b,,c"
    value.replace(','rune, "|")
    Swag.require(assertString(value, "a|b||c"))

    value.replace('|'rune, "")
    Swag.require(assertString(value, "abc"))
}

#test
{
    var value: String = "Core Caf\u00E9"

    Swag.require(value.contains('C'u8))
    Swag.require(value.contains('\u00E9'rune))
    Swag.require(value.contains(cast(string, "Caf")))

    let needle: [3] u8 = ['a'u8, 'f'u8, 0xC3]
    Swag.require(value.contains(cast(const [..] u8, needle)))

    Swag.require(value.startsWith("Core"))
    Swag.require(value.startsWith("core", Utf8.ComparisonType.Latin1NoCase))
    Swag.require(not value.startsWith("Cafe"))

    Swag.require(value.endsWith("Café"))
    Swag.require(not value.endsWith("Core"))
    Swag.require(value.endsWith("café", Utf8.ComparisonType.Latin1NoCase))

    Swag.require(value.indexOf("Core") == 0)
    Swag.require(value.indexOf("Caf") == 5)
    Swag.require(value.indexOf("core", comparisonType: Utf8.ComparisonType.Latin1NoCase) == 0)
    Swag.require(value.indexOf("missing") == Swag.U64.Max)
    Swag.require(value.indexOf('\u00E9'rune) == 8)
    Swag.require(value.indexOf('\u00E9'rune, 10) == Swag.U64.Max)

    let runes = value.toRuneArray()
    Swag.require(runes.count == 9)
    Swag.require(runes[0] == 'C'rune)
    Swag.require(runes[8] == '\u00E9'rune)
}

#test
{
    var value: String = "alpha"
    let ptr = cast(const *String, &value)

    Swag.require(ptr.toString() == "alpha")
    Swag.require(ptr[] == "alpha")
}

#test
{
    var value: String = "az\u00E9"
    value.makeUpper()
    Swag.require(assertString(value, "AZ\u00C9"))

    value.makeLower()
    Swag.require(assertString(value, "az\u00E9"))

    value = "az\u00E9"
    value.makeUpper(CharacterSet.Unicode)
    Swag.require(assertString(value, "AZ\u00C9"))

    value.makeLower(CharacterSet.Unicode)
    Swag.require(assertString(value, "az\u00E9"))

    Swag.require(assertString(value.toUpper(), "AZ\u00C9"))
    Swag.require(assertString(value.toLower(), "az\u00E9"))
    Swag.require(assertString(String.toUpper("az\u00E9"), "AZ\u00C9"))
    Swag.require(assertString(String.toLower("AZ\u00C9"), "az\u00E9"))

    var reserved: String = "az\u00E9"
    reserved.reserve(128)
    let capacity = reserved.capacity
    reserved.makeUpper(CharacterSet.Unicode)
    Swag.require(assertString(reserved, "AZ\u00C9"))
    Swag.require(reserved.capacity >= capacity)
}

#test
{
    var small:     String = "small"
    var smallCopy: String
    smallCopy = small
    small[0]  = 'S'u8
    Swag.require(assertString(small, "Small"))
    Swag.require(assertString(smallCopy, "small"))

    var movedSmall: String
    movedSmall = #move smallCopy
    Swag.require(assertString(movedSmall, "small"))

    var big = makePatternString(80)
    var expectedBig: String = big
    Swag.require(big.capacity > StringSmallSize)

    var bigCopy: String
    bigCopy = big
    big[0]  = 'Z'u8
    Swag.require(big[0] == 'Z'u8)
    Swag.require(expectedBig[0] == 'a'u8)
    Swag.require(assertString(bigCopy, expectedBig.toString()))

    var movedBig: String
    movedBig = #move bigCopy
    Swag.require(assertString(movedBig, expectedBig.toString()))

    var reserved: String = "reserve"
    reserved.reserve(64)
    Swag.require(reserved.capacity >= 64)
    Swag.require(assertString(reserved, "reserve"))

    reserved.grow(128)
    Swag.require(reserved.capacity >= 128)
    Swag.require(assertString(reserved, "reserve"))

    var truncated: String = "reserve"
    truncated.reserve(4)
    Swag.require(assertString(truncated, "res"))
    Swag.require(truncated.capacity == StringSmallSize)
    Swag.require(truncated.storage()[truncated.length] == 0)

    truncated.reserve(0)
    Swag.require(truncated.isEmpty())
    Swag.require(truncated.storage()[0] == 0)
    Swag.require(cast(cstring?, truncated).count == 0)

    var heapTruncated = makePatternString(80)
    heapTruncated.reserve(4)
    Swag.require(assertString(heapTruncated, "abc"))
    Swag.require(heapTruncated.storage()[3] == 0)

    var allocatedEmpty: String
    allocatedEmpty.reserve(64)
    Swag.require(allocatedEmpty.isEmpty())
    Swag.require(allocatedEmpty.storage()[0] == 0)
    Swag.require(cast(cstring?, allocatedEmpty).count == 0)
}

#test
{
    let fromValue = String.from("from")
    Swag.require(assertString(fromValue, "from"))

    let fromNull = String.from(null)
    Swag.require(assertString(fromNull, ""))

    let joined = String.join("a", "b", "c")
    Swag.require(joined == "abc")
    Swag.require(joined.count == 3)
    Swag.require(assertString(joined, "abc"))

    let joinedWithSeparator = String.joinWith(",", "a", "b", "c")
    Swag.require(assertString(joinedWithSeparator, "a,b,c"))

    let joinedWithoutSeparator = String.joinWith("", "a", "b", "c")
    Swag.require(assertString(joinedWithoutSeparator, "abc"))

    var value: String = "123456789"
    Swag.require(Hash.hash32(value) == Hash.hashBytes32(value.toSlice()))
}

#test
{
    var value: String = "caf\u00E9"
    Swag.require(value.contains('\u00E9'rune))
    Swag.require(value.indexOf('\u00E9'rune) == 3)
}

// Appending 'String' rvalues must accumulate intact content: the temporary's buffer has
// to stay alive until 'opAssign' consumed the view produced by the implicit cast.
#test
{
    var accumulator: String
    for i in 32 do
        accumulator += Format.toString("fragment-%-padded-beyond-the-small-string-size;", i)

    // 32 fragments of 46 bytes plus the decimal digits of 0..31.
    Swag.require(accumulator.length == 32 * 46 + 10 + 22 * 2)
    Swag.require(accumulator.startsWith("fragment-0-padded"))
    Swag.require(accumulator.endsWith("fragment-31-padded-beyond-the-small-string-size;"))
}

// A String that holds nothing answers an address for its storage too, on the same terms as
// an empty array: the walk is bounded by 'length', which is zero.
#test
{
    var empty: String
    Swag.require(empty.isNull())
    Swag.require(empty.storage() != null)

    empty = "abc"
    Swag.require(empty.storage()[0] == 'a')
}

// Replacing a rune removes all of its bytes, whatever its encoded length.
#test
{
    var text = String.from("a€b€c")
    text.replace('€', "EUR")
    Swag.require(text == "aEURbEURc")

    var shorter = String.from("x→y→z")
    shorter.replace('→', "")
    Swag.require(shorter == "xyz")
}

// Trimming the start moves the kept text over the space it removes.
#test
{
    var text = String.from("  \t  leading space removed, longer than the inline storage")
    text.trimStart()
    Swag.require(text == "leading space removed, longer than the inline storage")
}

// A Unicode case change keeps the zero terminator a cstring view relies on.
#test
{
    var text = String.from("ÉTÉ")
    text.makeLower(.Unicode)
    Swag.require(text == "été")
    Swag.require(text.storage()[text.length] == 0)

    let runes: [3] rune = ['😀', '😀', '😀']
    let wide = Utf8.fromUnicode(runes)
    Swag.require(wide.length == 12)
    Swag.require(wide.storage()[wide.length] == 0)
}

// Borrowed source bytes survive growth from both inline and allocated storage.
#test
{
    for original in ["abc123abc123abc", "abc123abc123abc123abc"]
    {
        var appended: String = original
        let appendSource     = appended[until 3]
        appended.append(appendSource)
        Swag.require(assertString(appended, Format.toString("%abc", original)))

        var inserted: String = original
        let insertSource     = inserted[until 3]
        inserted.insert(0, insertSource)
        Swag.require(assertString(inserted, Format.toString("abc%", original)))
    }
}

// Search and replacement views can each refer to the bytes being changed.
#test
{
    struct AliasCase
    {
        source:         string
        searchReplaced: string
        valueReplaced:  string
    }

    let cases: [2] AliasCase = [
        AliasCase{"abc123abc123abc", "X123X123X", "abcabc23abcabc23abc"},
        AliasCase{"abc123abc123abc123abc", "X123X123X123X", "abcabc23abcabc23abcabc23abc"}]

    for sample in cases
    {
        var search: String = sample.source
        let what = search[until 3]
        search.replace(what, "X")
        Swag.require(assertString(search, sample.searchReplaced))

        var replacement: String = sample.source
        let by = replacement[until 3]
        replacement.replace('1'rune, by)
        Swag.require(assertString(replacement, sample.valueReplaced))
    }
}

// Owned strings retain text equality when nested in composite values.
#test
{
    struct Item { label: String; id: u32 }
    struct Wrapper { item: Item }
    let first = Item{String.from("same text"), 7}
    let equal = Item{String.from("same text"), 7}
    Swag.require(first.label.toSlice().buffer != equal.label.toSlice().buffer)
    Swag.require(first.label == equal.label)
    Swag.require(first == equal)
    Swag.require(Wrapper{first} == Wrapper{equal})
    Swag.require([first] == [equal])
    Swag.require(first != Item{String.from("other text"), 7})
    Swag.require(first != Item{String.from("same text"), 8})
    Swag.require(Item{String{}, 0} == Item{String.from(""), 0})
}
