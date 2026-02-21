#global internal

#test
{
    const A: any = 1's8
    #assert(#typeof(A) == any)
    @assert(@kindof(A) == s8)
    @assert(cast(s8) A == 1's8)
}

#test
{
    const A: any = 2's16
    #assert(#typeof(A) == any)
    @assert(@kindof(A) == s16)
    @assert(cast(s16) A == 2's16)
}

#test
{
    const A: any = 3's32
    #assert(#typeof(A) == any)
    @assert(@kindof(A) == s32)
    @assert(cast(s32) A == 3's32)
}

#test
{
    const A: any = 4's64
    #assert(#typeof(A) == any)
    @assert(@kindof(A) == s64)
    @assert(cast(s64) A == 4's64)
}

#test
{
    const A: any = 5'u8
    #assert(#typeof(A) == any)
    @assert(@kindof(A) == u8)
    @assert(cast(u8) A == 5'u8)
}

#test
{
    const A: any = 6'u16
    #assert(#typeof(A) == any)
    @assert(@kindof(A) == u16)
    @assert(cast(u16) A == 6'u16)
}

#test
{
    const A: any = 7'u32
    #assert(#typeof(A) == any)
    @assert(@kindof(A) == u32)
    @assert(cast(u32) A == 7'u32)
}

#test
{
    const A: any = 8'u64
    #assert(#typeof(A) == any)
    @assert(@kindof(A) == u64)
    @assert(cast(u64) A == 8'u64)
}

#test
{
    const A: any = 1.5'f32
    #assert(#typeof(A) == any)
    @assert(@kindof(A) == f32)
    @assert(cast(f32) A == 1.5'f32)
}

#test
{
    const A: any = 2.5'f64
    #assert(#typeof(A) == any)
    @assert(@kindof(A) == f64)
    @assert(cast(f64) A == 2.5'f64)
}

#test
{
    const A: any = true
    #assert(#typeof(A) == any)
    @assert(@kindof(A) == bool)
    @assert(cast(bool) A == true)
}

#test
{
    const A: any = 'Z'
    #assert(#typeof(A) == any)
    @assert(@kindof(A) == rune)
    @assert(cast(rune) A == 'Z')
}

#test
{
    const A: any = "abc"
    #assert(#typeof(A) == any)
    @assert(@kindof(A) == string)
    @assert(cast(string) A == "abc")
}

#test
{
    const A: any = null
    #assert(#typeof(A) == any)
    @assert(A == null)
}

#test
{
    const A: any = 10
    const B: any = 3.0
    const C: any = 0x1_0000_0000
    const D: any = 1e40
    #assert(#typeof(A) == any)
    #assert(#typeof(B) == any)
    #assert(#typeof(C) == any)
    #assert(#typeof(D) == any)
    @assert(@kindof(A) == s32)
    @assert(@kindof(B) == f32)
    @assert(@kindof(C) == s64)
    @assert(@kindof(D) == f64)
    @assert(cast(s32) A == 10's32)
    @assert(cast(f32) B == 3.0'f32)
    @assert(cast(s64) C == 4294967296's64)
    @assert(cast(f64) D == 1e40'f64)
}
