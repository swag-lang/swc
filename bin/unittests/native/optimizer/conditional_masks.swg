#global private

#[Swag.NoInline]
func bit8(a, b: u64)->u64 => a < b ? 256 : 0

#[Swag.NoInline]
func bit32(a, b: u64)->u64 => a < b ? 0x100000000 : 0

#[Swag.NoInline]
func bit63(a, b: u64)->u64 => a < b ? 0x8000000000000000 : 0

#[Swag.NoInline]
func inverseBit(a, b: u64)->u64 => a < b ? 0 : 256

#[Swag.NoInline]
func mask64(a, b: u64)->u64 => a < b ? 0xFFFFFFFFFFFFFFFF : 0

#[Swag.NoInline]
func mask32(a, b: u64)->u32 => a < b ? 0xFFFFFFFF : 0

#[Swag.NoInline]
func signedMask(a, b: s64)->s64 => a < b ? -1 : 0

#[Swag.NoInline]
func multipleUses(a, b: u64)->u64
{
    let first = a < b ? 0x100000000 : 0
    let second = a < b ? 0 : 0x8000000000000000
    return first | second
}

#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            let bit = cast(u64) (a < b)
            Swag.assert(bit8(a, b) == bit << 8)
            Swag.assert(bit32(a, b) == bit << 32)
            Swag.assert(bit63(a, b) == bit << 63)
            Swag.assert(inverseBit(a, b) == (1 - bit) << 8)
            Swag.assert(mask64(a, b) == (bit == 0 ? 0 : ~0'u64))
            Swag.assert(mask32(a, b) == (bit == 0 ? 0 : ~0'u32))
            Swag.assert(multipleUses(a, b) == ((bit << 32) | ((1 - bit) << 63)))
        }
    }
    Swag.assert(signedMask(-0x7FFFFFFFFFFFFFFF - 1, 0x7FFFFFFFFFFFFFFF) == -1)
    Swag.assert(signedMask(0, -1) == 0)
    Swag.assert(signedMask(0, 0) == 0)
}
