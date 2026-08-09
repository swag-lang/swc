#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertFormatString(value: const &String, expected: string)->bool
{
    let text = value.toString()
    return value == expected and
           @countof(value) == @countof(expected) and
           @countof(text) == @countof(expected) and
           Memory.compare(@dataof(text), @dataof(expected), @countof(expected)) == 0
}

func formatReferencedString(value: const &String)->String
{
    return Format.toString("%", value)
}

#test
{
    @assert(Format.countPercent("") == 0)
    @assert(Format.countPercent("%%") == 0)
    @assert(Format.countPercent("%/%%/%{X}") == 2)
}

#test
{
    let mixed = Format.toString("%% % %{X} %{D03}", "core", 255, 7)
    @assert(assertFormatString(mixed, "% core FF 007"))

    var replaced: String = "seed"
    Format.replaceString(&replaced, "%{02}:%{02}", 3, 9)
    @assert(assertFormatString(replaced, "03:09"))
}

#test
{
    let padded = Format.toString("%{04}", 7)
    @assert(assertFormatString(padded, "0007"))

    let forcedPositive = Format.toString("%{+04}", 7)
    @assert(assertFormatString(forcedPositive, "+007"))

    let forcedNegative = Format.toString("%{+04}", -7)
    @assert(assertFormatString(forcedNegative, "-007"))
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

    @assert(assertFormatString(direct.toString(), "literal variable true A"))
}

#test
{
    let value = String.from("referenced")
    @assert(assertFormatString(formatReferencedString(value), "referenced"))
}

// '%{#n}' targets an explicit 0-based argument, so translations can reorder arguments.
#test
{
    let swapped = Format.toString("%{#1} then %{#0}", "first", "second")
    @assert(assertFormatString(swapped, "second then first"))

    let repeated = Format.toString("%{#0} and %{#0} again", "twice")
    @assert(assertFormatString(repeated, "twice and twice again"))

    // An indexed placeholder carries a conversion format after ':' and leaves the
    // running position of plain '%' placeholders untouched.
    let mixed = Format.toString("% %{#2:X} %", "a", "b", 255)
    @assert(assertFormatString(mixed, "a FF b"))
}

// 'byteSize' scales through the 1024-based units and keeps three significant digits.
#test
{
    @assert(Format.byteSize(0) == "0 B")
    @assert(Format.byteSize(312) == "312 B")
    @assert(Format.byteSize(1023) == "1023 B")
    @assert(Format.byteSize(1024) == "1.00 KB")
    @assert(Format.byteSize(4200) == "4.10 KB")
    @assert(Format.byteSize(1024 * 1024) == "1.00 MB")
    @assert(Format.byteSize(14_050_000) == "13.4 MB")
    @assert(Format.byteSize(650 * 1024 * 1024) == "650 MB")
    @assert(Format.byteSize(1024'u64 * 1024 * 1024 * 1024) == "1.00 TB")
}
