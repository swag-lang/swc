#global private

/**
# Integer Helpers

'Swag.min', 'Swag.max', and 'Swag.abs' preserve the operand type. Bit intrinsics operate on
unsigned widths from 'u8' through 'u64'.
*/
#test
{
    Swag.assert(Swag.min(4's32, 9's32) == 4)
    Swag.assert(Swag.max(4's32, 9's32) == 9)
    Swag.assert(Swag.abs(-7's32) == 7)

    Swag.assert(Swag.bitCountNz(0b1011'u8) == 3)
    Swag.assert(Swag.bitCountLz(1'u32) == 31)
    Swag.assert(Swag.bitCountTz(0x10'u32) == 4)
}

/**
# Byte Order and Rotation

'Swag.byteSwap' reverses bytes within an integer. 'Swag.rol' and 'Swag.ror' rotate bits
without discarding those shifted past an edge.
*/
#test
{
    const Value = 0x01020304'u32

    Swag.assert(Swag.byteSwap(Value) == 0x04030201)
    Swag.assert(Swag.rol(0x80000001'u32, 1) == 0x00000003)
    Swag.assert(Swag.ror(0x80000001'u32, 1) == 0xC0000000)
    Swag.assert(Swag.ror(Swag.rol(Value, 7), 7) == Value)
}

/**
# Floating-Point Math

The compiler provides trigonometric, hyperbolic, exponential, logarithmic, and
rounding operations for 'f32' and 'f64'. Results keep the input precision.
*/
#test
{
    #assert(#typeof(Swag.sqrt(9.0'f32)) == f32)
    #assert(#typeof(Swag.sqrt(9.0'f64)) == f64)

    Swag.assert(Swag.sqrt(9.0'f32) == 3.0)
    Swag.assert(Swag.pow(2.0'f32, 3.0'f32) == 8.0)
    Swag.assert(Swag.floor(3.75'f32) == 3.0)
    Swag.assert(Swag.ceil(3.25'f32) == 4.0)
    Swag.assert(Swag.round(3.5'f32) == 4.0)
    Swag.assert(Swag.sin(0.0'f32) == 0.0)
}

/**
The complete family is indexed in the keyword chapter. Domain checks such as a
negative square root depend on the active safety and sanity configuration.
*/
