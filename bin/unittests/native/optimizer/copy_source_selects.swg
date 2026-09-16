#global private

#[Swag.NoInline]
func minimum(a, b: u64)->u64 => a < b ? a : b

#[Swag.NoInline]
func maximum(a, b: u64)->u64 => a > b ? a : b

#[Swag.NoInline]
func signedMinimum(a, b: s32)->s32 => a < b ? a : b

#[Swag.NoInline]
func twoSelections(a, b, c: u64)->u64
{
    let first = a < b ? a : b
    let second = b > c ? b : c
    return first ^ second ^ b
}

#[Swag.NoInline]
func retainOriginal(a, b: u64)->u64
{
    let saved = b
    var changed = b
    changed ^= 0xABCD
    return (a < changed ? a : saved) ^ changed
}

#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            var lo = a
            var hi = b
            if a > b
            {
                lo = b
                hi = a
            }
            Swag.assert(minimum(a, b) == lo)
            Swag.assert(maximum(a, b) == hi)
            let changed = b ^ 0xABCD
            Swag.assert(retainOriginal(a, b) == ((a < changed ? a : b) ^ changed))
            for c in values do
                Swag.assert(twoSelections(a, b, c) == (lo ^ (b > c ? b : c) ^ b))
        }
    }
    Swag.assert(signedMinimum(-0x7FFFFFFF - 1, 0x7FFFFFFF) == -0x7FFFFFFF - 1)
    Swag.assert(signedMinimum(17, -31) == -31)
}
