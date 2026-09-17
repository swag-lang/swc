#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtractProducts(value: u64)->u64 => value * 5 - value * 3

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func addProducts(value: u64)->u64 => value * 3 + value * 2

// The expected values wrap too, so a build with overflow checks does not trap.
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func wrappingTimes(value, factor: u64)->u64 => value * factor

#test
{
    for value in [0'u64, 1, 2, 7, 0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF]
    {
        Swag.assert(subtractProducts(value) == wrappingTimes(value, 2))
        Swag.assert(addProducts(value) == wrappingTimes(value, 5))
    }
}
