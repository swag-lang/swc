#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// A lone sign is incomplete, even when the view it comes from continues with a digit.
#test
{
    let text = "-5"
    discard catch StrConv.parseS64(text[until 1]) as signOnly
    Swag.assert(signOnly != null)

    let {value, eat, ?} = expect StrConv.parseS64(text)
    Swag.assert(value == -5 and eat == 2)

    discard catch StrConv.parseF64(text[until 1]) as floatSignOnly
    Swag.assert(floatSignOnly != null)
}

// An empty text is not a number, whatever its type.
#test
{
    discard catch StrConv.toS32("") as emptyInt
    discard catch StrConv.toF64("") as emptyFloat
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
    Swag.assert(cast #bit (u32) subnormal.value == 0x6CE3EE and not subnormal.ovf)
    let smallest = expect StrConv.parseF32("1.401298464324817e-45")
    Swag.assert(cast #bit (u32) smallest.value == 1 and not smallest.ovf)
    let negative = expect StrConv.parseF32("-1e-40")
    Swag.assert(negative.value < 0 and negative.value > -Swag.F32.Min)
    let zero = expect StrConv.parseF32("1e-50")
    Swag.assert(zero.value == 0)
    let huge = expect StrConv.parseF32("1e39")
    Swag.assert(huge.value == Swag.F32.Max and huge.ovf)
}
