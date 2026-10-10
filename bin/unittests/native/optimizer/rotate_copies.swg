#global private

// Several rotations of one value that stays live: each rotation reads the value into a
// copy of its own, which a rotate naming its destination separately does without. Both
// directions and both widths, with the rotated value and the source used afterwards.

#[Swag.Optimize(true), Swag.NoInline]
func sigma32(x: u32)->u32 => Swag.ror(x, 6'u8) ^ Swag.ror(x, 11'u8) ^ Swag.ror(x, 25'u8) ^ x

#[Swag.Optimize(true), Swag.NoInline]
func sigma64(x: u64)->u64 => Swag.rol(x, 13'u8) ^ Swag.rol(x, 51'u8) ^ Swag.ror(x, 7'u8) ^ x

#[Swag.Optimize(true), Swag.NoInline]
func rotateBoth(x: u32)->u64
{
    let left  = Swag.rol(x, 9'u8)
    let right = Swag.ror(x, 9'u8)
    return (cast(u64, left) << 32) | right
}

func refRor32(x: u32, k: u32)->u32 => (x >> k) | (x << (32 - k))
func refRol64(x: u64, k: u64)->u64 => (x << k) | (x >> (64 - k))

#test
{
    for x in [0x12345678'u32, 0x80000001, 0xFFFFFFFF, 0, 0xDEADBEEF]
    {
        Swag.assert(sigma32(x) == (refRor32(x, 6) ^ refRor32(x, 11) ^ refRor32(x, 25) ^ x))
        Swag.assert(rotateBoth(x) == ((cast(u64, refRor32(x, 23)) << 32) | refRor32(x, 9)))
    }

    for x in [0x0123456789ABCDEF'u64, 0x8000000000000001, 0xFFFFFFFFFFFFFFFF, 0] do
        Swag.assert(sigma64(x) == (refRol64(x, 13) ^ refRol64(x, 51) ^ refRol64(x, 57) ^ x))
}
