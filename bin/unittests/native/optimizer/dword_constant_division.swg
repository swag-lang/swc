#global private
using Swag

// Unsigned 32-bit division and remainder by a constant go through a 64-bit
// product. Every divisor shape - small, decimal, with and without the
// multiplier fixup, near the top of the range - must agree with the 64-bit
// division of the same values.

#[Swag.Optimize(true), Swag.NoInline]
func div3(x: u32)->u32 => x / 3
#[Swag.Optimize(true), Swag.NoInline]
func div7(x: u32)->u32 => x / 7
#[Swag.Optimize(true), Swag.NoInline]
func div10(x: u32)->u32 => x / 10
#[Swag.Optimize(true), Swag.NoInline]
func mod10(x: u32)->u32 => x % 10
#[Swag.Optimize(true), Swag.NoInline]
func mod65521(x: u32)->u32 => x % 65521
#[Swag.Optimize(true), Swag.NoInline]
func div641(x: u32)->u32 => x / 641
#[Swag.Optimize(true), Swag.NoInline]
func divBig(x: u32)->u32 => x / 0x80000001
#[Swag.Optimize(true), Swag.NoInline]
func modPrime(x: u32)->u32 => x % 1000000007

#[Swag.NoInline]
func wide(x, d: u64)->u64 => x / d

#test
{
    let values = [0'u32, 1, 2, 6, 9, 10, 99, 641, 65520, 65521, 65522, 1000000006, 1000000007, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFE, 0xFFFFFFFF, 123456789, 3141592653]
    for v in values
    {
        let x = cast(u64) v
        Swag.assert(cast(u64) div3(v) == wide(x, 3))
        Swag.assert(cast(u64) div7(v) == wide(x, 7))
        Swag.assert(cast(u64) div10(v) == wide(x, 10))
        Swag.assert(cast(u64) mod10(v) == x - wide(x, 10) * 10)
        Swag.assert(cast(u64) mod65521(v) == x - wide(x, 65521) * 65521)
        Swag.assert(cast(u64) div641(v) == wide(x, 641))
        Swag.assert(cast(u64) divBig(v) == wide(x, 0x80000001))
        Swag.assert(cast(u64) modPrime(v) == x - wide(x, 1000000007) * 1000000007)
    }
}
