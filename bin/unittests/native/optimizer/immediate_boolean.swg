#global private

#[Swag.NoInline]
func zero(a: u64)->u64 => a == 0 ? 1 : 0
#[Swag.NoInline]
func nonzero(a: u64)->u64 => a != 0 ? 1 : 0
#[Swag.NoInline]
func lessTen(a: u64)->u64 => a < 10 ? 1 : 0
#[Swag.NoInline]
func bitThree(a: u64)->u64 => (a & 8) != 0 ? 1 : 0
#[Swag.NoInline]
func small(a: u16)->u32 => a < 10 ? 1 : 0
#[Swag.NoInline]
func negative(a: s64)->u64 => a < 0 ? 1 : 0
#[Swag.NoInline]
func reused(a: u64)->u64
{
    let masked     = a & 8
    let isSet: u64 = masked != 0 ? 1 : 0
    return masked ^ isSet ^ a
}

#test
{
    let values = [0'u64, 1, 7, 8, 9, 10, 15, 16, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        let isZero: u64 = a == 0 ? 1 : 0
        let bit:    u64 = (a >> 3) & 1
        Swag.assert(zero(a) == isZero)
        Swag.assert(nonzero(a) == 1 - isZero)
        Swag.assert(lessTen(a) == (a < 10 ? 1 : 0))
        Swag.assert(bitThree(a) == bit)
        Swag.assert(reused(a) == ((a & 8) ^ bit ^ a))
        let narrow = cast(u16) (a & 65535)
        Swag.assert(small(narrow) == (narrow < 10 ? 1 : 0))
    }
    Swag.assert(negative(-0x7FFFFFFFFFFFFFFF - 1) == 1)
    Swag.assert(negative(-1) == 1)
    Swag.assert(negative(0) == 0)
    Swag.assert(negative(0x7FFFFFFFFFFFFFFF) == 0)
}
