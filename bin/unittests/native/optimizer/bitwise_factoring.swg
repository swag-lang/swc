#global private

#[Swag.NoInline]
func sharedMask64(a, b, c: u64)->u64 => (a & b) ^ (a & c)

#[Swag.NoInline]
func sharedMask32(a, b, c: u32)->u32 => (a & b) ^ (a & c)

#[Swag.NoInline]
func changedMask(a, b, c: u64)->u64
{
    let first   = a & b
    let changed = a ^ 0xFF00FF00FF00FF00
    return first ^ (changed & c)
}

#[Swag.NoInline]
func reusedMask(a, b, c: u64)->u64
{
    let first = a & b
    return (first ^ (a & c)) + first
}

#test
{
    Swag.assert(sharedMask64(0, 0xFFFFFFFFFFFFFFFF, 0) == 0)
    Swag.assert(sharedMask64(0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0) == 0xFFFFFFFFFFFFFFFF)
    Swag.assert(sharedMask64(0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF) == 0)
    Swag.assert(sharedMask64(0x123456789ABCDEF0, 0xFF00FF00FF00FF00, 0x0F0F0F0F0F0F0F0F) == 0x10045008900CD000)
    Swag.assert(sharedMask32(0, 0xFFFFFFFF, 0) == 0)
    Swag.assert(sharedMask32(0xFFFFFFFF, 0xFFFFFFFF, 0) == 0xFFFFFFFF)
    Swag.assert(sharedMask32(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF) == 0)
    Swag.assert(sharedMask32(0xF1234567, 0x0FF00FF0, 0xFF00FF00) == 0xF0204060)
    Swag.assert(changedMask(0x123456789ABCDEF0, 0xFF00FF00FF00FF00, 0x0F0F0F0F0F0F0F0F) == 0x1F045F089F0CDF00)
    Swag.assert(reusedMask(0x123456789ABCDEF0, 0xFF00FF00FF00FF00, 0x0F0F0F0F0F0F0F0F) == 0x2204A6092A0DAE00)
}
