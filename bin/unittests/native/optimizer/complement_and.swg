#global private

// A complement consumed by an AND: `~a & b` in both widths, the SHA-256 choice function
// whose complement is masked to 32 bits inside a 64-bit word, and a complement whose
// source stays live after it.

const M32 = 0xFFFFFFFF'u64

#[Swag.Optimize(true), Swag.NoInline]
func clearBits(flags, mask: u64)->u64 => flags & ~mask

#[Swag.Optimize(true), Swag.NoInline]
func clearBits32(flags, mask: u32)->u32 => ~mask & flags

#[Swag.Optimize(true), Swag.NoInline]
func choose(e, f, g: u64)->u64 => (e & f) ^ ((~e & M32) & g)

#[Swag.Optimize(true), Swag.NoInline]
func keepSource(a, b: u64)->u64 => (~a & b) ^ a

#test
{
    for value in [0'u64, 1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF, 0x0123456789ABCDEF]
    {
        for mask in [0'u64, 0xFF, 0xF0F0F0F0F0F0F0F0, 0xFFFFFFFFFFFFFFFF]
        {
            Swag.assert(clearBits(value, mask) == (value & (mask ^ 0xFFFFFFFFFFFFFFFF)))
            Swag.assert(keepSource(mask, value) == (((mask ^ 0xFFFFFFFFFFFFFFFF) & value) ^ mask))
            let lowValue = cast(u32, value & M32)
            let lowMask  = cast(u32, mask & M32)
            Swag.assert(clearBits32(lowValue, lowMask) == (lowValue & (lowMask ^ 0xFFFFFFFF)))
        }
    }

    let e = 0x510E527F'u64
    let f = 0x9B05688C'u64
    let g = 0xFFFFFFFF1F83D9AB'u64
    Swag.assert(choose(e, f, g) == ((e & f) ^ ((e ^ M32) & g & M32)))
}
