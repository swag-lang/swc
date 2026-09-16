#global private

#[Swag.NoInline]
func combined3(a: u64)->u64 => a / 3 + a % 3
#[Swag.NoInline]
func combined7(a: u64)->u64 => a / 7 + a % 7
#[Swag.NoInline]
func combinedSigned(a: s64)->s64 => a / 3 + a % 3
#[Swag.NoInline]
func quotient(a, b: u64)->u64 => a / b
#[Swag.NoInline]
func remainder(a, b: u64)->u64 => a % b
#[Swag.NoInline]
func signedQuotient(a, b: s64)->s64 => a / b
#[Swag.NoInline]
func signedRemainder(a, b: s64)->s64 => a % b
#[Swag.NoInline]
func acrossBranch(a: u64, choose: bool)->u64
{
    let q = a / 3
    let r = a % 3
    return choose ? q + r : q ^ r
}
#[Swag.NoInline]
func carryAfter(a, b: u64)->u64
{
    let result = a / 3 + a % 3
    return result + (a < b ? 1'u64 : 0)
}

#test
{
    let values = [0'u64, 1, 2, 3, 7, 8, 0xFFFFFFFF, 0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        let q = quotient(a, 3)
        let r = remainder(a, 3)
        Swag.assert(combined3(a) == q + r)
        Swag.assert(combined7(a) == quotient(a, 7) + remainder(a, 7))
        let signed = cast #bit (s64) a
        Swag.assert(combinedSigned(signed) == signedQuotient(signed, 3) + signedRemainder(signed, 3))
        Swag.assert(acrossBranch(a, true) == q + r)
        Swag.assert(acrossBranch(a, false) == (q ^ r))
        for b in values
        {
            var expected = q + r
            if a < b do expected += 1
            Swag.assert(carryAfter(a, b) == expected)
        }
    }
}
