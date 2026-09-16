#global private

#[Swag.NoInline]
func unsignedMask(a, b: u64)->u64 => a < b ? 0xFFFFFFFFFFFFFFFF : 0

#[Swag.NoInline]
func signedMask(a, b: s64)->s64 => a >= b ? -1 : 0

#[Swag.NoInline]
func unsignedMask32(a, b: u32)->u32 => a < b ? 0xFFFFFFFF : 0

#[Swag.NoInline]
func immediateMask(a: u64)->u64 => a < 123 ? 0xFFFFFFFFFFFFFFFF : 0

#[Swag.NoInline]
func reusedInput(a, b: u64)->u64
{
    let selected = a < b ? 0xFFFFFFFFFFFFFFFF : 0
    return selected ^ a ^ b
}

#test
{
    let values = [0'u64, 1, 122, 123, 124, 0xFFFFFFFF, 0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        Swag.assert(immediateMask(a) == (a < 123 ? 0xFFFFFFFFFFFFFFFF : 0))
        for b in values
        {
            let expected = a < b ? 0xFFFFFFFFFFFFFFFF'u64 : 0
            Swag.assert(unsignedMask(a, b) == expected)
            Swag.assert(reusedInput(a, b) == (expected ^ a ^ b))
            let a32 = cast(u32) (a & 0xFFFFFFFF)
            let b32 = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(unsignedMask32(a32, b32) == (a32 < b32 ? 0xFFFFFFFF : 0))
        }
    }
    Swag.assert(signedMask(-1, 0) == 0)
    Swag.assert(signedMask(0, -1) == -1)
    Swag.assert(signedMask(-7, -7) == -1)
    Swag.assert(signedMask(-0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF) == 0)
}
