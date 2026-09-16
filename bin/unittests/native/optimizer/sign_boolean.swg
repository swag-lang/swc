#global private

#[Swag.NoInline]
func negative(a: s64)->u64 => a < 0 ? 1 : 0
#[Swag.NoInline]
func negative32(a: s32)->u32 => a < 0 ? 1 : 0
#[Swag.NoInline]
func negativeWide(a: s32)->u64 => a < 0 ? 1 : 0
#[Swag.NoInline]
func negativeNarrow(a: s64)->u32 => a < 0 ? 1 : 0
#[Swag.NoInline]
func nonnegative(a: s64)->u64 => a >= 0 ? 1 : 0
#[Swag.NoInline]
func preserve(a: s64)->u64
{
    let low: u64 = a < 0 ? 1 : 0
    return (cast #bit (u64) a) ^ low
}

#test
{
    let values = [-9223372036854775808's64, -2147483648, -1, 0, 1, 2147483647, 9223372036854775807]
    for a in values
    {
        let expected = (cast #bit (u64) a) >> 63
        Swag.assert(negative(a) == expected)
        Swag.assert(negativeNarrow(a) == expected)
        Swag.assert(nonnegative(a) == (expected ^ 1))
        Swag.assert(preserve(a) == ((cast #bit (u64) a) ^ expected))
    }
    let narrow = [-2147483648's32, -1, 0, 1, 2147483647]
    for a in narrow
    {
        let expected = (cast #bit (u32) a) >> 31
        Swag.assert(negative32(a) == expected)
        Swag.assert(negativeWide(a) == expected)
    }
}
