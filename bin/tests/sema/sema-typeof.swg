#global internal

const A: s32 = 10
#assert(#typeof(A) == s32)
#assert(#typeof(A) != f32)

#assert(#typeof(10) == s32)
#assert(#typeof(10'u8) == u8)

#assert(#typeof(0xFF) == u32)
#assert(#typeof(0xFFFFFFFF) == u32)
#assert(#typeof(0xFFFFFFFFF) == u64)

#assert(#typeof(1.0) == f32)
#assert(#typeof(1.0'f32) == f32)
#assert(#typeof(1.0'f64) == f64)

#assert(#typeof(1.0 + 5's64) == f64)
#assert(#typeof(1.0 + 5's32) == f32)
#assert(#typeof(1.0'f64 + 5's32) == f64)
#assert(#typeof(1.0 + 5'u64) == f64)
#assert(#typeof(10'u8 + 20'u16) == u16)
#assert(#typeof(10's8 + 20's16) == s16)
#assert(#typeof(0's8 + 1's8) == s8)
#assert(#typeof(0'u8 + 1'u8) == u8)
#assert(#typeof(1 + 1'u8) == u8)

#assert(#typeof(10'u8 + 20's8) == s8)
#assert(#typeof(10'u8 + 20's16) == s16)
#assert(#typeof(10'u16 + 20's8) == u16)
#assert(#typeof(10'u32 + 20's8) == u32)