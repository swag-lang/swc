#global private

// An unsigned division by a constant of a dividend with a known bound takes a
// dword multiplier and one shift. Products and sums of bytes and words, a
// masked dword, a difference from a constant and a zero-extended qword must
// agree with a division by the same value held in a variable.

#[Swag.Optimize(true), Swag.NoInline]
func mix8(a, b, t: u8)->u8 => cast(u8) ((cast(u32) a * (255 - cast(u32) t) + cast(u32) b * cast(u32) t) / 255)
#[Swag.Optimize(true), Swag.NoInline]
func mul255(a, b: u8)->u32 => (cast(u32) a * cast(u32) b) / 255
#[Swag.Optimize(true), Swag.NoInline]
func avg3(a, b, c: u8)->u32 => (cast(u32) a + cast(u32) b + cast(u32) c) / 3
#[Swag.Optimize(true), Swag.NoInline]
func tens(a: u16)->u32 => cast(u32) a / 10
#[Swag.Optimize(true), Swag.NoInline]
func sevenths(x: u32)->u32 => (x & 0xFFFFFF) / 7
#[Swag.Optimize(true), Swag.NoInline]
func largeDivisor(a, b: u16)->u32 => (cast(u32) a * cast(u32) b) / 1000003
#[Swag.Optimize(true), Swag.NoInline]
func wideTens(a: u16)->u64 => cast(u64) a / 10
#[Swag.Optimize(true), Swag.NoInline]
func wholeTens(x: u32)->u64 => cast(u64) x / 10
#[Swag.Optimize(true), Swag.NoInline]
func averageThird(a: const [*] u8, n: u64)->u32
{
    var sum = 0'u32
    for i in n do
        sum += cast(u32) a[i]
    return sum / 3
}

#[Swag.NoInline]
func div32(x, d: u32)->u32 => x / d
#[Swag.NoInline]
func div64(x, d: u64)->u64 => x / d

#test
{
    for i in 0 until 256
    {
        let a = cast(u8) i
        for j in 0 until 256
        {
            let b = cast(u8) j
            Swag.assert(mul255(a, b) == div32(cast(u32) a * cast(u32) b, 255))
            Swag.assert(avg3(a, b, 255) == div32(cast(u32) a + cast(u32) b + 255, 3))
            let t = cast(u8) ((i * 7 + j) % 256)
            Swag.assert(cast(u32) mix8(a, b, t) == div32(cast(u32) a * (255 - cast(u32) t) + cast(u32) b * cast(u32) t, 255))
        }
    }

    for i in 0 until 65536
    {
        let a = cast(u16) i
        Swag.assert(tens(a) == div32(cast(u32) a, 10))
        Swag.assert(wideTens(a) == div64(cast(u64) a, 10))
        let b = cast(u16) (65535 - i)
        Swag.assert(largeDivisor(a, b) == div32(cast(u32) a * cast(u32) b, 1000003))
    }
    Swag.assert(largeDivisor(65535, 65535) == 4294)

    for x in [0'u32, 1, 6, 7, 0xFFFFFF, 0xFFFFFE, 0xFFFFFA, 0x1000000, 0xFFFFFFFF, 0x7FFFFFFF, 0x12345678] do
        Swag.assert(sevenths(x) == div32(x & 0xFFFFFF, 7))
    for x in [0'u32, 9, 10, 0xFFFFFFFF, 0xFFFFFFFA, 0x80000000, 4294967290] do
        Swag.assert(wholeTens(x) == div64(cast(u64) x, 10))

    var bytes: [5] u8 = [255, 255, 255, 255, 254]
    Swag.assert(averageThird(&bytes[0], 5) == 1274 / 3)
}
