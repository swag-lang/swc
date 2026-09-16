#global private

#[Swag.NoInline]
func unionMasks(a: u64)->u64 => (a & 0xFF) | (a & 0xFF00)

#[Swag.NoInline]
func intersectMasks(a: u64)->u64 => (a & 0xFF) & (a & 0xF0F0)

#[Swag.NoInline]
func xorMasks(a: u64)->u64 => (a & 0xFF) ^ (a & 0xF0F0)

#[Swag.NoInline]
func highMasks(a: u64)->u64 => (a & 0xFFFF000000000000) | (a & 0xFFFF)

#[Swag.NoInline]
func unionMasks32(a: u32)->u32 => (a & 0xFF) | (a & 0xFF00)

#[Swag.NoInline]
func disjointMasks(a: u32)->u32 => (a & 0xFF) & (a & 0xFF00)

#[Swag.NoInline]
func reusedMask(a: u64)->u64
{
    let low = a & 0xFF
    return ((low | (a & 0xFF00)) << 8) | low
}

#[Swag.NoInline]
func differentInputs(a, b: u64)->u64 => (a & 0xFF) | (b & 0xFF00)

#[Swag.NoInline]
func maskedBranch(a: u64)->s32
{
    if ((a & 0xFF) ^ (a & 0xF0F0)) == 0 do
        return 11
    return 27
}

#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0xFFFFFFFFFFFFFFFF, 0x5555555555555555, 0xAAAAAAAAAAAAAAAA, 0x0123456789ABCDEF]
    for a in values
    {
        Swag.assert(unionMasks(a) == (a & 0xFFFF))
        Swag.assert(intersectMasks(a) == (a & 0xF0))
        Swag.assert(xorMasks(a) == (a & 0xF00F))
        Swag.assert(highMasks(a) == (a & 0xFFFF00000000FFFF))
        let a32 = cast(u32) (a & 0xFFFFFFFF)
        Swag.assert(unionMasks32(a32) == (a32 & 0xFFFF))
        Swag.assert(disjointMasks(a32) == 0)
        Swag.assert(reusedMask(a) == (((a & 0xFFFF) << 8) | (a & 0xFF)))
        Swag.assert(maskedBranch(a) == ((a & 0xF00F) == 0 ? 11 : 27))
        for b in values do
            Swag.assert(differentInputs(a, b) == ((a & 0xFF) + (b & 0xFF00)))
    }
}
