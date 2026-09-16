#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func factor3(a, b: u64)->u64 => a * 3 + b * 3
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func factor5(a, b: u64)->u64 => a * 5 + b * 5
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func factor9(a, b: u64)->u64 => a * 9 + b * 9
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtract(a, b: u64)->u64 => a * 3 - b * 3
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shared(a, b: u64)->u64
{
    let product = a * 3
    return (product + b * 3) ^ product
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func different(a, b: u64)->u64 => a * 3 + b * 5
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func variable(a, factor: u64)->u64 => a * factor

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            Swag.assert(factor3(a, b) == variable(a + b, 3))
            Swag.assert(factor5(a, b) == variable(a + b, 5))
            Swag.assert(factor9(a, b) == variable(a + b, 9))
            Swag.assert(subtract(a, b) == variable(a - b, 3))
            Swag.assert(shared(a, b) == ((variable(a, 3) + variable(b, 3)) ^ variable(a, 3)))
            Swag.assert(different(a, b) == variable(a, 3) + variable(b, 5))
        }
    }
}
