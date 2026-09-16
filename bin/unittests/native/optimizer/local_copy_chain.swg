#global private

#[Swag.NoInline]
func remainder(a: u64)->u64 => a % 3
#[Swag.NoInline]
func signedRemainder(a: s64)->s64 => a % 3
#[Swag.NoInline]
func signedDivide(a: s64)->s64 => a / 7
#[Swag.NoInline]
func dynamicRemainder(a, divisor: u64)->u64 => a % divisor
#[Swag.NoInline]
func dynamicSignedRemainder(a, divisor: s64)->s64 => a % divisor
#[Swag.NoInline]
func dynamicSignedDivide(a, divisor: s64)->s64 => a / divisor

#[Swag.NoInline]
func keepSource(a, b: u64)->u64 => (a % 3) ^ a ^ (b % 3) ^ b

#[Swag.NoInline]
func branchSource(a, b: u64, choose: bool)->u64
{
    let reduced = a % 3
    return choose ? reduced ^ a : reduced ^ b
}

#[Swag.NoInline]
func callSource(a, b: u64)->u64
{
    let first  = a % 3
    let second = dynamicRemainder(b, 7)
    return first ^ second ^ a ^ b
}

#[Swag.NoInline]
func loopSource(a: u64, count: u32)->u64
{
    var value = a
    for i in count do
        value = (value % 3) ^ a ^ cast(u64) i
    return value
}

#test
{
    let values = [0'u64, 1, 2, 3, 7, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        Swag.assert(remainder(a) == dynamicRemainder(a, 3))
        for b in values
        {
            let reduced = dynamicRemainder(a, 3)
            Swag.assert(keepSource(a, b) == (reduced ^ a ^ dynamicRemainder(b, 3) ^ b))
            Swag.assert(branchSource(a, b, true) == (reduced ^ a))
            Swag.assert(branchSource(a, b, false) == (reduced ^ b))
            Swag.assert(callSource(a, b) == (reduced ^ dynamicRemainder(b, 7) ^ a ^ b))
        }
        var expected = a
        for i in 9 do
            expected = dynamicRemainder(expected, 3) ^ a ^ cast(u64) i
        Swag.assert(loopSource(a, 9) == expected)
    }
    let signedValues = [-9223372036854775808's64, -9223372036854775807, -8, -7, -3, -1, 0, 1, 3, 7, 8, 9223372036854775807]
    for a in signedValues
    {
        Swag.assert(signedRemainder(a) == dynamicSignedRemainder(a, 3))
        Swag.assert(signedDivide(a) == dynamicSignedDivide(a, 7))
    }
}
