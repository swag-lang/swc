#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func addNegative(a, b: u64)->u64 => a + (~b + 1)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtractNegative(a, b: u64)->u64 => a - (~b + 1)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func addNegative32(a, b: u32)->u32 => a + (~b + 1)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtractNegative32(a, b: u32)->u32 => a - (~b + 1)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func sharedNegative(a, b: u64)->u64
{
    let negative = ~b + 1
    return (a + negative) ^ negative
}

#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checkedAddNegative(a, b: s64)->s64 => a + -b

#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checkedSubtractNegative(a, b: s64)->s64 => a - -b

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 2, 0xFFFFFFFF, 0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            Swag.assert(addNegative(a, b) == a - b)
            Swag.assert(subtractNegative(a, b) == a + b)
            Swag.assert(sharedNegative(a, b) == ((a - b) ^ (0'u64 - b)))
            let a32 = cast(u32) (a & 0xFFFFFFFF)
            let b32 = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(addNegative32(a32, b32) == a32 - b32)
            Swag.assert(subtractNegative32(a32, b32) == a32 + b32)
        }
    }
    Swag.assert(checkedAddNegative(100, 27) == 73)
    Swag.assert(checkedSubtractNegative(100, 27) == 127)
    Swag.assert(checkedAddNegative(-100, -27) == -73)
    Swag.assert(checkedSubtractNegative(-100, -27) == -127)
}
