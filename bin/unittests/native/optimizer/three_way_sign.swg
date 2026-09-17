#global private

// `x > y ? 1 : (x < y ? -1 : 0)` becomes the difference of two setcc bytes.
// Signed and unsigned orders, 32 and 64 bits, against a constant and against
// another value must all keep -1, 0 and 1.

#[Swag.Optimize(true), Swag.NoInline]
func sign32(x: s32)->s32 => x > 0 ? 1 : (x < 0 ? -1 : 0)

#[Swag.Optimize(true), Swag.NoInline]
func sign64(x: s64)->s64 => x > 0 ? 1 : (x < 0 ? -1 : 0)

#[Swag.Optimize(true), Swag.NoInline]
func order64(x, y: s64)->s32 => x > y ? 1 : (x < y ? -1 : 0)

#[Swag.Optimize(true), Swag.NoInline]
func orderU64(x, y: u64)->s64 => x > y ? 1 : (x < y ? -1 : 0)

#[Swag.Optimize(true), Swag.NoInline]
func orderU32(x, y: u32)->s32 => x > y ? 1 : (x < y ? -1 : 0)

func reference(less, greater: bool)->s64
{
    if less do
        return -1
    if greater do
        return 1
    return 0
}

#test
{
    let values = [0's64, 1, -1, 2, -2, 0x7FFFFFFF, -0x80000000, 0x80000000, 0x7FFFFFFFFFFFFFFF, -0x7FFFFFFFFFFFFFFF - 1]
    for x in values
    {
        let x32 = cast #wrap (s32) x
        Swag.assert(cast(s64) sign32(x32) == reference(x32 < 0, x32 > 0))
        Swag.assert(sign64(x) == reference(x < 0, x > 0))
        for y in values
        {
            Swag.assert(cast(s64) order64(x, y) == reference(x < y, x > y))
            let ux = cast #bit (u64) x
            let uy = cast #bit (u64) y
            Swag.assert(orderU64(ux, uy) == reference(ux < uy, ux > uy))
            let ux32 = cast #wrap (u32) x
            let uy32 = cast #wrap (u32) y
            Swag.assert(cast(s64) orderU32(ux32, uy32) == reference(ux32 < uy32, ux32 > uy32))
        }
    }
}
