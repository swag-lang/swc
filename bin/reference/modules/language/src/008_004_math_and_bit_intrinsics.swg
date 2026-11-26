#global private

/**
# Integer Helpers

'Swag.min', 'Swag.max', and 'Swag.abs' preserve the operand type. Bit intrinsics operate on
unsigned widths from 'u8' through '_u64'.
*/
#test
{
    Swag.require(Swag.min(4_s32, 9_s32) == 4)
    Swag.require(Swag.max(4_s32, 9_s32) == 9)
    Swag.require(Swag.abs(-7_s32) == 7)

    Swag.require(Swag.countOnes(0b1011_u8) == 3)
    Swag.require(Swag.leadingZeros(1_u32) == 31)
    Swag.require(Swag.trailingZeros(0x10_u32) == 4)
}

/**
# Wide Unsigned Multiplication

'Swag.mulWide' computes the exact product of two 'u64' values. It returns the low 64 bits
and writes the high 64 bits through the provided pointer. An overload adds two unsigned
64-bit words to the product before splitting it into halves.
*/
#test
{
    var high: u64
    let low = Swag.mulWide(0x8000000000000000'u64, 3'u64, &high)
    Swag.require(low == 0x8000000000000000'u64)
    Swag.require(high == 1)

    const Max = Swag.U64.Max
    let accumulated = Swag.mulWide(Max, Max, Max, Max, &high)
    Swag.require(accumulated == Max and high == Max)
}

/**
# Byte Order and Rotation

'Swag.byteSwap' reverses bytes within an integer. 'Swag.rol' and 'Swag.ror' rotate bits
without discarding those shifted past an edge.
*/
#test
{
    const Value = 0x01020304_u32

    Swag.require(Swag.byteSwap(Value) == 0x04030201)
    Swag.require(Swag.rol(0x80000001_u32, 1) == 0x00000003)
    Swag.require(Swag.ror(0x80000001_u32, 1) == 0xC0000000)
    Swag.require(Swag.ror(Swag.rol(Value, 7), 7) == Value)
}

/**
# Floating-Point Math

The compiler provides trigonometric, hyperbolic, exponential, logarithmic, and
rounding operations for 'f32' and 'f64'. Results keep the input precision.
*/
#test
{
    #assert(#typeof(Swag.sqrt(9.0_f32)) == f32)
    #assert(#typeof(Swag.sqrt(9.0_f64)) == f64)

    Swag.require(Swag.sqrt(9.0_f32) == 3.0)
    Swag.require(Swag.pow(2.0_f32, 3.0_f32) == 8.0)
    Swag.require(Swag.floor(3.75_f32) == 3.0)
    Swag.require(Swag.ceil(3.25_f32) == 4.0)
    Swag.require(Swag.round(3.5_f32) == 4.0)
    Swag.require(Swag.sin(0.0_f32) == 0.0)
}

/**
The complete family is indexed in the keyword chapter. Domain checks such as a
negative square root depend on the active safety and sanity configuration.
*/
