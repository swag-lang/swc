#global private

#[Swag.NoInline]
func byte8(a: u64)->u64 => (a >> 8) & 0xFF
#[Swag.NoInline]
func word8(a: u64)->u64 => (a >> 8) & 0xFFFF
#[Swag.NoInline]
func byte24(a: u64)->u64 => (a >> 24) & 0xFF
#[Swag.NoInline]
func word16(a: u64)->u64 => (a >> 16) & 0xFFFF
#[Swag.NoInline]
func byte25(a: u64)->u64 => (a >> 25) & 0xFF
#[Swag.NoInline]
func word17(a: u64)->u64 => (a >> 17) & 0xFFFF
#[Swag.NoInline]
func preserved(a: u64)->u64
{
    let shifted = a >> 8
    return (shifted & 0xFFFF) ^ shifted
}
#[Swag.NoInline]
func variable(a, count, mask: u64)->u64 => (a >> count) & mask

#test
{
    let values = [0'u64, 1, 0xFF00, 0xFF000000, 0x100000000, 0xABCDEF0123456789, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        Swag.assert(byte8(a) == variable(a, 8, 0xFF))
        Swag.assert(word8(a) == variable(a, 8, 0xFFFF))
        Swag.assert(byte24(a) == variable(a, 24, 0xFF))
        Swag.assert(word16(a) == variable(a, 16, 0xFFFF))
        Swag.assert(byte25(a) == variable(a, 25, 0xFF))
        Swag.assert(word17(a) == variable(a, 17, 0xFFFF))
        Swag.assert(preserved(a) == variable(a, 8, 0xFFFFFFFFFFFF0000))
    }
}
