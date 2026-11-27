namespace Swag
{
    // #########################################################
    // Numeric limits
    // #########################################################

    namespace S8
    {
        const Min = cast #bit (s8, 0x80)
        const Max = cast #bit (s8, 0x7F)
    }

    namespace S16
    {
        const Min = cast #bit (s16, 0x8000)
        const Max = cast #bit (s16, 0x7FFF)
    }

    namespace S32
    {
        const Min = cast #bit (s32, 0x80000000)
        const Max = cast #bit (s32, 0x7FFFFFFF)
    }

    namespace S64
    {
        const Min = cast #bit (s64, 0x80000000_00000000)
        const Max = cast #bit (s64, 0x7FFFFFFF_FFFFFFFF)
    }

    namespace U8
    {
        const Min = 0_u8        // Min 'u8' value
        const Max = 0xFF_u8     // Max 'u8' value
    }

    namespace U16
    {
        const Min = 0_u16
        const Max = 0xFFFF_u16
    }

    namespace U32
    {
        const Min = 0_u32
        const Max = 0xFFFFFFFF_u32
    }

    namespace U64
    {
        const Min = 0_u64
        const Max = 0xFFFFFFFF_FFFFFFFF_u64
    }

    namespace F32
    {
        const Min       = -3.40282346638528859812e+38_f32     // Most negative finite 'f32' value
        const Max       = 3.40282346638528859812e+38_f32      // Largest finite 'f32' value
        const MinNormal = 1.17549435082228750797e-38_f32      // Smallest positive normal 'f32' value
        const NaN       = cast #bit (f32, 0x7F800001)
        const Inf       = cast #bit (f32, 0x7F800000)
        const NegInf    = cast #bit (f32, 0xFF800000)
        const MantBits  = 23
        const ExpBits   = 8
        const Bias      = -127
    }

    namespace F64
    {
        const Min       = -1.79769313486231570815e+308_f64     // Most negative finite 'f64' value
        const Max       = 1.79769313486231570815e+308_f64      // Largest finite 'f64' value
        const MinNormal = 2.2250738585072014e-308_f64          // Smallest positive normal 'f64' value
        const NaN       = cast #bit (f64, 0x7FF8000000000001)
        const Inf       = cast #bit (f64, 0x7FF0000000000000)
        const NegInf    = cast #bit (f64, 0xFFF0000000000000)
        const MantBits  = 52
        const ExpBits   = 11
        const Bias      = -1023
    }
}
