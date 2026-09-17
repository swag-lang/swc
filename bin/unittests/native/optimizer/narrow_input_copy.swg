#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func remainder(a: s32)->s32 => a % 8

#[Swag.NoInline]
func dynamicRemainder(a, b: s32)->s32 => a % b

#[Swag.NoInline]
func divide(a: s32)->s32 => a / 7

#[Swag.NoInline]
func dynamicDivide(a, b: s32)->s32 => a / b

#[Swag.NoInline]
func retainSource(a: u64, b: u32)->u64
{
    let low = cast(u32) (a & 0xFFFFFFFF)
    return a ^ cast(u64) ((low + b) * (low - b))
}

#[Swag.NoInline]
func shift(a: u64, count: u32)->u64
{
    let low = cast(u32) (a & 0xFFFFFFFF)
    return a ^ cast(u64) (low >> count)
}

#[Swag.NoInline]
func branch(a: u64, b: u32)->u64
{
    if b == 0 do
        return a
    return cast(u64) (cast(u32) (a & 0xFFFFFFFF) + b)
}

#test
{
    let signedValues = [-2147483648's32, -2147483647, -65537, -9, -8, -7, -1, 0, 1, 7, 8, 9, 65537, 2147483647]
    for a in signedValues
    {
        Swag.assert(remainder(a) == dynamicRemainder(a, 8))
        Swag.assert(divide(a) == dynamicDivide(a, 7))
    }
    let wideValues = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0x1234567887654321, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in wideValues
    {
        let low = a & 0xFFFFFFFF
        for b in [0'u32, 1, 7, 0x80000000, 0xFFFFFFFF]
        {
            let sum = (low + cast(u64) b) & 0xFFFFFFFF
            let difference = (low - cast(u64) b) & 0xFFFFFFFF
            Swag.assert(retainSource(a, b) == (a ^ ((sum * difference) & 0xFFFFFFFF)))
            Swag.assert(branch(a, b) == (b == 0 ? a : sum))
        }
        for count in [0'u32, 1, 7, 16, 31] do
            Swag.assert(shift(a, count) == (a ^ (low >> count)))
    }
}
