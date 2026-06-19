#global fileprivate

// Compound assignment on array elements
#test
{
    var arr: [5] s32 = [1, 2, 3, 4, 5]
    arr[0] += 10
    arr[1] -= 1
    arr[2] *= 3
    arr[3] /= 2
    arr[4] %= 3
    @assert(arr[0] == 11)
    @assert(arr[1] == 1)
    @assert(arr[2] == 9)
    @assert(arr[3] == 2)
    @assert(arr[4] == 2)
}

// Compound assignment on array elements - bitwise
#test
{
    var arr: [3] u32 = [0xFF'u32, 0x0F'u32, 0x01'u32]
    arr[0] &= 0x0F'u32
    arr[1] |= 0xF0'u32
    arr[2] ^= 0x03'u32
    @assert(arr[0] == 0x0F'u32)
    @assert(arr[1] == 0xFF'u32)
    @assert(arr[2] == 0x02'u32)
}

// Compound assignment in a loop
#test
{
    var total: s32 = 0
    for i in 10
    {
        total += cast(s32) i
    }
    @assert(total == 45)
}

// Compound multiply in loop (factorial)
#test
{
    var result: s64 = 1
    for i in 1 to 10
    {
        result *= cast(s64) i
    }
    @assert(result == 3628800) // 10!
}

// Chained compound assignments on same variable
#test
{
    var x: s32 = 1
    x += 1  // 2
    x *= 3  // 6
    x -= 1  // 5
    x += 5  // 10
    x /= 2  // 5
    @assert(x == 5)
}

// Compound shift on u64
#test
{
    var a: u64 = 1'u64
    a <<= 32
    @assert(a == 0x0000_0001_0000_0000'u64)
    a >>= 16
    @assert(a == 0x0000_0000_0001_0000'u64)
}

// Compound assignment with f32
#test
{
    var f: f32 = 1.0'f32
    f += 0.5'f32
    @assert(f == 1.5'f32)
    f *= 4.0'f32
    @assert(f == 6.0'f32)
    f -= 1.0'f32
    @assert(f == 5.0'f32)
    f /= 2.5'f32
    @assert(f == 2.0'f32)
}

// XOR swap pattern
#test
{
    var a: u32 = 42
    var b: u32 = 99
    a ^= b
    b ^= a
    a ^= b
    @assert(a == 99)
    @assert(b == 42)
}

// XOR swap with u64
#test
{
    var a: u64 = 0xDEAD_BEEF'u64
    var b: u64 = 0xCAFE_BABE'u64
    a ^= b
    b ^= a
    a ^= b
    @assert(a == 0xCAFE_BABE'u64)
    @assert(b == 0xDEAD_BEEF'u64)
}

// Compound assignment through pointer
#test
{
    var x: s32 = 10
    var p = &x
    dref p += 5
    @assert(x == 15)
    dref p *= 2
    @assert(x == 30)
}

// Compound modulo
#test
{
    var x: s32 = 100
    x %= 30
    @assert(x == 10)
    x %= 7
    @assert(x == 3)
}

// All compound bitwise on same variable
#test
{
    var x: u32 = 0xFF'u32
    x &= 0x3F'u32   // 0x3F
    x |= 0x80'u32   // 0xBF
    x ^= 0x0F'u32   // 0xB0
    x <<= 4          // 0xB00
    x >>= 8          // 0x0B
    @assert(x == 0x0B'u32)
}
