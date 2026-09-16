#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtract(a, b, c: u64)->u64 => a - (b < c ? 1'u64 : 0)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func addInverse(a, b, c: u64)->u64 => a + (b >= c ? 1'u64 : 0)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtractInverse(a, b, c: u64)->u64 => a - (b >= c ? 1'u64 : 0)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtract32(a, b, c: u32)->u32 => a - (b < c ? 1'u32 : 0)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shared(a, b, c: u64)->u64
{
    let bit = b < c ? 1'u64 : 0
    return (a - bit) ^ bit
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func reverseSubtract(a, b, c: u64)->u64 => (b < c ? 1'u64 : 0) - a
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func checked(a, b, c: u64)->u64
{
    let result = a - (b < c ? 1'u64 : 0)
    return result == 0 ? 7 : 11
}
#[Swag.NoInline]
func below(a, b: u64)->bool => a < b

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            for c in values
            {
                var bit = 0'u64
                if below(b, c) do bit = 1
                Swag.assert(subtract(a, b, c) == a - bit)
                Swag.assert(addInverse(a, b, c) == a + (1 - bit))
                Swag.assert(subtractInverse(a, b, c) == a - (1 - bit))
                Swag.assert(shared(a, b, c) == ((a - bit) ^ bit))
                Swag.assert(reverseSubtract(a, b, c) == bit - a)
                if a - bit == 0 do Swag.assert(checked(a, b, c) == 7)
                else do Swag.assert(checked(a, b, c) == 11)
                let a32   = cast(u32) (a & 0xFFFFFFFF)
                let b32   = cast(u32) (b & 0xFFFFFFFF)
                let c32   = cast(u32) (c & 0xFFFFFFFF)
                var bit32 = 0'u32
                if below(b32, c32) do bit32 = 1
                Swag.assert(subtract32(a32, b32, c32) == a32 - bit32)
            }
        }
    }
}
