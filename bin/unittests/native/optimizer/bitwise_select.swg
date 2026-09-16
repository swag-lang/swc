#global private

#[Swag.NoInline]
func selectBits(a, b, mask: u64)->u64 => (a & mask) | (b & ~mask)

#[Swag.NoInline]
func selectBitsCommuted(a, b, mask: u64)->u64 => (~mask & b) | (mask & a)

#[Swag.NoInline]
func selectBitsXor(a, b, mask: u64)->u64 => (a & mask) ^ (~mask & b)

#[Swag.NoInline]
func selectBits32(a, b, mask: u32)->u32 => (a & mask) | (b & ~mask)

#[Swag.NoInline]
func reusedArm(a, b, mask: u64)->u64
{
    let first = a & mask
    return (first | (b & ~mask)) ^ first
}

#[Swag.NoInline]
func reusedInverse(a, b, mask: u64)->u64
{
    let inverse = ~mask
    return ((a & mask) | (b & inverse)) ^ inverse
}

#[Swag.NoInline]
func differentMasks(a, b, mask: u64)->u64 => (a & mask) | (b & ~(mask << 1))

#test
{
    Swag.assert(differentMasks(0xFF, 0xFF, 1) == 0xFD)
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0xFFFFFFFFFFFFFFFF, 0x5555555555555555, 0xAAAAAAAAAAAAAAAA]
    for a in values
    {
        for b in values
        {
            for mask in values
            {
                let expected = b ^ ((a ^ b) & mask)
                Swag.assert(selectBits(a, b, mask) == expected)
                Swag.assert(selectBitsCommuted(a, b, mask) == expected)
                Swag.assert(selectBitsXor(a, b, mask) == expected)
                let a32 = cast(u32) (a & 0xFFFFFFFF)
                let b32 = cast(u32) (b & 0xFFFFFFFF)
                let m32 = cast(u32) (mask & 0xFFFFFFFF)
                Swag.assert(selectBits32(a32, b32, m32) == cast(u32) (expected & 0xFFFFFFFF))
                Swag.assert(reusedArm(a, b, mask) == (b & ~mask))
                Swag.assert(reusedInverse(a, b, mask) == (expected ^ ~mask))
                Swag.assert(differentMasks(a, b, mask) == ((a & mask) | (b & ~(mask << 1))))
            }
        }
    }
}
