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
