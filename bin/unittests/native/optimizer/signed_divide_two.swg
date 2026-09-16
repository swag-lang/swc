#global private

#[Swag.NoInline]
func quotient(a: s64)->s64 => a / 2
#[Swag.NoInline]
func negativeQuotient(a: s64)->s64 => a / -2
#[Swag.NoInline]
func remainder(a: s64)->s64 => a % 2
#[Swag.NoInline]
func negativeRemainder(a: s64)->s64 => a % -2
#[Swag.NoInline]
func quotient32(a: s32)->s32 => a / 2
#[Swag.NoInline]
func remainder32(a: s32)->s32 => a % 2
#[Swag.NoInline]
func divide(a, b: s64)->s64 => a / b
#[Swag.NoInline]
func modulo(a, b: s64)->s64 => a % b
#[Swag.NoInline]
func preserve(a, b, c: s64)->s64 => (a / 2) ^ (b % -2) ^ (c / -2) ^ a ^ b ^ c

#test
{
    let values = [-9223372036854775808's64, -9223372036854775807, -2147483648, -7, -3, -2, -1, 0, 1, 2, 3, 7, 2147483647, 9223372036854775807]
    for a in values
    {
        Swag.assert(quotient(a) == divide(a, 2))
        Swag.assert(negativeQuotient(a) == divide(a, -2))
        Swag.assert(remainder(a) == modulo(a, 2))
        Swag.assert(negativeRemainder(a) == modulo(a, -2))
        for b in values
        {
            Swag.assert(preserve(a, b, ~a) == (divide(a, 2) ^ modulo(b, -2) ^ divide(~a, -2) ^ a ^ b ^ ~a))
        }
    }
    let narrow = [-2147483648's32, -7, -2, -1, 0, 1, 2, 7, 2147483647]
    for a in narrow
    {
        Swag.assert(quotient32(a) == divide(a, 2))
        Swag.assert(remainder32(a) == modulo(a, 2))
    }
}
