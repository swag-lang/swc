#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func product(a, b, c: u64)->u64 => (a + b) * c
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func square(a, b: u64)->u64 => (a + b) * (a + b)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func product32(a, b, c: u32)->u32 => (a + b) * c
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func square32(a, b: u32)->u32 => (a + b) * (a + b)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func preserve(a, b, c: u64)->u64
{
    let sum = a + b
    return (sum * c) ^ sum
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func branch(a, b, c: u64)->u64
{
    let value = (a + b) * c
    if value == 0 do return a
    return value
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func pressure(a, b, c, d, e, f: u64)->u64 => (a + b) * c + (d + e) * f

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 7, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            let sum = a + b
            Swag.assert(square(a, b) == sum * sum)
            let lowA   = cast(u32) (a & 0xFFFFFFFF)
            let lowB   = cast(u32) (b & 0xFFFFFFFF)
            let lowSum = lowA + lowB
            Swag.assert(square32(lowA, lowB) == lowSum * lowSum)
            for c in values
            {
                let expected = sum * c
                Swag.assert(product(a, b, c) == expected)
                Swag.assert(product32(lowA, lowB, cast(u32) (c & 0xFFFFFFFF)) == cast(u32) (expected & 0xFFFFFFFF))
                Swag.assert(preserve(a, b, c) == (expected ^ sum))
                Swag.assert(branch(a, b, c) == (expected == 0 ? a : expected))
                Swag.assert(pressure(a, b, c, ~a, ~b, ~c) == expected + (~a + ~b) * ~c)
            }
        }
    }
}
