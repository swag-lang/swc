#global private

// An unsigned remainder by a constant of a dividend with a known bound takes a
// dword multiplier, one shift and the quotient multiplied back, as an unsigned
// quotient of one does. A hash folded modulo a prime carries its own bound
// around the loop: the remainder of the previous trip bounds the next sum.
// Qword sums and products of bytes and words, a masked dword and a remainder of
// a quotient must agree with a remainder by the same value held in a variable.

#[Swag.Optimize(true), Swag.NoInline]
func hashBytes(a: const [*] u8, n: u64)->u64
{
    var h = 0'u64
    for i in n do
        h = (h * 31 + a[i]) % 1000003
    return h
}

#[Swag.Optimize(true), Swag.NoInline]
func hashQuotient(a: const [*] u8, n: u64)->u64
{
    var h = 0'u64
    for i in n do
        h = (h * 3 + a[i]) / 7
    return h
}

#[Swag.Optimize(true), Swag.NoInline]
func byteSumRemainder(a, b: u8)->u64 => (cast(u64) a * 1000 + cast(u64) b) % 7
#[Swag.Optimize(true), Swag.NoInline]
func wordProductRemainder(a, b: u16)->u64 => (cast(u64) a * cast(u64) b) % 1000003
#[Swag.Optimize(true), Swag.NoInline]
func wordRemainder(a: u16)->u32 => cast(u32) a % 10
#[Swag.Optimize(true), Swag.NoInline]
func maskedRemainder(x: u32)->u32 => (x & 0xFFFFFF) % 1000
#[Swag.Optimize(true), Swag.NoInline]
func quotientRemainder(x: u32)->u32 => (x / 1000) % 100

#[Swag.NoInline]
func rem32(x, d: u32)->u32 => x % d
#[Swag.NoInline]
func rem64(x, d: u64)->u64 => x % d
#[Swag.NoInline]
func div64(x, d: u64)->u64 => x / d

#[Swag.NoInline]
func hashBytesByVariable(a: const [*] u8, n: u64, d: u64)->u64
{
    var h = 0'u64
    for i in n do
        h = rem64(h * 31 + a[i], d)
    return h
}

#[Swag.NoInline]
func hashQuotientByVariable(a: const [*] u8, n: u64, d: u64)->u64
{
    var h = 0'u64
    for i in n do
        h = div64(h * 3 + a[i], d)
    return h
}

#test
{
    for i in 0 until 256
    {
        let a = cast(u8) i
        for j in 0 until 256
        {
            let b = cast(u8) j
            Swag.assert(byteSumRemainder(a, b) == rem64(cast(u64) a * 1000 + cast(u64) b, 7))
        }
    }

    for i in 0 until 65536
    {
        let a = cast(u16) i
        Swag.assert(wordRemainder(a) == rem32(cast(u32) a, 10))
        let b = cast(u16) (65535 - i)
        Swag.assert(wordProductRemainder(a, b) == rem64(cast(u64) a * cast(u64) b, 1000003))
        Swag.assert(wordProductRemainder(a, a) == rem64(cast(u64) a * cast(u64) a, 1000003))
    }
    Swag.assert(wordProductRemainder(65535, 65535) == 4294836225'u64 % 1000003)

    for x in [0'u32, 1, 999, 1000, 0xFFFFFF, 0xFFFFFE, 0x1000000, 0xFFFFFFFF, 0x7FFFFFFF, 0x12345678, 4294967295 - 1000]
    {
        Swag.assert(maskedRemainder(x) == rem32(x & 0xFFFFFF, 1000))
        Swag.assert(quotientRemainder(x) == rem32(x / 1000, 100))
    }

    // Bytes that drive the hash to its largest sums, then a spread of values.
    var bytes: [512] u8
    for i in 512 do
        bytes[i] = 255
    Swag.assert(hashBytes(&bytes[0], 512) == hashBytesByVariable(&bytes[0], 512, 1000003))
    Swag.assert(hashQuotient(&bytes[0], 512) == hashQuotientByVariable(&bytes[0], 512, 7))
    for i in 512 do
        bytes[i] = cast(u8) ((i * 131 + 7) % 256)
    for n in [0'u64, 1, 2, 3, 17, 255, 511, 512]
    {
        Swag.assert(hashBytes(&bytes[0], n) == hashBytesByVariable(&bytes[0], n, 1000003))
        Swag.assert(hashQuotient(&bytes[0], n) == hashQuotientByVariable(&bytes[0], n, 7))
    }
}
