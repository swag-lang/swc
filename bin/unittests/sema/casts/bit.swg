#global private

#[Swag.Strict]
alias BitCastStrictU32 = u32

#[Swag.Strict]
alias BitCastStrictF32 = f32

#assert(cast #bit (u32, 1.0_f32) == 0x3F800000)
#assert(cast #bit (u32, 0.0_f32) == 0x00000000)
#assert(cast #bit (u32, -1.0_f32) == 0xBF800000)
#assert(cast #bit (u32, -0.0_f32) == 0x80000000)

#assert(cast #bit (u64, 1.0_f64) == 0x3FF0000000000000)
#assert(cast #bit (u64, 0.0_f64) == 0x0000000000000000)
#assert(cast #bit (u64, -1.0_f64) == 0xBFF0000000000000)
#assert(cast #bit (u64, -0.0_f64) == 0x8000000000000000)

#assert(cast #bit (u32, 0_u32) == 0)
#assert(cast #bit (u32, 1_u32) == 1)
#assert(cast #bit (u32, 0xFFFFFFFF_u32) == 0xFFFFFFFF)
#assert(cast #bit (u32, 0x00000000_u32) == 0x00000000)
#assert(cast #bit (u32, 0x80000000_u32) == 0x80000000)

#assert(cast #bit (s32, 2147483647_s32) == 2147483647)
#assert(cast #bit (s32, -1_s32) == -1)
#assert(cast #bit (s32, -2147483648_s32) == -2147483648)

#assert(cast #bit (f32, 0x3F800000_u32) == 1.0_f32)
#assert(cast #bit (f32, 0xBF800000_u32) == -1.0_f32)
#assert(cast #bit (f32, 0x00000000_u32) == 0.0_f32)
#assert(cast #bit (f32, 0x80000000_u32) == -0.0_f32)
#assert(cast #bit (f32, 0x3F000000_u32) == 0.5_f32)
#assert(cast #bit (f32, 0x40000000_u32) == 2.0_f32)

#assert(cast #bit (f64, 0x3FF0000000000000_u64) == 1.0_f64)
#assert(cast #bit (f64, 0xBFF0000000000000_u64) == -1.0_f64)
#assert(cast #bit (f64, 0x0000000000000000_u64) == 0.0_f64)
#assert(cast #bit (f64, 0x8000000000000000_u64) == -0.0_f64)
#assert(cast #bit (f64, 0x3FE0000000000000_u64) == 0.5_f64)
#assert(cast #bit (f64, 0x4000000000000000_u64) == 2.0_f64)

#assert(cast #bit (s32, -1.0_f32) == -1082130432)
#assert(cast #bit (u32, -1.0_f32) == 0xBF800000)
#assert(cast #bit (u64, -1.0_f64) == 0xBFF0000000000000)

#assert(cast #bit (f32, -1082130432_s32) == -1.0_f32)
#assert(cast #bit (u32, cast #bit (f32, 0x80000000_u32)) == 0x80000000)
#assert(cast #bit (u64, cast #bit (f64, 0x8000000000000000_u64)) == 0x8000000000000000)
#assert(cast #bit (u32, -1_s32) == 0xFFFFFFFF)
#assert(cast #bit (s32, 0xFFFFFFFF_u32) == -1)
#assert(cast #bit (u32, cast #bit (s32, -1_s32)) == 0xFFFFFFFF)
#assert(cast #bit (s32, cast #bit (u32, 0xFFFFFFFF_u32)) == -1)
#assert(cast #bit (u32, 0x123456789ABCDEF0_u64) == 0x9ABCDEF0)
#assert(cast #bit (u8, 0x1234_u16) == 0x34)
#assert(cast #bit (u64, -1_s8) == 0xFFFFFFFFFFFFFFFF)
#assert(cast #bit (u32, -11) == 0xFFFF_FFF5)
#assert(cast #bit (u64, -11) == 0xFFFF_FFFF_FFFF_FFF5)
#assert(cast #bit (u32, cast #bit (f32, -11)) == cast #bit (u32, cast #bit (f32, -11_s32)))
#assert(cast #bit (u64, cast #bit (f64, -11)) == cast #bit (u64, cast #bit (f64, -11_s64)))

#assert(cast #bit (u32, cast #bit (f32, 0x7F800000_u32)) == 0x7F800000)
#assert(cast #bit (u32, cast #bit (f32, 0xFF800000_u32)) == 0xFF800000)
#assert(cast #bit (u32, cast #bit (f32, 0x7FC00001_u32)) == 0x7FC00001)
#assert(cast #bit (u32, cast #bit (f32, 0x7FA00000_u32)) == 0x7FA00000)
#assert(cast #bit (u64, cast #bit (f64, 0x7FF0000000000000_u64)) == 0x7FF0000000000000)
#assert(cast #bit (u64, cast #bit (f64, 0xFFF0000000000000_u64)) == 0xFFF0000000000000)
#assert(cast #bit (u64, cast #bit (f64, 0x7FF8000000000001_u64)) == 0x7FF8000000000001)
#assert(cast #bit (u64, cast #bit (f64, 0x7FF4000000000000_u64)) == 0x7FF4000000000000)

#assert(cast #bit (rune, 65_u32) == 'A')

const StrictBits  = cast #bit (BitCastStrictU32, cast(BitCastStrictF32, 1.0_f32))
const StrictFloat = cast #bit (BitCastStrictF32, cast(BitCastStrictU32, 0x40000000_u32))
#assert(#typeof(StrictBits) == BitCastStrictU32)
#assert(#typeof(StrictFloat) == BitCastStrictF32)
#assert(StrictBits == cast(BitCastStrictU32, 0x3F800000_u32))
#assert(StrictFloat == cast(BitCastStrictF32, 2.0_f32))

const NaN0    = cast #bit (f32, 0x7F800001)
const Inf0    = cast #bit (f32, 0x7F800000)
const NegInf0 = cast #bit (f32, 0xFF800000)
const NaN1    = cast #bit (f64, 0x7FF8000000000001)
const Inf1    = cast #bit (f64, 0x7FF0000000000000)
const NegInf1 = cast #bit (f64, 0xFFF0000000000000)

const A = cast #bit (f32, -666)
