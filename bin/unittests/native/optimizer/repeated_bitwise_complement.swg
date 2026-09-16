#global private

#[Swag.NoInline]
func xorOr(a, b: u64)->u64 => a ^ (a | b)
#[Swag.NoInline]
func orXor(a, b: u64)->u64 => (a | b) ^ a
#[Swag.NoInline]
func andXor(a, b: u64)->u64 => a & (a ^ b)
#[Swag.NoInline]
func xorAnd(a, b: u64)->u64 => (a ^ b) & a
#[Swag.NoInline]
func xorOr32(a, b: u32)->u32 => a ^ (a | b)
#[Swag.NoInline]
func andXor32(a, b: u32)->u32 => a & (a ^ b)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shared(a, b: u64)->u64
{
    let combined = a | b
    return (a ^ combined) + combined
}
#[Swag.NoInline]
func compared(a, b: u64)->bool => (a ^ (a | b)) == 0
#[Swag.NoInline]
func nested(a, b, c: u64)->u64 => (a ^ (a | b)) & (c ^ (c | b))

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 7, 0xFFFFFFFF, 0x100000000, 0xAAAAAAAAAAAAAAAA, 0x5555555555555555, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            Swag.assert(xorOr(a, b) == (~a & b))
            Swag.assert(orXor(a, b) == (~a & b))
            Swag.assert(andXor(a, b) == (a & ~b))
            Swag.assert(xorAnd(a, b) == (a & ~b))
            let lowA = cast(u32) (a & 0xFFFFFFFF)
            let lowB = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(xorOr32(lowA, lowB) == (~lowA & lowB))
            Swag.assert(andXor32(lowA, lowB) == (lowA & ~lowB))
            Swag.assert(shared(a, b) == ((~a & b) + (a | b)))
            Swag.assert(compared(a, b) == ((~a & b) == 0))
            Swag.assert(nested(a, b, ~a) == 0)
        }
    }
}
