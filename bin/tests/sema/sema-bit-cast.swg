#assert(cast #bit (u64) -1.0'f64 == 0xBFF0000000000000)

#assert(cast #bit (u32) -1.0'f32 == 0xBF800000)
#assert(cast #bit (u32) 1.0'f32 == 0x3F800000)
#assert(cast #bit (u32) 0.0'f32 == 0x00000000)
#assert(cast #bit (u64) 1.0'f64 == 0x3FF0000000000000)
#assert(cast #bit (u64) 0.0'f64 == 0x0000000000000000)
#assert(cast #bit (u32) 0'u32 == 0)
#assert(cast #bit (u32) 1'u32 == 1)
#assert(cast #bit (u32) 0xFFFFFFFF'u32 == 0xFFFFFFFF)
#assert(cast #bit (s32) -1's32 == -1)
#assert(cast #bit (s32) 2147483647's32 == 2147483647)
#assert(cast #bit (s32) -2147483648's32 == -2147483648)
#assert(cast #bit (f32) 0x3F800000'u32 == 1.0'f32)
#assert(cast #bit (f32) 0xBF800000'u32 == -1.0'f32)
#assert(cast #bit (f32) 0x00000000'u32 == 0.0'f32)
#assert(cast #bit (f64) 0x3FF0000000000000'u64 == 1.0'f64)
#assert(cast #bit (f64) 0xBFF0000000000000'u64 == -1.0'f64)

//#assert(cast #bit (s32) -1.0'f32 == -1074790400)

#assert(cast #bit (u32) -1.0'f64 == 0xBF800000)         // swc-expected-error {{sema_err_bit_cast_size}}
#assert(cast #bit (bool) -1.0'f64 == 0xBF800000)        // swc-expected-error {{sema_err_bit_cast_invalid_type}}
