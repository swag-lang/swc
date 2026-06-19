#global fileprivate //

// Hexadecimal literals
#test
{
    let a = 0x2A
    let b = 0xFF'u8
    let c = 0xDEAD_BEEF'u32
    let d = 0xFFFF_FFFF_FFFF_FFFF'u64

    #assert(#typeof(a) == u32)
    #assert(#typeof(b) == u8)
    #assert(#typeof(c) == u32)
    #assert(#typeof(d) == u64)

    @assert(a == 42)
    @assert(b == 255'u8)
    @assert(c == 3735928559'u32)
    @assert(d == 18446744073709551615'u64)
}

// Binary literals
#test
{
    let a = 0b0010_1010
    let b = 0b1111_1111'u8
    let c = 0b1010_1010_1010_1010'u16

    #assert(#typeof(a) == u32)
    #assert(#typeof(b) == u8)
    #assert(#typeof(c) == u16)

    @assert(a == 42)
    @assert(b == 255'u8)
    @assert(c == 43690'u16)
}

// Hex and binary consistency
#test
{
    let hex  = 0x2A'u32
    let bin  = 0b0010_1010'u32
    let dec  = 42'u32
    @assert(hex == bin)
    @assert(hex == dec)
}

// Integer type suffixes
#test
{
    let a = 127's8
    let b = 255'u8
    let c = 32767's16
    let d = 65535'u16
    let e = 2147483647's32
    let f = 4294967295'u32
    let g = 9223372036854775807's64
    let h = 18446744073709551615'u64

    #assert(#typeof(a) == s8)
    #assert(#typeof(b) == u8)
    #assert(#typeof(c) == s16)
    #assert(#typeof(d) == u16)
    #assert(#typeof(e) == s32)
    #assert(#typeof(f) == u32)
    #assert(#typeof(g) == s64)
    #assert(#typeof(h) == u64)

    @assert(a == 127's8)
    @assert(b == 255'u8)
    @assert(c == 32767's16)
    @assert(d == 65535'u16)
}

// Float type suffixes
#test
{
    let a = 3.14'f32
    let b = 3.14'f64
    let c = 0.0'f32
    let d = 1.0'f64

    #assert(#typeof(a) == f32)
    #assert(#typeof(b) == f64)
    #assert(#typeof(c) == f32)
    #assert(#typeof(d) == f64)

    @assert(a > 3.13'f32 and a < 3.15'f32)
    @assert(c == 0.0'f32)
    @assert(d == 1.0'f64)
}

// Digit separator underscores
#test
{
    let a = 1_000_000
    let b = 0xFF_FF'u32
    let c = 0b1010_1010'u32

    @assert(a == 1000000)
    @assert(b == 65535'u32)
    @assert(c == 170'u32)
}

// Hex type suffixes
#test
{
    let a = 0x7F's8
    let b = 0xFF'u8
    let c = 0x7FFF's16
    let d = 0xFFFF'u16
    let e = 0x7FFF_FFFF's32
    let f = 0xFFFF_FFFF'u32

    #assert(#typeof(a) == s8)
    #assert(#typeof(b) == u8)
    #assert(#typeof(c) == s16)
    #assert(#typeof(d) == u16)
    #assert(#typeof(e) == s32)
    #assert(#typeof(f) == u32)

    @assert(a == 127's8)
    @assert(b == 255'u8)
    @assert(c == 32767's16)
    @assert(d == 65535'u16)
    @assert(e == 2147483647's32)
    @assert(f == 4294967295'u32)
}
