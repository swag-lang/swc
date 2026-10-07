#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.Optimize(true), Swag.NoInline]
func mix(values: [*] u64, seed: u64)->u64
{
    var a    = seed
    var b    = seed ^ 0x123456789ABCDEF0
    var c    = seed + 17
    var d    = seed - 29
    var last = 0'u64
    for i in 64'u64
    {
        let x = values[i] + ((a << 7) ^ (a >> 13))
        let y = (b ^ c) + d + i
        d    = c
        c    = b
        b    = a
        a    = (x + y) ^ ((c << 11) | (c >> 53))
        last = a + b + c + d
        values[i + 1] ^= last
    }
    return a ^ b ^ c ^ d ^ last
}

#[Swag.Optimize(false), Swag.NoInline]
func reference(values: [*] u64, seed: u64)->u64
{
    var a    = seed
    var b    = seed ^ 0x123456789ABCDEF0
    var c    = seed + 17
    var d    = seed - 29
    var last = 0'u64
    for i in 64'u64
    {
        let x = values[i] + ((a << 7) ^ (a >> 13))
        let y = (b ^ c) + d + i
        d    = c
        c    = b
        b    = a
        a    = (x + y) ^ ((c << 11) | (c >> 53))
        last = a + b + c + d
        values[i + 1] ^= last
    }
    return a ^ b ^ c ^ d ^ last
}

#[Swag.Optimize(true), Swag.NoInline]
func strided(seed: u32)->u32
{
    var a    = seed
    var b    = seed + 19
    var c    = seed ^ 0x87654321
    var last = 0'u32
    for var i = 5's32; i < 197; i += 3
    {
        let value = cast(u32, i)
        let x     = (a << 5) ^ (a >> 17) ^ b
        let y     = c + value * 17
        c    = b
        b    = a
        a    = x + y
        last = a ^ b ^ c
    }
    return a + b + c + last
}

#[Swag.Optimize(false), Swag.NoInline]
func stridedReference(seed: u32)->u32
{
    var a    = seed
    var b    = seed + 19
    var c    = seed ^ 0x87654321
    var last = 0'u32
    for var i = 5's32; i < 197; i += 3
    {
        let value = cast(u32, i)
        let x     = (a << 5) ^ (a >> 17) ^ b
        let y     = c + value * 17
        c    = b
        b    = a
        a    = x + y
        last = a ^ b ^ c
    }
    return a + b + c + last
}

#test
{
    for seed in [0'u64, 1, 0x123456789ABCDEF0, 0xFFFFFFFFFFFFFFFF]
    {
        var actual: [65] u64
        for i in 65 do
            actual[i] = i * 0x1234567 + seed
        var expected = actual
        Swag.assert(mix(&actual[0], seed) == reference(&expected[0], seed))
        for i in 65 do
            Swag.assert(actual[i] == expected[i])
    }
}

#test
{
    for seed in [0'u32, 1, 0x12345678, 0xFFFFFFFF] do
        Swag.assert(strided(seed) == stridedReference(seed))
}
