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

func formatReferencedString(value: String)->String
{
    return Format.toString("%", value)
}

#test
{
    Swag.assert(Format.countPercent("") == 0)
    Swag.assert(Format.countPercent("%%") == 0)
    Swag.assert(Format.countPercent("%/%%/%{X}") == 2)
}

#test
{
    let mixed = Format.toString("%% % %{X} %{D03}", "core", 255, 7)
    Swag.assert(assertFormatString(mixed, "% core FF 007"))

    var replaced: String = "seed"
    Format.replaceString(&replaced, "%{02}:%{02}", 3, 9)
    Swag.assert(assertFormatString(replaced, "03:09"))
}

#test
{
    let padded = Format.toString("%{04}", 7)
    Swag.assert(assertFormatString(padded, "0007"))

    let forcedPositive = Format.toString("%{+04}", 7)
    Swag.assert(assertFormatString(forcedPositive, "+007"))

    let forcedNegative = Format.toString("%{+04}", -7)
    Swag.assert(assertFormatString(forcedNegative, "-007"))
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
    StrConv.convertAny(&direct, cast(rune) 'A', fmt, null)

    Swag.assert(assertFormatString(direct.toString(), "literal variable true A"))
}

#test
{
    let value = String.from("referenced")
    Swag.assert(assertFormatString(formatReferencedString(value), "referenced"))
}

// '%{#n}' targets an explicit 0-based argument, so translations can reorder arguments.
#test
{
    let swapped = Format.toString("%{#1} then %{#0}", "first", "second")
    Swag.assert(assertFormatString(swapped, "second then first"))

    let repeated = Format.toString("%{#0} and %{#0} again", "twice")
    Swag.assert(assertFormatString(repeated, "twice and twice again"))

    // An indexed placeholder carries a conversion format after ':' and leaves the
    // running position of plain '%' placeholders untouched.
    let mixed = Format.toString("% %{#2:X} %", "a", "b", 255)
    Swag.assert(assertFormatString(mixed, "a FF b"))
}

// 'byteSize' scales through the 1024-based units and keeps three significant digits.
#test
{
    Swag.assert(Format.byteSize(0) == "0 B")
    Swag.assert(Format.byteSize(312) == "312 B")
    Swag.assert(Format.byteSize(1023) == "1023 B")
    Swag.assert(Format.byteSize(1024) == "1.00 KB")
    Swag.assert(Format.byteSize(4200) == "4.10 KB")
    Swag.assert(Format.byteSize(1024 * 1024) == "1.00 MB")
    Swag.assert(Format.byteSize(14_050_000) == "13.4 MB")
    Swag.assert(Format.byteSize(650 * 1024 * 1024) == "650 MB")
    Swag.assert(Format.byteSize(1024'u64 * 1024 * 1024 * 1024) == "1.00 TB")
}
