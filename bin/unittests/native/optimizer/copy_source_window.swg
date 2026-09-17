#global private

#[Swag.NoInline]
func combine(a, b, mask: u64)->u64 => b ^ ((a ^ b) & mask)

#[Swag.NoInline]
func changeSource(a, b: u64)->u64
{
    var current  = b
    let snapshot = current
    current ^= 0x55
    return (a ^ snapshot) & current
}

#[Swag.NoInline]
func helper(a, b: u64)->u64 => a ^ b

#[Swag.NoInline]
func acrossCall(a, b, mask: u64)->u64
{
    let value = helper(a, b)
    return (value & mask) ^ b
}

#[Swag.NoInline]
func acrossBranch(a, b, mask: u64)->u64
{
    var value = a ^ b
    var other = b
    if mask == 0 do
        other = ~other
    else do
        value &= mask
    return value ^ other
}

#[Swag.NoInline]
func narrowSnapshot(a: u32, b: u64)->u64
{
    let byte = cast(u8) (a & 255)
    return (cast(u64) byte << 32) ^ b
}

#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0xFFFFFFFFFFFFFFFF, 0x5555555555555555, 0xAAAAAAAAAAAAAAAA]
    for a in values
    {
        for b in values
        {
            Swag.assert(changeSource(a, b) == ((a ^ b) & (b ^ 0x55)))
            let a32 = cast(u32) (a & 0xFFFFFFFF)
            Swag.assert(narrowSnapshot(a32, b) == (((a & 255) << 32) ^ b))
            for mask in values
            {
                let selected = (a & mask) | (b & ~mask)
                Swag.assert(combine(a, b, mask) == selected)
                Swag.assert(acrossCall(a, b, mask) == selected)
                Swag.assert(acrossBranch(a, b, mask) == (mask == 0 ? ~a : selected))
            }
        }
    }
}
