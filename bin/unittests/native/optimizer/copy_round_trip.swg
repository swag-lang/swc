#global private

#[Swag.NoInline]
func div3(a: u64)->u64 => a / 3

#[Swag.NoInline]
func div10(a: u64)->u64 => a / 10

#[Swag.NoInline]
func div7(a: u64)->u64 => a / 7

#[Swag.NoInline]
func dynamicDiv(a, divisor: u64)->u64 => a / divisor

#[Swag.NoInline]
func keepBoth(a: u64)->u64
{
    let q = a / 10
    return q ^ (q >> 3)
}

#[Swag.NoInline]
func div32(a: u32)->u32 => a / 10

#test
{
    let values = [0'u64, 1, 2, 3, 7, 9, 10, 11, 0xFFFFFFFF, 0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for value in values
    {
        Swag.assert(div3(value) == dynamicDiv(value, 3))
        Swag.assert(div7(value) == dynamicDiv(value, 7))
        let quotient = dynamicDiv(value, 10)
        Swag.assert(div10(value) == quotient)
        Swag.assert(keepBoth(value) == (quotient ^ (quotient >> 3)))
        let narrow = cast(u32) (value & 0xFFFFFFFF)
        Swag.assert(div32(narrow) == dynamicDiv(narrow, 10))
    }
}
