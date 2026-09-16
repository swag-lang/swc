#global private

#[Swag.NoInline]
func divide3(a: s64)->s64 => a / 3
#[Swag.NoInline]
func divide5(a: s64)->s64 => a / 5
#[Swag.NoInline]
func divide7(a: s64)->s64 => a / 7
#[Swag.NoInline]
func divideNegative(a: s64)->s64 => a / -3
#[Swag.NoInline]
func remainder3(a: s64)->s64 => a % 3
#[Swag.NoInline]
func remainderNegative(a: s64)->s64 => a % -7
#[Swag.NoInline]
func divide32(a: s32)->s32 => a / 7
#[Swag.NoInline]
func remainder32(a: s32)->s32 => a % -3
#[Swag.NoInline]
func dynamicDivide(a, b: s64)->s64 => a / b
#[Swag.NoInline]
func dynamicRemainder(a, b: s64)->s64 => a % b
#[Swag.NoInline]
func preserve(a, b, c, d: s64)->s64 => (a / 3) ^ (b % -7) ^ (c / 5) ^ (d % 3) ^ a ^ b ^ c ^ d

#test
{
    let values = [-9223372036854775808's64, -9223372036854775807, -2147483648, -8, -7, -6, -3, -1, 0, 1, 2, 3, 5, 6, 7, 8, 2147483647, 9223372036854775807]
    for a in values
    {
        Swag.assert(divide3(a) == dynamicDivide(a, 3))
        Swag.assert(divide5(a) == dynamicDivide(a, 5))
        Swag.assert(divide7(a) == dynamicDivide(a, 7))
        Swag.assert(divideNegative(a) == dynamicDivide(a, -3))
        Swag.assert(remainder3(a) == dynamicRemainder(a, 3))
        Swag.assert(remainderNegative(a) == dynamicRemainder(a, -7))
        for b in values
        {
            let expected = dynamicDivide(a, 3) ^ dynamicRemainder(b, -7) ^ dynamicDivide(~a, 5) ^ dynamicRemainder(~b, 3) ^ a ^ b ^ ~a ^ ~b
            Swag.assert(preserve(a, b, ~a, ~b) == expected)
        }
    }
    let narrow = [-2147483648's32, -7, -3, -1, 0, 1, 3, 7, 2147483647]
    for a in narrow
    {
        Swag.assert(divide32(a) == dynamicDivide(a, 7))
        Swag.assert(remainder32(a) == dynamicRemainder(a, -3))
    }
}
