#global internal

const A: s32 = 10
#assert(#typeof(A) == s32)
#assert(#typeof(A) != f32)

#assert(#typeof(10) == s32)
#assert(#typeof(10'u8) == u8)

#assert(#typeof(0xFF) == u32)
#assert(#typeof(0xFFFFFFFF) == u32)
#assert(#typeof(0xFFFFFFFFF) == u64)