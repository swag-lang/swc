#global private

#[Swag.NoInline, Swag.Optimize(true), Swag.Safety(.Overflow, false)]
func decrementPositive(values: [*] s64, index: u64)
{
    values[index] -= 1
    if values[index] > 0
    {
        values[index + 1] ^= 0x55
    }
}

#[Swag.NoInline, Swag.Optimize(true), Swag.Safety(.Overflow, false)]
func decrementNonpositive(values: [*] s64, index: u64)
{
    values[index] -= 1
    if values[index] <= 0
    {
        values[index + 1] ^= 0x55
    }
}

#test
{
    for initial in [0_s64, 1, 2, -1, -2, -9223372036854775808_s64, 9223372036854775807_s64]
    {
        let decremented = initial == -9223372036854775808_s64 ? 9223372036854775807_s64 : initial - 1
        var positive    = [initial, 0_s64]
        decrementPositive(&positive[0], 0)
        Swag.require(positive[0] == decremented)
        Swag.require(positive[1] == (decremented > 0 ? 0x55 : 0))

        var nonpositive = [initial, 0_s64]
        decrementNonpositive(&nonpositive[0], 0)
        Swag.require(nonpositive[0] == decremented)
        Swag.require(nonpositive[1] == (decremented <= 0 ? 0x55 : 0))
    }
}
