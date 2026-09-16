#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func positive(a: s64)->u64
{
    let raw = cast #bit (u64) a
    return a < 0 ? 0'u64 - raw : raw
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func positiveStrict(a: s64)->u64
{
    let raw = cast #bit (u64) a
    return a > 0 ? raw : 0'u64 - raw
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func negative(a: s64)->s64 => a < 0 ? a : 0 - a
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func negativeInclusive(a: s64)->s64 => a <= 0 ? a : 0 - a
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func positive32(a: s32)->u32
{
    let raw = cast #bit (u32) a
    return a < 0 ? 0'u32 - raw : raw
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shared(a: s64)->u64
{
    let raw = cast #bit (u64) a
    return (a < 0 ? 0'u64 - raw : raw) ^ raw
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func sharedCondition(a: s64)->u64
{
    let raw  = cast #bit (u64) a
    let less = a < 0
    return (less ? 0'u64 - raw : raw) ^ (less ? 1'u64 : 0)
}

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 7, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0x8000000000000001, 0xFFFFFFFFFFFFFFFF]
    for raw in values
    {
        let sign     = raw >> 63
        let mask     = 0'u64 - sign
        let expected = (raw ^ mask) + sign
        let value    = cast #bit (s64) raw
        Swag.assert(positive(value) == expected)
        Swag.assert(positiveStrict(value) == expected)
        Swag.assert(cast #bit (u64) negative(value) == 0'u64 - expected)
        Swag.assert(cast #bit (u64) negativeInclusive(value) == 0'u64 - expected)
        Swag.assert(shared(value) == (expected ^ raw))
        Swag.assert(sharedCondition(value) == (expected ^ sign))
        let low     = cast(u32) (raw & 0xFFFFFFFF)
        let lowSign = low >> 31
        let lowMask = 0'u32 - lowSign
        Swag.assert(positive32(cast #bit (s32) low) == (low ^ lowMask) + lowSign)
    }
}
