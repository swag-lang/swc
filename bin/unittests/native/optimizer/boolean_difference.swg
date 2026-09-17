#global private

// Three-way comparisons subtract two booleans and sign-extend the result;
// the optimizer does both on bytes. Every order and width must still give
// -1, 0 or 1.

#[Swag.Optimize(true), Swag.NoInline]
func compare32(a, b: s32)->s32 => a <=> b
#[Swag.Optimize(true), Swag.NoInline]
func compare64(a, b: s64)->s32 => a <=> b
#[Swag.Optimize(true), Swag.NoInline]
func compareU64(a, b: u64)->s32 => a <=> b
#[Swag.Optimize(true), Swag.NoInline]
func compareU8(a, b: u8)->s64 => a <=> b

func expected(less, greater: bool)->s32
{
    if less do
        return -1
    if greater do
        return 1
    return 0
}

#test
{
    let signed = [0's64, 1, -1, 2, -2, 0x7FFFFFFF, -0x80000000, 0x7FFFFFFFFFFFFFFF, -0x7FFFFFFFFFFFFFFF - 1]
    for a in signed
    {
        for b in signed
        {
            Swag.assert(compare64(a, b) == expected(a < b, a > b))
            let a32 = cast #wrap (s32) a
            let b32 = cast #wrap (s32) b
            Swag.assert(compare32(a32, b32) == expected(a32 < b32, a32 > b32))
            let au = cast #bit (u64) a
            let bu = cast #bit (u64) b
            Swag.assert(compareU64(au, bu) == expected(au < bu, au > bu))
            let a8 = cast #wrap (u8) a
            let b8 = cast #wrap (u8) b
            Swag.assert(compareU8(a8, b8) == cast(s64) expected(a8 < b8, a8 > b8))
        }
    }
}
