#global private

#[Swag.NoInline]
func adjacent(a, b: u64)->u64 => a < b ? 4 : 3
#[Swag.NoInline]
func doubled(a, b: u64)->u64 => a < b ? 5 : 3
#[Swag.NoInline]
func tripled(a, b: u64)->u64 => a < b ? 10 : 7
#[Swag.NoInline]
func quadrupled(a, b: u64)->u64 => a < b ? 7 : 3
#[Swag.NoInline]
func five(a, b: u64)->u64 => a < b ? 12 : 7
#[Swag.NoInline]
func eight(a, b: u64)->u64 => a < b ? 9 : 1
#[Swag.NoInline]
func nine(a, b: u64)->u64 => a < b ? 16 : 7
#[Swag.NoInline]
func reversed(a, b: u64)->u64 => a < b ? 3 : 5
#[Swag.NoInline]
func signedValues(a, b: s64)->s64 => a < b ? -3 : 5
#[Swag.NoInline]
func wrapped(a, b: u64)->u64 => a == b ? 1 : 0xFFFFFFFFFFFFFFFF
#[Swag.NoInline]
func narrow(a, b: u32)->u32 => a == b ? 1 : 0xFFFFFFFF
#[Swag.NoInline]
func reused(a, b: u64)->u64
{
    let selected: u64 = a < b ? 5 : 3
    return selected + (a == b ? 7 : 11)
}

#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            let low = a < b
            Swag.assert(adjacent(a, b) == (low ? 4 : 3))
            Swag.assert(doubled(a, b) == (low ? 5 : 3))
            Swag.assert(tripled(a, b) == (low ? 10 : 7))
            Swag.assert(quadrupled(a, b) == (low ? 7 : 3))
            Swag.assert(five(a, b) == (low ? 12 : 7))
            Swag.assert(eight(a, b) == (low ? 9 : 1))
            Swag.assert(nine(a, b) == (low ? 16 : 7))
            Swag.assert(reversed(a, b) == (low ? 3 : 5))
            Swag.assert(wrapped(a, b) == (a == b ? 1'u64 : 0xFFFFFFFFFFFFFFFF))
            let a32 = cast(u32) (a & 0xFFFFFFFF)
            let b32 = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(narrow(a32, b32) == (a32 == b32 ? 1'u32 : 0xFFFFFFFF))
            Swag.assert(reused(a, b) == (low ? 5'u64 : 3) + (a == b ? 7'u64 : 11))
        }
    }
    Swag.assert(signedValues(-1, 0) == -3)
    Swag.assert(signedValues(0, -1) == 5)
    Swag.assert(signedValues(-1, -1) == 5)
}
