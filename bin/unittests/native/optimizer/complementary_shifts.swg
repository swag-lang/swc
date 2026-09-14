#global private

#[Swag.NoInline]
func pair32(value: u32)->u32 => (value >> 6) | (value << 26)

#[Swag.NoInline]
func pair64(value: u64)->u64 => (value << 13) | (value >> 51)

#[Swag.NoInline]
func widenedPair(value: u32)->u32
{
    let wide = cast(u64) value
    return cast(u32) (((wide >> 6) | (wide << 26)) & 0xFFFFFFFF)
}

#[Swag.NoInline]
func unknownWidePair(value: u64)->u32 => cast(u32) (((value >> 6) | (value << 26)) & 0xFFFFFFFF)

#test
{
    for value in [0'u32, 1, 0x80000000, 0xFFFFFFFF, 0x12345678]
    {
        Swag.assert(pair32(value) == Swag.ror(value, 6'u8))
        Swag.assert(widenedPair(value) == Swag.ror(value, 6'u8))
    }
    for value in [0'u64, 1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF, 0x0123456789ABCDEF] do
        Swag.assert(pair64(value) == Swag.rol(value, 13'u8))
    // Truncating the result does not prove that the input's high bits are zero.
    Swag.assert(unknownWidePair(0x100000000) == 0x04000000)
}
