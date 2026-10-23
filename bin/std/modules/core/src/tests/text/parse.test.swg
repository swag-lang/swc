#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// A lone sign is incomplete, even when the view it comes from continues with a digit.
#test
{
    let text = "-5"
    var signOnlyOutcome: Swag.Error
    discard catch StrConv.parseS64(text[until 1]) as &signOnlyOutcome
    let signOnly = signOnlyOutcome.value()
    Swag.assert(signOnly != null)

    let {value, eat, _} = expect StrConv.parseS64(text)
    Swag.assert(value == -5 and eat == 2)

    var floatSignOnlyOutcome: Swag.Error
    discard catch StrConv.parseF64(text[until 1]) as &floatSignOnlyOutcome
    let floatSignOnly = floatSignOnlyOutcome.value()
    Swag.assert(floatSignOnly != null)
}

// An empty text is not a number, whatever its type.
#test
{
    var emptyIntOutcome: Swag.Error
    discard catch StrConv.toS32("") as &emptyIntOutcome
    let emptyInt = emptyIntOutcome.value()
    var emptyFloatOutcome: Swag.Error
    discard catch StrConv.toF64("") as &emptyFloatOutcome
    let emptyFloat = emptyFloatOutcome.value()
    Swag.assert(emptyInt != null)
    Swag.assert(emptyFloat != null)
    Swag.assert(expect StrConv.toF64("2.5") == 2.5)
}

// A backslash escapes the next character, inside or outside quotes.
#test
{
    let {value, eat} = expect StrConv.parseString("\"a\\tb\\\"c\" tail")
    Swag.assert(value == "a\tb\"c")
    Swag.assert(eat == 9)

    let plain = expect StrConv.parseString("x\"y")
    Swag.assert(plain.value == "x\"y")
}

// Superscripts and fractions are Latin-1 numbers but not decimal digits.
#test
{
    Swag.assert(Latin1.isDigit('7'))
    Swag.assert(not Latin1.isDigit(0xB2))
    Swag.assert(Latin1.isNumber(0xB2))
    Swag.assert(not Unicode.isDigit('²'))
    Swag.assert(Unicode.isNumber('¾'))
}

// An f32 below the smallest normal value is a subnormal, not an overflow: it reads back exactly.
#test
{
    let subnormal = expect StrConv.parseF32("9.999999350456404e-39")
    Swag.assert(cast #bit (u32, subnormal.value) == 0x6CE3EE and not subnormal.ovf)
    let smallest = expect StrConv.parseF32("1.401298464324817e-45")
    Swag.assert(cast #bit (u32, smallest.value) == 1 and not smallest.ovf)
    let negative = expect StrConv.parseF32("-1e-40")
    Swag.assert(negative.value < 0 and negative.value > -Swag.F32.MinNormal)
    let zero = expect StrConv.parseF32("1e-50")
    Swag.assert(zero.value == 0)
    let huge = expect StrConv.parseF32("1e39")
    Swag.assert(huge.value == Swag.F32.Max and huge.ovf)
}

func(T) checkCompleteNumberConversion(overflowText: string)
{
    let value = expect StrConv.toNum'T("12")
    Swag.assert(value == cast(T, 12))

    var trailingOutcome: Swag.Error
    discard catch StrConv.toNum'T("12x") as &trailingOutcome
    let trailing = trailingOutcome.value()
    Swag.assert(trailing is Errors.SyntaxError)

    var overflowOutcome: Swag.Error
    discard catch StrConv.toNum'T(overflowText) as &overflowOutcome
    let overflow = overflowOutcome.value()
    Swag.assert(overflow is Errors.OverflowError)

    // Overflow keeps priority when unconsumed text follows the number too.
    var overflowWithSuffix = String.from(overflowText)
    overflowWithSuffix.append("x")
    var bothOutcome: Swag.Error
    discard catch StrConv.toNum'T(overflowWithSuffix.toString()) as &bothOutcome
    let both = bothOutcome.value()
    Swag.assert(both is Errors.OverflowError)
}

#test
{
    checkCompleteNumberConversion's8("128")
    checkCompleteNumberConversion's16("32768")
    checkCompleteNumberConversion's32("2147483648")
    checkCompleteNumberConversion's64("9223372036854775808")
    checkCompleteNumberConversion'u8("256")
    checkCompleteNumberConversion'u16("65536")
    checkCompleteNumberConversion'u32("4294967296")
    checkCompleteNumberConversion'u64("18446744073709551616")
    checkCompleteNumberConversion'f32("1e39")
    checkCompleteNumberConversion'f64("1e400")
}

// Decimal accumulation detects overflow before multiplication, even when wrapping would increase
// the intermediate value and leave an apparently representable result.
#test
{
    let unsigned = expect StrConv.parseU64("30000000000000000000")
    Swag.assert(unsigned.ovf and unsigned.eat == 20)

    let positive = expect StrConv.parseS64("25000000000000000000")
    Swag.assert(positive.ovf and positive.eat == 20)

    let negative = expect StrConv.parseS64("-25000000000000000000")
    Swag.assert(negative.ovf and negative.eat == 21)
}
