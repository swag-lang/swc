#global private
using Swag

// Signed 32-bit division and remainder by a constant go through a 64-bit
// product of the sign-extended dividend. Multipliers with and without their
// top bit set, and every sign and edge of the dividend, must agree with the
// 64-bit division of the same values.

#[Swag.Optimize(true), Swag.NoInline]
func div3(x: s32)->s32 => x / 3
#[Swag.Optimize(true), Swag.NoInline]
func div7(x: s32)->s32 => x / 7
#[Swag.Optimize(true), Swag.NoInline]
func div10(x: s32)->s32 => x / 10
#[Swag.Optimize(true), Swag.NoInline]
func mod10(x: s32)->s32 => x % 10
#[Swag.Optimize(true), Swag.NoInline]
func div1000(x: s32)->s32 => x / 1000
#[Swag.Optimize(true), Swag.NoInline]
func mod641(x: s32)->s32 => x % 641
#[Swag.Optimize(true), Swag.NoInline]
func divLarge(x: s32)->s32 => x / 0x40000001

#[Swag.NoInline]
func wide(x, d: s64)->s64 => x / d

#test
{
    let values = [0's32, 1, -1, 2, -2, 6, -6, 7, -7, 9, -9, 10, -10, 999, -1000, 1001, 641, -642, 0x40000001, -0x40000001, 0x7FFFFFFF, -0x7FFFFFFF, -0x7FFFFFFF - 1, 123456789, -987654321]
    for v in values
    {
        let x = cast(s64) v
        Swag.assert(cast(s64) div3(v) == wide(x, 3))
        Swag.assert(cast(s64) div7(v) == wide(x, 7))
        Swag.assert(cast(s64) div10(v) == wide(x, 10))
        Swag.assert(cast(s64) mod10(v) == x - wide(x, 10) * 10)
        Swag.assert(cast(s64) div1000(v) == wide(x, 1000))
        Swag.assert(cast(s64) mod641(v) == x - wide(x, 641) * 641)
        Swag.assert(cast(s64) divLarge(v) == wide(x, 0x40000001))
    }
}
