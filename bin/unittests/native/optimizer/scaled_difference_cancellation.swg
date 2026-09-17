#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func quotientRemainder(value: u64)->u64 => value / 3 + value % 3

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func remainderQuotient(value: u64)->u64 => value % 3 + value / 3

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func direct(value, quotient: u64)->u64 => quotient + (value - quotient * 3)

#test
{
    for value in [0'u64, 1, 2, 3, 17, 0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF]
    {
        Swag.assert(quotientRemainder(value) == value / 3 + value % 3)
        Swag.assert(remainderQuotient(value) == value % 3 + value / 3)
        var quotient = value / 5
        Swag.assert(direct(value, quotient) == quotient + (value - quotient * 3))
    }
}
