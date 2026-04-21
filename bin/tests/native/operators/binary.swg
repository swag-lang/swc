#global fileprivate

// Integer arithmetic operators
#test
{
    let a = 40 + 2
    let b = 84 - 42
    let c = 6 * 7
    let d = 84 / 2
    let e = 212 % 85

    #assert(#typeof(a) == s32)
    #assert(#typeof(b) == s32)
    #assert(#typeof(c) == s32)
    #assert(#typeof(d) == s32)
    #assert(#typeof(e) == s32)

    @assert(a == 42)
    @assert(b == 42)
    @assert(c == 42)
    @assert(d == 42)
    @assert(e == 42)
}

// Float arithmetic and type promotion
#test
{
    let a = 40 + 2.5'f64
    let b = 84.0'f32 / 2.0'f32
    let c = 10.5'f64 - 2

    #assert(#typeof(a) == f64)
    #assert(#typeof(b) == f32)
    #assert(#typeof(c) == f64)

    @assert(a == 42.5'f64)
    @assert(b == 42.0'f32)
    @assert(c == 8.5'f64)
}

// Bitwise AND, OR, XOR on u32
#test
{
    let a = 0x3F'u32 & 0x2A'u32
    let b = 0x20'u32 | 0x0A'u32
    let c = 0x7F'u32 ^ 0x55'u32

    #assert(#typeof(a) == u32)
    #assert(#typeof(b) == u32)
    #assert(#typeof(c) == u32)

    @assert(a == 42'u32)
    @assert(b == 42'u32)
    @assert(c == 42'u32)
}

// Shift left and right on u32 and u64
#test
{
    let a = 21'u32 << 1
    let b = 84'u32 >> 1
    let c = 1'u64 << 40
    let d = c >> 20

    #assert(#typeof(a) == u32)
    #assert(#typeof(b) == u32)
    #assert(#typeof(c) == u64)
    #assert(#typeof(d) == u64)

    @assert(a == 42'u32)
    @assert(b == 42'u32)
    @assert(c == 0x0000_0100_0000_0000'u64)
    @assert(d == 0x0000_0000_0010_0000'u64)
}

// Operator precedence and parentheses
#test
{
    let a = 6 + 8 * 5 - 4
    let b = (6 + 8) * (5 - 2)

    @assert(a == 42)
    @assert(b == 42)
}

// 64-bit integer arithmetic
#test
{
    let a = 10000000000's64 + 42's64
    let b = 7'u64 * 6'u64

    #assert(#typeof(a) == s64)
    #assert(#typeof(b) == u64)

    @assert(a == 10000000042's64)
    @assert(b == 42'u64)
}

// Rune bitwise and shift operators behave like int-like unsigned values
#test
{
    let r = 'A''rune
    let a = r & 0x7F
    let b = r | 0x20
    let c = r << 1
    let d = c >> 1

    #assert(#typeof(a) == rune)
    #assert(#typeof(b) == rune)
    #assert(#typeof(c) == rune)
    #assert(#typeof(d) == rune)

    @assert(a == 'A''rune)
    @assert(b == 'a''rune)
    @assert(c == cast(rune) 130'u32)
    @assert(d == 'A''rune)
}

#test
{
    var r = 'A''rune
    let next = r + #wrap 1
    r += #wrap 1

    #assert(#typeof(next) == rune)
    @assert(next == 'B''rune)
    @assert(r == 'B''rune)
}
