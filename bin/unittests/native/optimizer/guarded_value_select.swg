#global private

// A pair of range guards selecting between two values is if-converted as one
// chain. Exercise both comparison directions, signednesses and register widths
// at the boundaries where either guard rejects.

#[Swag.Optimize(true), Swag.NoInline]
func betweenU32(x, low, high, inside, outside: u32)->u32 => x >= low and x <= high ? inside : outside

#[Swag.Optimize(true), Swag.NoInline]
func betweenS32(x, low, high, inside, outside: s32)->s32 => x >= low and x <= high ? inside : outside

#[Swag.Optimize(true), Swag.NoInline]
func betweenU64(x, low, high, inside, outside: u64)->u64 => x >= low and x < high ? inside : outside

#[Swag.Optimize(true), Swag.NoInline]
func reversedS64(x, low, high, inside, outside: s64)->s64 => x <= high and x >= low ? inside : outside

#test
{
    Swag.assert(betweenU32(9, 10, 20, 101, 202) == 202)
    Swag.assert(betweenU32(10, 10, 20, 101, 202) == 101)
    Swag.assert(betweenU32(20, 10, 20, 101, 202) == 101)
    Swag.assert(betweenU32(21, 10, 20, 101, 202) == 202)

    Swag.assert(betweenS32(-11, -10, 10, -101, -202) == -202)
    Swag.assert(betweenS32(-10, -10, 10, -101, -202) == -101)
    Swag.assert(betweenS32(10, -10, 10, -101, -202) == -101)
    Swag.assert(betweenS32(11, -10, 10, -101, -202) == -202)

    Swag.assert(betweenU64(0xFFFFFFFF, 0x100000000, 0x100000002, 101, 202) == 202)
    Swag.assert(betweenU64(0x100000000, 0x100000000, 0x100000002, 101, 202) == 101)
    Swag.assert(betweenU64(0x100000001, 0x100000000, 0x100000002, 101, 202) == 101)
    Swag.assert(betweenU64(0x100000002, 0x100000000, 0x100000002, 101, 202) == 202)

    Swag.assert(reversedS64(-101, -100, 100, -303, -404) == -404)
    Swag.assert(reversedS64(-100, -100, 100, -303, -404) == -303)
    Swag.assert(reversedS64(100, -100, 100, -303, -404) == -303)
    Swag.assert(reversedS64(101, -100, 100, -303, -404) == -404)
}
