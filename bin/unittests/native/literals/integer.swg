#global private     //

// Hexadecimal literals
#test
{
    let a = 0x2A
    let b = 0xFF_u8
    let c = 0xDEAD_BEEF_u32
    let d = 0xFFFF_FFFF_FFFF_FFFF_u64

    #assert(#typeof(a) == u32)
    #assert(#typeof(b) == u8)
    #assert(#typeof(c) == u32)
    #assert(#typeof(d) == u64)

    Swag.require(a == 42)
    Swag.require(b == 255_u8)
    Swag.require(c == 3735928559_u32)
    Swag.require(d == 18446744073709551615_u64)
}

// Binary literals
#test
{
    let a = 0b0010_1010
    let b = 0b1111_1111_u8
    let c = 0b1010_1010_1010_1010_u16

    #assert(#typeof(a) == u32)
    #assert(#typeof(b) == u8)
    #assert(#typeof(c) == u16)

    Swag.require(a == 42)
    Swag.require(b == 255_u8)
    Swag.require(c == 43690_u16)
}

// Hex and binary consistency
#test
{
    let hex = 0x2A_u32
    let bin = 0b0010_1010_u32
    let dec = 42_u32
    Swag.require(hex == bin)
    Swag.require(hex == dec)
}

// Integer type suffixes
#test
{
    let a = 127_s8
    let b = 255_u8
    let c = 32767_s16
    let d = 65535_u16
    let e = 2147483647_s32
    let f = 4294967295_u32
    let g = 9223372036854775807_s64
    let h = 18446744073709551615_u64

    #assert(#typeof(a) == s8)
    #assert(#typeof(b) == u8)
    #assert(#typeof(c) == s16)
    #assert(#typeof(d) == u16)
    #assert(#typeof(e) == s32)
    #assert(#typeof(f) == u32)
    #assert(#typeof(g) == s64)
    #assert(#typeof(h) == u64)

    Swag.require(a == 127_s8)
    Swag.require(b == 255_u8)
    Swag.require(c == 32767_s16)
    Swag.require(d == 65535_u16)
}

// Float type suffixes
#test
{
    let a = 3.14_f32
    let b = 3.14_f64
    let c = 0.0_f32
    let d = 1.0_f64

    #assert(#typeof(a) == f32)
    #assert(#typeof(b) == f64)
    #assert(#typeof(c) == f32)
    #assert(#typeof(d) == f64)

    Swag.require(a > 3.13_f32 and a < 3.15_f32)
    Swag.require(c == 0.0_f32)
    Swag.require(d == 1.0_f64)
}

// Digit separator underscores
#test
{
    let a = 1_000_000
    let b = 0xFF_FF_u32
    let c = 0b1010_1010_u32

    Swag.require(a == 1000000)
    Swag.require(b == 65535_u32)
    Swag.require(c == 170_u32)
}

// Hex type suffixes
#test
{
    let a = 0x7F_s8
    let b = 0xFF_u8
    let c = 0x7FFF_s16
    let d = 0xFFFF_u16
    let e = 0x7FFF_FFFF_s32
    let f = 0xFFFF_FFFF_u32

    #assert(#typeof(a) == s8)
    #assert(#typeof(b) == u8)
    #assert(#typeof(c) == s16)
    #assert(#typeof(d) == u16)
    #assert(#typeof(e) == s32)
    #assert(#typeof(f) == u32)

    Swag.require(a == 127_s8)
    Swag.require(b == 255_u8)
    Swag.require(c == 32767_s16)
    Swag.require(d == 65535_u16)
    Swag.require(e == 2147483647_s32)
    Swag.require(f == 4294967295_u32)
}
