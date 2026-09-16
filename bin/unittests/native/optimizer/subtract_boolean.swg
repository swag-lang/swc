#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func equal64(a, b: u64)->u64 => cast(u64) (a - b == 0)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func different32(a, b: u32)->u32 => cast(u32) (a - b != 0)

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func signedDifference(a, b: s64)->u64 => cast(u64) (a - b < 0)

#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checkedEqual(a, b: s64)->u64 => cast(u64) (a - b == 0)

#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            Swag.assert(equal64(a, b) == (a == b ? 1 : 0))
            let a32 = cast(u32) (a & 0xFFFFFFFF)
            let b32 = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(different32(a32, b32) == (a32 != b32 ? 1 : 0))
        }
    }
    Swag.assert(signedDifference(-1, 1) == 1)
    Swag.assert(signedDifference(1, -1) == 0)
    Swag.assert(signedDifference(-0x7FFFFFFFFFFFFFFF - 1, 1) == 0)
    Swag.assert(signedDifference(0x7FFFFFFFFFFFFFFF, -1) == 1)
    Swag.assert(checkedEqual(-42, -42) == 1)
    Swag.assert(checkedEqual(42, -42) == 0)
}
