#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// A 32-bit copy is widened only when no reader looks above bit 31, and an
// extension is dropped only when nobody reads its upper half, even through
// further copies. Wrapping values, whose upper halves differ from the
// extension of their low halves, exercise both directions.

#[Swag.Optimize(true), Swag.NoInline]
func absDiff(a, b: u32)->u32 => a > b ? a - b : b - a

#[Swag.Optimize(true), Swag.NoInline]
func clamp(x, lo, hi: s32)->s32
{
    if x < lo do return lo
    if x > hi do return hi
    return x
}

#[Swag.Optimize(true), Swag.NoInline]
func widenLater(a: u32, b: u64)->u64
{
    let x = a
    let y = x + 1
    return cast(u64, y) + b
}

#[Swag.Optimize(true), Swag.NoInline]
func signLater(a: s32)->s64
{
    let x = a
    let y = x - 1
    return cast(s64, y) * 3
}

#[Swag.Optimize(true), Swag.NoInline]
func byteLater(a: u8, b: u64)->u64
{
    var x = a
    x += 1
    return cast(u64, x) + b
}

#[Swag.Optimize(true), Swag.NoInline]
func affine(b: bool)->u32 => b ? 7 : 3

#[Swag.Optimize(true), Swag.NoInline]
func widened(b: bool, x: u64)->u64 => cast(u64, affine(b)) + x

#test
{
    Swag.require(widened(true, 0x100000000) == 0x100000007)
    Swag.require(widened(false, 1) == 4)

    Swag.require(absDiff(3, 10) == 7)
    Swag.require(absDiff(0xFFFFFFFF, 1) == 0xFFFFFFFE)
    Swag.require(absDiff(0, 0xFFFFFFFF) == 0xFFFFFFFF)

    Swag.require(clamp(5, -3, 3) == 3)
    Swag.require(clamp(-9, -3, 3) == -3)
    Swag.require(clamp(-2, -3, 3) == -2)
    Swag.require(clamp(-0x7FFFFFFF - 1, -0x7FFFFFFF - 1, 0) == -0x7FFFFFFF - 1)

    Swag.require(widenLater(0xFFFFFFFF, 5) == 5)
    Swag.require(widenLater(7, 0x100000000) == 0x100000008)

    Swag.require(signLater(-5) == -18)
    Swag.require(signLater(-0x7FFFFFFF - 1) == 0x7FFFFFFF * 3)
    Swag.require(signLater(0) == -3)

    Swag.require(byteLater(0xFF, 3) == 3)
    Swag.require(byteLater(0x10, 0x100) == 0x111)
}
