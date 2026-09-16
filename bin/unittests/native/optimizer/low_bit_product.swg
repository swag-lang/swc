#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func low(a, b: u64)->u64 => (a & 1) * b
#[Swag.NoInline]
func reversed(a, b: u64)->u64 => b * (a & 1)
#[Swag.NoInline]
func narrow(a, b: u32)->u32 => (a & 1) * b
#[Swag.NoInline]
func same(a: u64)->u64 => (a & 1) * a
#[Swag.NoInline]
func shifted(a, b: u64)->u64 => ((a >> 17) & 1) * b
#[Swag.NoInline]
func sharedInput(a, b: u64)->u64 => ((a & 1) * b) ^ a
#[Swag.NoInline]
func sharedMask(a, b: u64)->u64
{
    let bit = a & 1
    return bit * b + bit
}
#[Swag.NoInline]
func signed(a, b: s64)->s64 => (a & 1) * b
#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checked(a, b: u64)->u64 => (a & 1) * b

#test
{
    let values = [0'u64, 1, 2, 3, 0x20000, 0x20001, 0xFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        let odd = (a & 1) != 0
        Swag.assert(same(a) == (odd ? a : 0))
        for b in values
        {
            let expected = odd ? b : 0
            Swag.assert(low(a, b) == expected)
            Swag.assert(reversed(a, b) == expected)
            Swag.assert(narrow(cast(u32) (a & 0xFFFFFFFF), cast(u32) (b & 0xFFFFFFFF)) == cast(u32) (expected & 0xFFFFFFFF))
            Swag.assert(shifted(a, b) == ((a & 0x20000) != 0 ? b : 0))
            Swag.assert(sharedInput(a, b) == (expected ^ a))
            Swag.assert(sharedMask(a, b) == expected + (a & 1))
            Swag.assert(signed(cast #bit(s64) a, cast #bit(s64) b) == cast #bit(s64) expected)
            Swag.assert(checked(a, b) == expected)
        }
    }
}
