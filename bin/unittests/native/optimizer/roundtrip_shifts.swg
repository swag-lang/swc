#global private

#[Swag.NoInline]
func rounded(a: u64)->u64 => (a >> 3) << 3
#[Swag.NoInline]
func roundedSigned(a: s64)->s64 => (a >> 3) << 3
#[Swag.NoInline]
func rounded32(a: u32)->u32 => (a >> 3) << 3
#[Swag.NoInline]
func roundedSigned32(a: s32)->s32 => (a >> 3) << 3
#[Swag.NoInline]
func roundedOne(a: u64)->u64 => (a >> 1) << 1
#[Swag.NoInline]
func rounded31(a: s64)->s64 => (a >> 31) << 31
#[Swag.NoInline]
func shared(a: u64)->u64
{
    let high = a >> 3
    return (high << 3) ^ high
}
#[Swag.NoInline]
func remainderTwo(a: s64)->s64 => a % 2
#[Swag.NoInline]
func remainderEight(a: s64)->s64 => a % 8
#[Swag.NoInline]
func remainderNegativeEight(a: s64)->s64 => a % -8
#[Swag.NoInline]
func dynamicRemainder(a, b: s64)->s64 => a % b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func copiedAdd(a: u64)->u64 => (a + 3) + 5
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func copiedMultiply(a: u64)->u64 => (a * 7) * 11

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 7, 8, 9, 0xFFFFFFFF, 0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        Swag.require(copiedAdd(a) == a + 8)
        Swag.require(copiedMultiply(a) == a * 77)
        let signed = cast #bit (s64, a)
        Swag.require(rounded(a) == (a & 0xFFFFFFFFFFFFFFF8))
        Swag.require(cast #bit (u64, roundedSigned(signed)) == (a & 0xFFFFFFFFFFFFFFF8))
        Swag.require(roundedOne(a) == (a & 0xFFFFFFFFFFFFFFFE))
        Swag.require(cast #bit (u64, rounded31(signed)) == (a & 0xFFFFFFFF80000000))
        Swag.require(shared(a) == ((a & 0xFFFFFFFFFFFFFFF8) ^ (a >> 3)))
        let narrow = cast(u32, (a & 0xFFFFFFFF))
        Swag.require(rounded32(narrow) == (narrow & 0xFFFFFFF8))
        Swag.require(cast #bit (u32, roundedSigned32(cast #bit (s32, narrow))) == (narrow & 0xFFFFFFF8))
        Swag.require(remainderTwo(signed) == dynamicRemainder(signed, 2))
        Swag.require(remainderEight(signed) == dynamicRemainder(signed, 8))
        Swag.require(remainderNegativeEight(signed) == dynamicRemainder(signed, -8))
    }
}
