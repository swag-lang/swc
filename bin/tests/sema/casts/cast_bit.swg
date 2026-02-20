#global internal

#assert(cast #bit (u32) 1.0'f32 == 0x3F800000)
#assert(cast #bit (u32) 0.0'f32 == 0x00000000)
#assert(cast #bit (u32) -1.0'f32 == 0xBF800000)
#assert(cast #bit (u32) -0.0'f32 == 0x80000000)

#assert(cast #bit (u64) 1.0'f64 == 0x3FF0000000000000)
#assert(cast #bit (u64) 0.0'f64 == 0x0000000000000000)
#assert(cast #bit (u64) -1.0'f64 == 0xBFF0000000000000)
#assert(cast #bit (u64) -0.0'f64 == 0x8000000000000000)

#assert(cast #bit (u32) 0'u32 == 0)
#assert(cast #bit (u32) 1'u32 == 1)
#assert(cast #bit (u32) 0xFFFFFFFF'u32 == 0xFFFFFFFF)
#assert(cast #bit (u32) 0x00000000'u32 == 0x00000000)
#assert(cast #bit (u32) 0x80000000'u32 == 0x80000000)

#assert(cast #bit (s32) 2147483647's32 == 2147483647)
#assert(cast #bit (s32) -1's32 == -1)
#assert(cast #bit (s32) -2147483648's32 == -2147483648)

#assert(cast #bit (f32) 0x3F800000'u32 == 1.0'f32)
#assert(cast #bit (f32) 0xBF800000'u32 == -1.0'f32)
#assert(cast #bit (f32) 0x00000000'u32 == 0.0'f32)
#assert(cast #bit (f32) 0x80000000'u32 == -0.0'f32)
#assert(cast #bit (f32) 0x3F000000'u32 == 0.5'f32)
#assert(cast #bit (f32) 0x40000000'u32 == 2.0'f32)

#assert(cast #bit (f64) 0x3FF0000000000000'u64 == 1.0'f64)
#assert(cast #bit (f64) 0xBFF0000000000000'u64 == -1.0'f64)
#assert(cast #bit (f64) 0x0000000000000000'u64 == 0.0'f64)
#assert(cast #bit (f64) 0x8000000000000000'u64 == -0.0'f64)
#assert(cast #bit (f64) 0x3FE0000000000000'u64 == 0.5'f64)
#assert(cast #bit (f64) 0x4000000000000000'u64 == 2.0'f64)

#assert(cast #bit (s32) -1.0'f32 == -1082130432)
#assert(cast #bit (u32) -1.0'f32 == 0xBF800000)
#assert(cast #bit (u64) -1.0'f64 == 0xBFF0000000000000)

#assert(cast #bit (f32) -1082130432's32 == -1.0'f32)
#assert(cast #bit (u32) (cast #bit (f32) 0x80000000'u32) == 0x80000000)
#assert(cast #bit (u64) (cast #bit (f64) 0x8000000000000000'u64) == 0x8000000000000000)
#assert(cast #bit (u32) -1's32 == 0xFFFFFFFF)
#assert(cast #bit (s32) 0xFFFFFFFF'u32 == -1)
#assert(cast #bit (u32) (cast #bit (s32) -1's32) == 0xFFFFFFFF)
#assert(cast #bit (s32) (cast #bit (u32) 0xFFFFFFFF'u32) == -1)

#assert(cast #bit (u32) (cast #bit (f32) 0x7F800000'u32) == 0x7F800000)
#assert(cast #bit (u32) (cast #bit (f32) 0xFF800000'u32) == 0xFF800000)
#assert(cast #bit (u32) (cast #bit (f32) 0x7FC00001'u32) == 0x7FC00001)
#assert(cast #bit (u32) (cast #bit (f32) 0x7FA00000'u32) == 0x7FA00000)
#assert(cast #bit (u64) (cast #bit (f64) 0x7FF0000000000000'u64) == 0x7FF0000000000000)
#assert(cast #bit (u64) (cast #bit (f64) 0xFFF0000000000000'u64) == 0xFFF0000000000000)
#assert(cast #bit (u64) (cast #bit (f64) 0x7FF8000000000001'u64) == 0x7FF8000000000001)
#assert(cast #bit (u64) (cast #bit (f64) 0x7FF4000000000000'u64) == 0x7FF4000000000000)

#assert(cast #bit (u64) 1.0'f32 == 0)                   // swc-expected-error {{sema_err_bit_cast_size}}
#assert(cast #bit (f32) 1.0'f64 == 0.0'f32)             // swc-expected-error {{sema_err_bit_cast_size}}
#assert(cast #bit (u32) 1'u64 == 0)                     // swc-expected-error {{sema_err_bit_cast_size}}
#assert(cast #bit (u32) -1.0'f64 == 0xBF800000)         // swc-expected-error {{sema_err_bit_cast_size}}
#assert(cast #bit (bool) -1.0'f64 == 0xBF800000)        // swc-expected-error {{sema_err_bit_cast_invalid_type}}
#assert(cast #bit (bool) 1'u8 == true)                  // swc-expected-error {{sema_err_bit_cast_invalid_type}}

#assert(cast #bit (rune) 65'u32 == 'A')

const NaN0    = cast #bit (f32) 0x7F800001
const Inf0    = cast #bit (f32) 0x7F800000
const NegInf0 = cast #bit (f32) 0xFF800000
const NaN1    = cast #bit (f64) 0x7ff8000000000001
const Inf1    = cast #bit (f64) 0x7ff0000000000000
const NegInf1 = cast #bit (f64) 0xfff0000000000000

const A = cast #bit (f32) -666
