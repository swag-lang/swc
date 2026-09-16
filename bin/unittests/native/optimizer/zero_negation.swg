#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func negate(a: u64)->u64 => 0 - a
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func negate32(a: u32)->u32 => 0 - a
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func signedNegate(a: s64)->s64 => 0 - a
#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checkedNegate(a: s64)->s64 => 0 - a
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func nonzero(a: u64)->u64 => 7 - a
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shared(a, b: u64)->u64 => (0 - a) ^ b ^ a
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func isolated(a: u64)->u64 => a & (0 - a)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func sum(a, b: u64)->u64 => (0 - a) + (0 - b)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func isZero(a: u64)->bool => (0 - a) == 0

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 7, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        let expected = ~a + 1
        Swag.assert(negate(a) == expected)
        Swag.assert(cast #bit (u64) signedNegate(cast #bit (s64) a) == expected)
        if a != 0x8000000000000000 do Swag.assert(cast #bit (u64) checkedNegate(cast #bit (s64) a) == expected)
        Swag.assert(nonzero(a) == 7'u64 + expected)
        Swag.assert(isolated(a) == (a & expected))
        Swag.assert(isZero(a) == (a == 0))
        let lowA = cast(u32) (a & 0xFFFFFFFF)
        Swag.assert(negate32(lowA) == ~lowA + 1)
        for b in values
        {
            Swag.assert(shared(a, b) == (expected ^ b ^ a))
            Swag.assert(sum(a, b) == expected + (~b + 1))
        }
    }
}
