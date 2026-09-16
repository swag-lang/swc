#global private

#[Swag.NoInline]
func cancelComplements64(a, b: u64)->u64 => ~a ^ ~b

#[Swag.NoInline]
func cancelComplements32(a, b: u32)->u32 => ~a ^ ~b

#[Swag.NoInline]
func reusedComplement(a, b: u64)->u64
{
    let first = ~a
    return (first ^ ~b) & first
}

#[Swag.NoInline]
func complementBranch(a, b: u64)->s32
{
    if (~a ^ ~b) == 0 do
        return 11
    return 27
}

#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0xFFFFFFFFFFFFFFFF, 0x5555555555555555, 0xAAAAAAAAAAAAAAAA]
    for a in values
    {
        for b in values
        {
            Swag.assert(cancelComplements64(a, b) == (a ^ b))
            let a32 = cast(u32) (a & 0xFFFFFFFF)
            let b32 = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(cancelComplements32(a32, b32) == (a32 ^ b32))
            Swag.assert(reusedComplement(a, b) == (~a & b))
            Swag.assert(complementBranch(a, b) == (a == b ? 11 : 27))
        }
    }
}
