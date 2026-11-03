#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertFormatString(value: String, expected: string)->bool
{
    let text = value.toString()
    return value == expected and
           value.count == expected.count and
           text.count == expected.count and
           Memory.compare(text.buffer, expected.buffer, expected.count) == 0
}

func formatReferencedString(value: String)->String => Format.toString("%", value)

#test
{
    Swag.require(Format.countPercent("") == 0)
    Swag.require(Format.countPercent("%%") == 0)
    Swag.require(Format.countPercent("%/%%/%{X}") == 2)
}

#test
{
    let mixed = Format.toString("%% % %{X} %{D03}", "core", 255, 7)
    Swag.require(assertFormatString(mixed, "% core FF 007"))

    var replaced: String = "seed"
    Format.replaceString(&replaced, "%{02}:%{02}", 3, 9)
    Swag.require(assertFormatString(replaced, "03:09"))
}

#test
{
    let padded = Format.toString("%{04}", 7)
    Swag.require(assertFormatString(padded, "0007"))

    let forcedPositive = Format.toString("%{+04}", 7)
    Swag.require(assertFormatString(forcedPositive, "+007"))

    let forcedNegative = Format.toString("%{+04}", -7)
    Swag.require(assertFormatString(forcedNegative, "-007"))
}

#test
{
    var dest: String
    Format.replaceString(&dest, "fresh %", "value")
    Swag.require(assertFormatString(dest, "fresh value"))
    Swag.require(dest.storage()[dest.count] == 0)
}

#test
{
    var dest: String = "small"
    Format.replaceString(&dest, "a replacement larger than inline storage: %", 42)
    Swag.require(assertFormatString(dest, "a replacement larger than inline storage: 42"))
    Swag.require(dest.storage()[dest.count] == 0)
}

#test
{
    var dest: String = "original"
    let borrowed     = dest.toString()
    Format.replaceString(&dest, "[%] %", borrowed, borrowed)
    Swag.require(assertFormatString(dest, "[original] original"))
}

#test
{
    var dest: String = "abcdefghijklmnopqrstuvwxyz"
    let storage      = dest.buffer
    Format.replaceString(&dest, "%", "short")
    Swag.require(assertFormatString(dest, "short"))
    Swag.require(dest.buffer == storage)
    Swag.require(dest.storage()[dest.count] == 0)
    Format.replaceString(&dest, "")
    Swag.require(dest.isEmpty())
    Swag.require(dest.buffer == storage)
    Swag.require(dest.storage()[0] == 0)
}

#test
{
    var direct: ConcatBuffer
    let fmt:    StrConv.ConvertFormat
    let text = "variable"

    StrConv.convertAny(&direct, "literal", fmt, null)
    StrConv.convertAny(&direct, " ", fmt, null)
    StrConv.convertAny(&direct, text, fmt, null)
    StrConv.convertAny(&direct, " ", fmt, null)
    StrConv.convertAny(&direct, true, fmt, null)
    StrConv.convertAny(&direct, " ", fmt, null)
    StrConv.convertAny(&direct, cast(rune, 'A'), fmt, null)

    Swag.require(assertFormatString(direct.toString(), "literal variable true A"))
}

#test
{
    let value = String.from("referenced")
    Swag.require(assertFormatString(formatReferencedString(value), "referenced"))
}

// '%{#n}' targets an explicit 0-based argument, so translations can reorder arguments.
#test
{
    let swapped = Format.toString("%{#1} then %{#0}", "first", "second")
    Swag.require(assertFormatString(swapped, "second then first"))

    let repeated = Format.toString("%{#0} and %{#0} again", "twice")
    Swag.require(assertFormatString(repeated, "twice and twice again"))

    // An indexed placeholder carries a conversion format after ':' and leaves the
    // running position of plain '%' placeholders untouched.
    let mixed = Format.toString("% %{#2:X} %", "a", "b", 255)
    Swag.require(assertFormatString(mixed, "a FF b"))
}

// 'byteSize' scales through the 1024-based units and keeps three significant digits.
#test
{
    Swag.require(Format.byteSize(0) == "0 B")
    Swag.require(Format.byteSize(312) == "312 B")
    Swag.require(Format.byteSize(1023) == "1023 B")
    Swag.require(Format.byteSize(1024) == "1.00 KB")
    Swag.require(Format.byteSize(4200) == "4.10 KB")
    Swag.require(Format.byteSize(1024 * 1024) == "1.00 MB")
    Swag.require(Format.byteSize(14_050_000) == "13.4 MB")
    Swag.require(Format.byteSize(650 * 1024 * 1024) == "650 MB")
    Swag.require(Format.byteSize(1024'u64 * 1024 * 1024 * 1024) == "1.00 TB")
}

#test
{
    Swag.require(StrConv.toDisplaySize(0) == "0 bytes")
    Swag.require(StrConv.toDisplaySize(1) == "1 byte")
    Swag.require(StrConv.toDisplaySize(1023) == "1023 bytes")
    Swag.require(StrConv.toDisplaySize(1536) == "1 KB")
}

// A character literal formats as the character, and a decimal literal as the double nearest to it.
#test
{
    Swag.require(Format.toString("%", 'A') == "A")
    Swag.require(Format.toString("% %", 'é', '😀') == "é 😀")
    Swag.require(Format.toString("%{f2}", 1.005) == "1.00")
    Swag.require(Format.toString("%", 0.00012) == "0.00012")
}

// Format views need no terminator, including at a final placeholder or escaped percent.
#test
{
    let storage = "text %% % trailing"
    let view    = storage[until 9]
    Swag.require(Format.toString(view, 42) == "text % 42")
    Swag.require(Format.toString("plain text") == "plain text")
    Swag.require(Format.toString("%%") == "%")
    Swag.require(Format.toString("%% tail") == "% tail")
    Swag.require(Format.toString("%", 42) == "42")
    Swag.require(Format.toString("%{#1} % tail", "first", "second") == "second first tail")
}
