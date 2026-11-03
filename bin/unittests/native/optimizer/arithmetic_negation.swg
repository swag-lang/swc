#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func complementPlusOne(a: u64)->u64 => ~a + 1

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func complementPlusOne32(a: u32)->u32 => ~a + 1

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func multiplyMinusOne(a: u64)->u64 => a * 0xFFFFFFFFFFFFFFFF

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func multiplyMinusOne32(a: u32)->u32 => a * 0xFFFFFFFF

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func signedMultiplyMinusOne(a: s64)->s64 => a * -1

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func sharedComplement(a: u64)->u64
{
    let inverse = ~a
    return (inverse + 1) ^ inverse
}

#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checkedComplementPlusOne(a: u64)->u64 => ~a + 1

#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checkedMultiplyMinusOne(a: s64)->s64 => a * -1

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 2, 0xFFFFFFFF, 0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        let expected = 0'u64 - a
        Swag.require(complementPlusOne(a) == expected)
        Swag.require(multiplyMinusOne(a) == expected)
        Swag.require(sharedComplement(a) == (expected ^ ~a))
        let a32        = cast(u32, (a & 0xFFFFFFFF))
        let expected32 = 0'u32 - a32
        Swag.require(complementPlusOne32(a32) == expected32)
        Swag.require(multiplyMinusOne32(a32) == expected32)
    }
    Swag.require(signedMultiplyMinusOne(-0x7FFFFFFFFFFFFFFF) == 0x7FFFFFFFFFFFFFFF)
    Swag.require(signedMultiplyMinusOne(-0x7FFFFFFFFFFFFFFF - 1) == -0x7FFFFFFFFFFFFFFF - 1)
    Swag.require(checkedComplementPlusOne(1) == 0xFFFFFFFFFFFFFFFF)
    Swag.require(checkedMultiplyMinusOne(-123) == 123)
}
