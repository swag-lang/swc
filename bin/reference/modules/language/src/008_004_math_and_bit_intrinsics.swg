#global private

/**
# Integer Helpers

'@min', '@max', and '@abs' preserve the operand type. Bit intrinsics operate on
unsigned widths from 'u8' through 'u64'.
*/
#test
{
    @assert(@min(4's32, 9's32) == 4)
    @assert(@max(4's32, 9's32) == 9)
    @assert(@abs(-7's32) == 7)

    @assert(@bitcountnz(0b1011'u8) == 3)
    @assert(@bitcountlz(1'u32) == 31)
    @assert(@bitcounttz(0x10'u32) == 4)
}

/**
# Byte Order and Rotation

'@byteswap' reverses bytes within an integer. '@rol' and '@ror' rotate bits
without discarding those shifted past an edge.
*/
#test
{
    const Value = 0x01020304'u32

    @assert(@byteswap(Value) == 0x04030201)
    @assert(@rol(0x80000001'u32, 1) == 0x00000003)
    @assert(@ror(0x80000001'u32, 1) == 0xC0000000)
    @assert(@ror(@rol(Value, 7), 7) == Value)
}

/**
# Floating-Point Math

The compiler provides trigonometric, hyperbolic, exponential, logarithmic, and
rounding operations for 'f32' and 'f64'. Results keep the input precision.
*/
#test
{
    #assert(#typeof(@sqrt(9.0'f32)) == f32)
    #assert(#typeof(@sqrt(9.0'f64)) == f64)

    @assert(@sqrt(9.0'f32) == 3.0)
    @assert(@pow(2.0'f32, 3.0'f32) == 8.0)
    @assert(@floor(3.75'f32) == 3.0)
    @assert(@ceil(3.25'f32) == 4.0)
    @assert(@round(3.5'f32) == 4.0)
    @assert(@sin(0.0'f32) == 0.0)
}

/**
The complete family is indexed in the keyword chapter. Domain checks such as a
negative square root depend on the active safety and sanity configuration.
*/
