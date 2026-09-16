#global private

#[Swag.NoInline]
func rightComplement(a, b: u64)->u64 => a ^ ~b

#[Swag.NoInline]
func leftComplement(a, b: u64)->u64 => ~a ^ b

#[Swag.NoInline]
func rightComplement32(a, b: u32)->u32 => a ^ ~b

#[Swag.NoInline]
func sharedComplement(a, b: u64)->u64
{
    let inverse = ~b
    return (a ^ inverse) & inverse
}

#[Swag.NoInline]
func complementBranch(a, b: u64)->s32
{
    if (a ^ ~b) == 0 do
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
            Swag.assert(rightComplement(a, b) == ~(a ^ b))
            Swag.assert(leftComplement(a, b) == ~(a ^ b))
            let a32 = cast(u32) (a & 0xFFFFFFFF)
            let b32 = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(rightComplement32(a32, b32) == ~(a32 ^ b32))
            Swag.assert(sharedComplement(a, b) == (~a & ~b))
            Swag.assert(complementBranch(a, b) == (a == ~b ? 11 : 27))
        }
    }
}
