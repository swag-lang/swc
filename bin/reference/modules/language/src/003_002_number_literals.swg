#global private

/**
# Number Representations

Integers can be written in multiple formats: *decimal*, *hexadecimal*, or *binary*.
These representations allow you to express numbers in the format that best fits
your use case or domain requirements.
*/
#test
{
    const a: u32 = 123456         // Decimal format
    const b: u32 = 0xFFFF         // Hexadecimal, prefixed with '0x' (represents 65535)
    const c: u32 = 0b00001111     // Binary, prefixed with '0b' (represents 15)

    Swag.assert(a == 123456)
    Swag.assert(b == 65535)
    Swag.assert(c == 15)
}

/**
# Digit Separators

Numeric literals can use the underscore ('_') as a digit separator for better
readability. Separators do not affect the numeric value.
*/
#test
{
    const a: u32 = 123_456         // Decimal with separators
    const b: u32 = 0xF_F_F_F       // Hexadecimal with separators
    const c: u32 = 0b0000_1111     // Binary with separators

    Swag.assert(a == 123456)
    Swag.assert(b == 65535)
    Swag.assert(c == 15)
}

/**
# Default Integer Types

In Swag, hexadecimal or binary literals default to type 'u32' if the value fits
within 32 bits. If the literal exceeds 32 bits, it is automatically inferred as 'u64'.
Decimal literals prefer a signed integer type when no surrounding type is imposed.

A bare literal can still adapt to the type required by its context. Once a 'const' or
'let' declaration infers its type, using that name uses the inferred type: an unsigned
hexadecimal constant can therefore change the common type of a later arithmetic or bitwise
expression, even when a decimal constant with the same value would not.
*/
#test
{
    const a = 0xFF     // Fits in 32 bits → inferred as 'u32'
    #assert(#typeof(a) == u32)

    const b = 0xF_FFFFF_FFFFFF     // Exceeds 32 bits → inferred as 'u64'
    #assert(#typeof(b) == u64)

    const c = 0b00000001     // Within 32 bits → inferred as 'u32'
    #assert(#typeof(c) == u32)

    const d = 0b00000001_00000001_00000001_00000001_00000001     // Exceeds 32 bits → 'u64'
    #assert(#typeof(d) == u64)
}

#test
{
    const hexMask     = 0xF0
    const decimalMask = 240
    var value: s32 = 0x7F

    #assert(#typeof(hexMask) == u32)
    #assert(#typeof(decimalMask) == s32)
    #assert(#typeof(value & hexMask) == u32)
    #assert(#typeof(value & decimalMask) == s32)
    #assert(#typeof(value & 0xF0) == s32)
}

/**
# Booleans

A 'bool' type can hold either 'true' or 'false'. Since constants are known at compile
time, you can use '#assert' to verify their values during compilation.
*/
#test
{
    const a = true
    #assert(a == true)
    const b, c = false
    #assert(b == false)
    #assert(c == false)
}

/**
# Floating-Point Values

Floating-point literals use standard C-style notation. This makes them familiar and
easy to read for developers coming from C or C++ backgrounds.
*/
#test
{
    let a = 1.5
    Swag.assert(a == 1.5)
    #assert(#typeof(a) == f32)     // This value fits exactly in 'f32'

    let b = 0.11
    Swag.assert(b == 0.11)
    #assert(#typeof(b) == f64)

    let c = 15e2
    Swag.assert(c == 15e2)     // Equivalent to 1500

    let d = 15e+2
    Swag.assert(d == 15e2)

    let e = -1e-1
    Swag.assert(e == -0.1)
}

/**
# Default Floating-Point Type

Without a suffix or an imposed type, a floating-point literal becomes 'f32' when its
parsed value can be represented in 'f32' without further rounding, and 'f64' otherwise.
For example, '1.5' infers 'f32', while '0.1' infers 'f64'. This differs from C and C++,
where an unsuffixed floating-point literal has type 'double'.

Use a type annotation or a suffix when the width matters. An explicit 'f32' accepts
rounding to that width; an explicit 'f64' keeps that width even for an exact small value.
*/
#test
{
    let a = 1.5
    Swag.assert(a == 1.5)
    #assert(#typeof(a) == f32)
    #assert(#typeof(a) != f64)

    let b = 0.1
    #assert(#typeof(b) == f64)

    let c = 16777216.0
    let d = 16777217.0
    #assert(#typeof(c) == f32)
    #assert(#typeof(d) == f64)

    let rounded: f32 = 0.1
    #assert(#typeof(rounded) == f32)
}

/**
# Literal Suffix

You can specify the type of a literal explicitly by adding a **suffix** to it. This
is useful when a specific type is required, such as 'f64' or 'u8'.
*/
#test
{
    let a = 1.5'f64     // Explicitly declare 'a' as 'f64'
    Swag.assert(a == 1.5)
    Swag.assert(a == 1.5'f64)
    #assert(#typeof(a) == f64)

    let b = 10'u8     // Declare 'b' as 'u8'
    Swag.assert(b == 10)
    #assert(#typeof(b) == u8)

    let c = 1'u32     // Explicitly typed as 'u32'
    #assert(#typeof(c) == u32)
}
