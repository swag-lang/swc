#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// Bytes reassembled in reverse order are one byte swap. Both widths, any
// order of the terms, and near misses - a byte left in place, a byte taken
// twice - must keep the source answers.

#[Swag.Optimize(true), Swag.NoInline]
func swap32(x: u32)->u32 => (x >> 24) | ((x >> 8) & 0xFF00) | ((x << 8) & 0xFF0000) | (x << 24)

#[Swag.Optimize(true), Swag.NoInline]
func swap32Reordered(x: u32)->u32 => (x << 24) | ((x << 8) & 0xFF0000) | (x >> 24) | ((x >> 8) & 0xFF00)

#[Swag.Optimize(true), Swag.NoInline]
func swap64(x: u64)->u64
{
    return (x >> 56) | ((x >> 40) & 0xFF00) | ((x >> 24) & 0xFF0000) | ((x >> 8) & 0xFF000000) |
           ((x << 8) & 0xFF00000000) | ((x << 24) & 0xFF0000000000) | ((x << 40) & 0xFF000000000000) | (x << 56)
}

#[Swag.Optimize(true), Swag.NoInline]
func notQuite(x: u32)->u32 => (x >> 24) | ((x >> 8) & 0xFF00) | (x & 0xFF0000) | (x << 24)

#[Swag.Optimize(true), Swag.NoInline]
func twice(x: u32)->u32 => (x >> 24) | ((x >> 16) & 0xFF00) | ((x << 8) & 0xFF0000) | (x << 24)

#test
{
    Swag.assert(swap32(0x11223344) == 0x44332211)
    Swag.assert(swap32(0xFF000001) == 0x010000FF)
    Swag.assert(swap32Reordered(0xA1B2C3D4) == 0xD4C3B2A1)
    Swag.assert(swap64(0x0102030405060708) == 0x0807060504030201)
    Swag.assert(swap64(0xFF00000000000000) == 0xFF)
    Swag.assert(notQuite(0x11223344) == 0x44222211)
    Swag.assert(twice(0x11223344) == 0x44331111)
}
