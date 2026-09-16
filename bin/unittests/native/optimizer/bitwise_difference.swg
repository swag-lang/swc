#global private

#[Swag.NoInline]
func difference(a, b: u64)->u64 => (a | b) - (a & b)
#[Swag.NoInline]
func swapped(a, b: u64)->u64 => (b | a) - (a & b)
#[Swag.NoInline]
func difference32(a, b: u32)->u32 => (a | b) - (b & a)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func reversed(a, b: u64)->u64 => (a & b) - (a | b)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func other(a, b, c: u64)->u64 => (a | b) - (a & c)
#[Swag.NoInline]
func shared(a, b: u64)->u64
{
    let intersection = a & b
    return ((a | b) - intersection) ^ intersection
}
#[Swag.NoInline]
func compared(a, b: u64)->bool => ((a | b) - (a & b)) == 0
#[Swag.NoInline]
func unionValue(a, b: u64)->u64 => a | b
#[Swag.NoInline]
func intersectionValue(a, b: u64)->u64 => a & b

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 7, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xAAAAAAAAAAAAAAAA, 0x5555555555555555, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            Swag.assert(difference(a, b) == (a ^ b))
            Swag.assert(swapped(a, b) == (a ^ b))
            Swag.assert(reversed(a, b) == 0'u64 - (a ^ b))
            Swag.assert(shared(a, b) == unionValue(a, b))
            Swag.assert(compared(a, b) == (a == b))
            Swag.assert(other(a, b, ~b) == unionValue(a, b) - intersectionValue(a, ~b))
            let lowA = cast(u32) (a & 0xFFFFFFFF)
            let lowB = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(difference32(lowA, lowB) == (lowA ^ lowB))
        }
    }
}
