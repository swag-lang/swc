#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func left(a, b: u64)->u64 => (0 - a) - b
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func sum(a, b: u64)->u64 => (0 - a) + (0 - b)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func left32(a, b: u32)->u32 => (0 - a) - b
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func sum32(a, b: u32)->u32 => (0 - a) + (0 - b)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shared(a, b: u64)->u64
{
    let negative = 0'u64 - a
    return (negative - b) ^ negative
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func compared(a, b: u64)->bool => ((0 - a) - b) == 0
#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checked(a, b: s64)->s64 => (0 - a) - b
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shifted(a, b: u64)->u64 => ((0 - a) - b) >> 3

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 7, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            let expected = ~(a + b) + 1
            Swag.assert(left(a, b) == expected)
            Swag.assert(sum(a, b) == expected)
            Swag.assert(shared(a, b) == (expected ^ (~a + 1)))
            Swag.assert(compared(a, b) == (expected == 0))
            Swag.assert(shifted(a, b) == expected >> 3)
            let lowA = cast(u32) (a & 0xFFFFFFFF)
            let lowB = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(left32(lowA, lowB) == cast(u32) (expected & 0xFFFFFFFF))
            Swag.assert(sum32(lowA, lowB) == cast(u32) (expected & 0xFFFFFFFF))
        }
    }
    Swag.assert(checked(-7, 3) == 4)
    Swag.assert(checked(7, -3) == -4)
}
