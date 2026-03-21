#global fileprivate //

#test
{
    var a: s32 = 100
    a += 10
    @assert(a == 110)
    a -= 25
    @assert(a == 85)
    a *= 2
    @assert(a == 170)
    a /= 5
    @assert(a == 34)
    a %= 10
    @assert(a == 4)
}

#test
{
    var a: u32 = 0xFF'u32
    a &= 0x0F'u32
    @assert(a == 0x0F'u32)
    a |= 0x30'u32
    @assert(a == 0x3F'u32)
    a ^= 0x15'u32
    @assert(a == 0x2A'u32)
}

#test
{
    var a: u32 = 1'u32
    a <<= 5
    @assert(a == 32'u32)
    a >>= 2
    @assert(a == 8'u32)
}

#test
{
    var a: u64 = 1'u64
    a <<= 40
    @assert(a == 0x0000_0100_0000_0000'u64)
    a >>= 20
    @assert(a == 0x0000_0000_0010_0000'u64)
}

#test
{
    var a: f64 = 10.0'f64
    a += 2.5'f64
    @assert(a == 12.5'f64)
    a -= 0.5'f64
    @assert(a == 12.0'f64)
    a *= 3.5'f64
    @assert(a == 42.0'f64)
    a /= 6.0'f64
    @assert(a == 7.0'f64)
}

#test
{
    var a: s64 = 1000000000's64
    a += 42's64
    @assert(a == 1000000042's64)
    a -= 1000000000's64
    @assert(a == 42's64)
    a *= 1000000000's64
    @assert(a == 42000000000's64)
    a /= 1000000000's64
    @assert(a == 42's64)
}

func addAssign(a: &s32, b: s32)
{
    a += b
}

func mulAssign(a: &s32, b: s32)
{
    a *= b
}

#test
{
    var x: s32 = 10
    addAssign(&x, 32)
    @assert(x == 42)
    mulAssign(&x, 2)
    @assert(x == 84)
}
