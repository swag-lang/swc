#global private

const A: s32 = 10
#assert(#typeof(A) == s32)
#assert(#typeof(A) != f32)

#assert(#typeof(10) == s32)
#assert(#typeof(-10) == s32)
#assert(#typeof(0) == s32)
#assert(#typeof(10_s8) == s8)
#assert(#typeof(10_s16) == s16)
#assert(#typeof(10_s32) == s32)
#assert(#typeof(10_s64) == s64)
#assert(#typeof(10_u8) == u8)
#assert(#typeof(10_u16) == u16)
#assert(#typeof(10_u32) == u32)
#assert(#typeof(10_u64) == u64)

#assert(#typeof(0xFF) == u32)
#assert(#typeof(0xFFFFFFFF) == u32)
#assert(#typeof(0x1_0000_0000) == u64)
#assert(#typeof(0xFFFFFFFFF) == u64)
#assert(#typeof(0b1111) == u32)
#assert(#typeof(0b1111_1111_1111_1111_1111_1111_1111_1111) == u32)
#assert(#typeof(0b1_0000_0000_0000_0000_0000_0000_0000_0000_0000) == u64)

#assert(#typeof(1.0) == f32)
#assert(#typeof(-1.0) == f32)
#assert(#typeof(1.0_f32) == f32)
#assert(#typeof(-1.0_f32) == f32)
#assert(#typeof(1.0_f64) == f64)
#assert(#typeof(-1.0_f64) == f64)

#assert(#typeof(1.0 + 5_s8) == f32)
#assert(#typeof(1.0 + 5_s16) == f32)
#assert(#typeof(1.0 + 5_s32) == f32)
#assert(#typeof(1.0 + 5_s64) == f64)
#assert(#typeof(1.0 + 5_u32) == f32)
#assert(#typeof(1.0 + 5_u64) == f64)
#assert(#typeof(1.0_f32 + 5_s64) == f64)
#assert(#typeof(1.0_f32 + 5_u64) == f64)
#assert(#typeof(1.0_f64 + 5_s32) == f64)
#assert(#typeof(1.0_f64 + 5_u32) == f64)

#assert(#typeof(10_u8 + 20_u16) == u16)
#assert(#typeof(10_u8 + 20_u32) == u32)
#assert(#typeof(10_u8 + 20_u64) == u64)
#assert(#typeof(10_u16 + 20_u32) == u32)
#assert(#typeof(10_u16 + 20_u64) == u64)
#assert(#typeof(10_u32 + 20_u64) == u64)

#assert(#typeof(10_u8 + 20_s8) == u8)
#assert(#typeof(10_u16 + 20_s16) == u16)
#assert(#typeof(10_u32 + 20_s32) == u32)
#assert(#typeof(10_u64 + 20_s64) == u64)

#assert(#typeof(10_u8 + 20_s16) == s16)
#assert(#typeof(10_u8 + 20_s32) == s32)
#assert(#typeof(10_u8 + 20_s64) == s64)

#assert(#typeof(10_u16 + 20_s8) == u16)
#assert(#typeof(10_u16 + 20_s32) == s32)
#assert(#typeof(10_u16 + 20_s64) == s64)

#assert(#typeof(10_u32 + 20_s8) == u32)
#assert(#typeof(10_u32 + 20_s16) == u32)
#assert(#typeof(10_u32 + 20_s64) == s64)

#assert(#typeof(10_u64 + 20_s8) == u64)
#assert(#typeof(10_u64 + 20_s16) == u64)
#assert(#typeof(10_u64 + 20_s32) == u64)

#assert(#typeof(10_s8 + 20_s16) == s16)
#assert(#typeof(10_s8 + 20_s32) == s32)
#assert(#typeof(10_s8 + 20_s64) == s64)

#assert(#typeof(10_s16 + 20_s32) == s32)
#assert(#typeof(10_s16 + 20_s64) == s64)
#assert(#typeof(10_s32 + 20_s64) == s64)

#assert(#typeof(0_s8 + 1_s8) == s8)
#assert(#typeof(0_s16 + 1_s16) == s16)
#assert(#typeof(0_s32 + 1_s32) == s32)
#assert(#typeof(0_s64 + 1_s64) == s64)

#assert(#typeof(0_u8 + 1_u8) == u8)
#assert(#typeof(0_u16 + 1_u16) == u16)
#assert(#typeof(0_u32 + 1_u32) == u32)
#assert(#typeof(0_u64 + 1_u64) == u64)

#assert(#typeof(1 + 1_u8) == u32)
#assert(#typeof(1 + 1_u16) == u32)
#assert(#typeof(1 + 1_u32) == u32)
#assert(#typeof(1 + 1_u64) == u64)

#assert(#typeof(1 + 1_s8) == s32)
#assert(#typeof(1 + 1_s16) == s32)
#assert(#typeof(1 + 1_s32) == s32)
#assert(#typeof(1 + 1_s64) == s64)

#assert(#typeof(2147483647) == s32)
#assert(#typeof(2147483648) == s64)

#assert(#typeof(256 + 1_u8) == u32)
#assert(#typeof(65536 + 1_u16) == u32)
#assert(#typeof(4294967296 + 1_u32) == u64)
#assert(#typeof(128 + 1_s8) == s32)
#assert(#typeof(32768 + 1_s16) == s32)
#assert(#typeof(2147483648 + 1_s32) == s64)
#assert(#typeof(255 + 1_s8) == s32)
#assert(#typeof(65535 + 1_s16) == s32)
#assert(#typeof(4294967295 + 1_s32) == s64)
#assert(#typeof(0x1FF + 1_u8) == u32)
#assert(#typeof(0x1_0000 + 1_u16) == u32)
#assert(#typeof(0b1_0000_0000 + 1_u8) == u32)

const OverflowU8  = -1 + 1_u8
const OverflowU16 = -1 + 1_u16
