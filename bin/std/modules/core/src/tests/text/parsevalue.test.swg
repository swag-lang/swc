#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func checkParseValue(addr: *void, type: typeinfo, text: string) fail { discard try StrConv.parseValue(addr, type, text) }

struct ParseInner
{
    x, y: f32
    w, h: f32
}

struct ParseOuter
{
    rect:   ParseInner
    corner: f32
    keep = true
}

// A struct decodes as a brace-enclosed field list in declaration order, nesting included.
#test
{
    var value: ParseOuter
    let rest = expect StrConv.parseValue(&value, #typeof(ParseOuter), "{{1 29 27 27} 13 false} tail")
    Swag.assert(value.rect.x == 1)
    Swag.assert(value.rect.y == 29)
    Swag.assert(value.rect.w == 27)
    Swag.assert(value.rect.h == 27)
    Swag.assert(value.corner == 13)
    Swag.assert(not value.keep)
    Swag.assert(Tokenize.eatSpaces(rest) == "tail")
}

// Commas between field values are accepted, and an early '}' keeps the remaining defaults.
#test
{
    var value: ParseOuter
    discard expect StrConv.parseValue(&value, #typeof(ParseOuter), "{{1, 2, 3, 4} 5}")
    Swag.assert(value.rect.h == 4)
    Swag.assert(value.corner == 5)
    Swag.assert(value.keep)
}

// A missing opening or closing brace is a decoding error.
#test
{
    var value: ParseOuter
    catch checkParseValue(&value, #typeof(ParseOuter), "1 2 3") as err
    Swag.assert(err != null)
    Swag.assert(err is Errors.InvalidFormatError)

    catch checkParseValue(&value, #typeof(ParseOuter), "{{1 2 3 4} 5") as err2
    Swag.assert(err2 != null)
    Swag.assert(err2 is Errors.InvalidFormatError)
}

// A struct field parses from a tweak line, which is what theme sheets rely on.
#test
{
    struct TweakRects
    {
        first:  ParseOuter
        second: ParseOuter
    }

    var rects: TweakRects
    var tweak: File.TweakFile
    tweak.registerFolder'TweakRects(&rects)

    discard expect tweak.parse("/TweakRects\nfirst {{1 29 27 27} 0}\nsecond $first\n")
    Swag.assert(rects.first.rect.y == 29)
    Swag.assert(rects.first.corner == 0)
    Swag.assert(rects.second.rect.y == 29)
}

func(T) expectParsedNumber(text: string, expected: T)
{
    var value: T
    let rest = expect StrConv.parseValue(&value, #typeof(T), text)
    Swag.assert(value == expected)
    Swag.assert(rest == " tail")
}

// Every numeric kind writes its own representation and leaves the trailing text untouched.
#test
{
    expectParsedNumber("-128 tail", Swag.S8.Min)
    expectParsedNumber("-32768 tail", Swag.S16.Min)
    expectParsedNumber("-2147483648 tail", Swag.S32.Min)
    expectParsedNumber("-9223372036854775808 tail", Swag.S64.Min)
    expectParsedNumber("255 tail", Swag.U8.Max)
    expectParsedNumber("65535 tail", Swag.U16.Max)
    expectParsedNumber("4294967295 tail", Swag.U32.Max)
    expectParsedNumber("18446744073709551615 tail", Swag.U64.Max)
    expectParsedNumber("1.25 tail", 1.25'f32)
    expectParsedNumber("-2.5 tail", -2.5'f64)
}

func(T) expectNumericOverflow(text: string, initial: T)
{
    var value = initial
    catch checkParseValue(&value, #typeof(T), text) as error
    Swag.assert(error is Errors.OverflowError)
    Swag.assert(value == initial)
}

// Failed numeric conversion preserves an already initialized destination.
#test
{
    expectNumericOverflow("128", 7's8)
    expectNumericOverflow("32768", 7's16)
    expectNumericOverflow("2147483648", 7's32)
    expectNumericOverflow("9223372036854775808", 7's64)
    expectNumericOverflow("256", 7'u8)
    expectNumericOverflow("65536", 7'u16)
    expectNumericOverflow("4294967296", 7'u32)
    expectNumericOverflow("18446744073709551616", 7'u64)
    expectNumericOverflow("1e39", 7'f32)
    expectNumericOverflow("1e309", 7'f64)
}
