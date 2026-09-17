#global private

// A signed division by a power of two from four up selects its rounding bias:
// the dividend itself when it is not negative, the dividend plus the divisor
// minus one otherwise. Dwords and qwords, the largest divisors whose bias
// still fits a dword, the one past it, and the most negative dividends must
// agree with a division by the same value held in a variable.

#[Swag.Optimize(true), Swag.NoInline]
func quarter(x: s32)->s32 => x / 4
#[Swag.Optimize(true), Swag.NoInline]
func by256(x: s32)->s32 => x / 256
#[Swag.Optimize(true), Swag.NoInline]
func byTopDword(x: s32)->s32 => x / 0x40000000
#[Swag.Optimize(true), Swag.NoInline]
func wideBy16(x: s64)->s64 => x / 16
#[Swag.Optimize(true), Swag.NoInline]
func wideBy2Pow31(x: s64)->s64 => x / 0x80000000
#[Swag.Optimize(true), Swag.NoInline]
func wideBy2Pow32(x: s64)->s64 => x / 0x100000000
#[Swag.Optimize(true), Swag.NoInline]
func lerp(a, b, t: s32)->s32 => a + (b - a) * #wrap t / 256
#[Swag.Optimize(true), Swag.NoInline]
func averageQuarters(p: const [*] s32, n: u64)->s32
{
    var sum = 0's32
    for i in n do
        sum += p[i] / 8
    return sum
}

#[Swag.NoInline]
func div32(x, d: s32)->s32 => x / d
#[Swag.NoInline]
func div64(x, d: s64)->s64 => x / d

func check32(x: s32)
{
    Swag.assert(quarter(x) == div32(x, 4))
    Swag.assert(by256(x) == div32(x, 256))
    Swag.assert(byTopDword(x) == div32(x, 0x40000000))
}

func check64(x: s64)
{
    Swag.assert(wideBy16(x) == div64(x, 16))
    Swag.assert(wideBy2Pow31(x) == div64(x, 0x80000000))
    Swag.assert(wideBy2Pow32(x) == div64(x, 0x100000000))
}

#test
{
    for i in -1000 until 1000
    {
        check32(i)
        check64(i)
        Swag.assert(lerp(i, 3 * i, 77) == i + div32((3 * i - i) * 77, 256))
    }
    for x in [0x7FFFFFFF's32, -0x7FFFFFFF, -0x7FFFFFFF - 1, 0x40000000, -0x40000000, -0x3FFFFFFF, -0x40000001, 255, -255, -256, -257] do
        check32(x)
    for x in [0x7FFFFFFFFFFFFFFF's64, -0x7FFFFFFFFFFFFFFF, -0x7FFFFFFFFFFFFFFF - 1, 0x80000000, -0x80000000, -0x7FFFFFFF, -0x80000001, 0x100000000, -0x100000000, -0xFFFFFFFF, -0x100000001] do
        check64(x)

    var values: [4] s32 = [-9, -8, -7, 17]
    Swag.assert(averageQuarters(&values[0], 4) == -1 + -1 + 0 + 2)
}
