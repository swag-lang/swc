#global fileprivate // swc-option suite-test

const TypedValue: s32 = 10

#assert(#typeof(TypedValue) == s32)
#assert(#typeof(10) == s8)
#assert(#typeof(-10) == s8)
#assert(#typeof(0xFF) == u8)
#assert(#typeof(0x1_0000) == u32)
#assert(#typeof(1.0) == f32)
#assert(#typeof(1.0'f64) == f64)
#assert(#typeof(10'u8 + 20'u16) == u16)
#assert(#typeof(10'u8 + 20's16) == s16)
#assert(#typeof(10's16 + 20's64) == s64)
#assert(#typeof(1 + 1'u32) == u32)
#assert(#typeof(1 + 1's64) == s64)
#assert(#typeof(cast(*u8) null) == *u8)
#assert(#typeof(true) == bool)
#assert(#typeof("x") == string)

#test
{
    var local = 1 + 1'u16
    var ptr = cast(*u8) null

    #assert(#typeof(local) == u16)
    #assert(#typeof(ptr) == *u8)

    @assert(local == 2'u16)
    @assert(ptr == null)
}
