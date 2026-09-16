#global private

#[Swag.NoInline]
func mask(a, b: u64)->u64 => a < b ? 0xFFFFFFFFFFFFFFFF : 0
#[Swag.NoInline]
func mask32(a, b: u32)->u32 => a < b ? 0xFFFFFFFF : 0
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func sum(a, b, c: u64)->u64 => (a < b ? 1'u64 : 0) + c
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func sum32(a, b, c: u32)->u32 => (a < b ? 1'u32 : 0) + c
#[Swag.NoInline]
func offset(a, b: u64)->u64 => a < b ? 4 : 3
#[Swag.NoInline]
func largeOffset(a, b: u64)->u64 => a < b ? 0x12345679 : 0x12345678
#[Swag.NoInline]
func negativeOffset(a, b: u64)->s64 => a < b ? -3 : -4
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func shared(a, b, c: u64)->u64
{
    let low: u64 = a < b ? 1 : 0
    return (low + c) ^ low
}
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func checked(a, b, c: u64)->u64
{
    let total = (a < b ? 1'u64 : 0) + c
    return total == 0 ? 7 : 11
}
#[Swag.NoInline]
func twice(a, b, c: u64)->u64 => (a < b ? 1'u64 : 0) + (b < c ? 1'u64 : 0)
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
            var bit = 0'u64
            if below(a, b)
            {
                bit = 1
                Swag.assert(mask(a, b) == 0xFFFFFFFFFFFFFFFF)
                Swag.assert(offset(a, b) == 4)
                Swag.assert(largeOffset(a, b) == 0x12345679)
                Swag.assert(negativeOffset(a, b) == -3)
            }
            else
            {
                Swag.assert(mask(a, b) == 0)
                Swag.assert(offset(a, b) == 3)
                Swag.assert(largeOffset(a, b) == 0x12345678)
                Swag.assert(negativeOffset(a, b) == -4)
            }
            let a32   = cast(u32) (a & 0xFFFFFFFF)
            let b32   = cast(u32) (b & 0xFFFFFFFF)
            var bit32 = 0'u32
            if below(a32, b32)
            {
                bit32 = 1
                Swag.assert(mask32(a32, b32) == 0xFFFFFFFF)
            }
            else do Swag.assert(mask32(a32, b32) == 0)
            for c in values
            {
                Swag.assert(sum(a, b, c) == c + bit)
                Swag.assert(shared(a, b, c) == ((c + bit) ^ bit))
                let c32 = cast(u32) (c & 0xFFFFFFFF)
                Swag.assert(sum32(a32, b32, c32) == c32 + bit32)
                if c + bit == 0 do Swag.assert(checked(a, b, c) == 7)
                else do Swag.assert(checked(a, b, c) == 11)
                var expected = bit
                if below(b, c) do expected += 1
                Swag.assert(twice(a, b, c) == expected)
            }
        }
    }
}
