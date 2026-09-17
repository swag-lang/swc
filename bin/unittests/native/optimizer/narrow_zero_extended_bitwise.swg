#global private

#[Swag.NoInline]
func or64(a, b: u8)->u64 => cast(u64) (a) | cast(u64) (b)

#[Swag.NoInline]
func xor64(a, b: u8)->u64 => cast(u64) (a) ^ cast(u64) (b)

#[Swag.NoInline]
func and32(a, b: u8)->u32 => cast(u32) (a) & cast(u32) (b)

#test
{
    let values = [0'u8, 1, 0x80, 0xFF]
    for a in values
    {
        for b in values
        {
            Swag.assert(or64(a, b) == cast(u64) (a | b))
            Swag.assert(xor64(a, b) == cast(u64) (a ^ b))
            Swag.assert(and32(a, b) == cast(u32) (a & b))
        }
    }
}
