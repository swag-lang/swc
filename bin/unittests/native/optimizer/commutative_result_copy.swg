#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func lowest(a: u64)->u64 => a & (0 - a)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func lowest32(a: u32)->u32 => a & (0 - a)
#[Swag.NoInline]
func orComplement(a, b: u64)->u64 => a | ~b
#[Swag.NoInline]
func xorComplement(a, b: u64)->u64 => a ^ ~b
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func added(a, b: u64)->u64 => a + (b * 7)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func multiplied(a, b: u64)->u64 => a * (b + 7)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func preserve(a, b: u64)->u64
{
    let isolated = a & (0 - a)
    if b != 0 do return isolated ^ a
    return isolated
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func compared(a: u64)->bool => (a & (0 - a)) == 0
#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checked(a, b: u64)->u64 => a + b * 7

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 7, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        let isolated = a & (~a + 1)
        Swag.assert(lowest(a) == isolated)
        Swag.assert(lowest32(cast(u32) (a & 0xFFFFFFFF)) == cast(u32) (isolated & 0xFFFFFFFF))
        Swag.assert(compared(a) == (a == 0))
        for b in values
        {
            Swag.assert(orComplement(a, b) == (a | ~b))
            Swag.assert(xorComplement(a, b) == (a ^ ~b))
            Swag.assert(added(a, b) == a + b * 7)
            Swag.assert(multiplied(a, b) == a * (b + 7))
            Swag.assert(preserve(a, b) == (b != 0 ? isolated ^ a : isolated))
        }
    }
    Swag.assert(checked(9, 11) == 86)
}
