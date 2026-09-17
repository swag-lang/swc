#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// A rotation written with the width minus the count on its second shift is
// the same rotation as with the negated count. Counts of zero, the width and
// beyond wrap like the instruction does.

#[Swag.Optimize(true), Swag.NoInline]
func rotl32(x, n: u32)->u32 => (x << (n & 31)) | (x >> ((32 - n) & 31))

#[Swag.Optimize(true), Swag.NoInline]
func rotr64(x, n: u64)->u64 => (x >> (n & 63)) | (x << ((64 - n) & 63))

#[Swag.NoInline]
func oracle32(x, n: u32)->u32
{
    var r = x
    for n & 31 do r = (r << 1) | (r >> 31)
    return r
}

#[Swag.NoInline]
func oracle64(x, n: u64)->u64
{
    var r = x
    for n & 63 do r = (r >> 1) | (r << 63)
    return r
}

#test
{
    let counts32 = [0'u32, 1, 7, 31, 32, 33, 100]
    for n in counts32
    {
        Swag.assert(rotl32(0x80000001, n) == oracle32(0x80000001, n))
        Swag.assert(rotl32(0x12345678, n) == oracle32(0x12345678, n))
    }
    let counts64 = [0'u64, 1, 13, 63, 64, 65]
    for n in counts64
    {
        Swag.assert(rotr64(0x8000000000000001, n) == oracle64(0x8000000000000001, n))
        Swag.assert(rotr64(0x0123456789ABCDEF, n) == oracle64(0x0123456789ABCDEF, n))
    }
}
