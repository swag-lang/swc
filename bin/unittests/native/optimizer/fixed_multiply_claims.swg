#global private

// Constant quotients lower to RAX/RDX multiply-high sequences. The multiplier
// may die in RDX, but inputs still used after the multiply must survive it.
#[Swag.Optimize(true), Swag.NoInline]
func quotient32(value: u32)->u32 => value / 7
#[Swag.Optimize(true), Swag.NoInline]
func quotient64(value: u64)->u64 => value / 7
#[Swag.Optimize(true), Swag.NoInline]
func signedQuotient(value: s64)->s64 => value / 11
#[Swag.Optimize(true), Swag.NoInline]
func carriedInputs(first, second: u64)->u64 => (first / 7) ^ (second / 11) ^ first ^ second

#[Swag.Optimize(false), Swag.NoInline]
func unsignedReference(value, divisor: u64)->u64 => value / divisor
#[Swag.Optimize(false), Swag.NoInline]
func signedReference(value, divisor: s64)->s64 => value / divisor

#test
{
    for value in [0'u64, 1, 6, 7, 8, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF,
                  0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    {
        let narrow = cast #wrap (u32) value
        Swag.assert(quotient32(narrow) == unsignedReference(narrow, 7))
        Swag.assert(quotient64(value) == unsignedReference(value, 7))
        let second   = value ^ 0x123456789ABCDEF0
        let expected = unsignedReference(value, 7) ^ unsignedReference(second, 11) ^ value ^ second
        Swag.assert(carriedInputs(value, second) == expected)
    }
    for value in [-9223372036854775807's64, -2147483648, -12, -11, -10, -1, 0, 1, 10, 11, 12, 2147483647, 9223372036854775807] do
        Swag.assert(signedQuotient(value) == signedReference(value, 11))
}
