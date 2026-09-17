#global private

// Masked bytes and words widened to 32 bits: the mask takes over from the
// extension. The bits above the byte hold whatever the register held before,
// so the results must still come from the byte alone.

#[Swag.Optimize(true), Swag.NoInline]
func popcount8(x: u8)->u32
{
    var count = 0'u32
    for i in 0 until 8 do
        count += cast(u32) ((x >> cast(u8) i) & 1)
    return count
}

#[Swag.Optimize(true), Swag.NoInline]
func lowNibbles(a: u8, b: u16)->u32 => cast(u32) (a & 0x0F) + cast(u32) (b & 0xF0F0)

#[Swag.Optimize(true), Swag.NoInline]
func highBit(x: u8)->u64 => cast(u64) (x & 0x80)

#[Swag.Optimize(true), Swag.NoInline]
func mixed(x: u64)->u32
{
    let low = cast #wrap (u8) x
    return cast(u32) ((low >> 2) & 3) + cast(u32) (low & 0x40)
}

func slowPopcount(x: u64)->u32
{
    var count = 0'u32
    var v     = x
    while v != 0
    {
        count += cast(u32) (v & 1)
        v     >>= 1
    }
    return count
}

#test
{
    for v in 0 until 256
    {
        let x = cast(u8) v
        Swag.assert(popcount8(x) == slowPopcount(cast(u64) v))
        Swag.assert(highBit(x) == cast(u64) (v & 0x80))
        let wide = cast(u64) v | 0xABCD_EF00_1234_5600
        Swag.assert(mixed(wide) == cast(u32) (((v >> 2) & 3) + (v & 0x40)))
        let word = cast(u16) (v * 257)
        Swag.assert(lowNibbles(x, word) == cast(u32) (v & 0x0F) + cast(u32) ((v * 257) & 0xF0F0))
    }
}
