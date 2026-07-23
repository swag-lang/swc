#global #if #command == Swag.CompilerCommand.Test
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
