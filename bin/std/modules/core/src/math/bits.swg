#global public
#global namespace Math
using Swag

// Lookup table for bit reversal of 8-bit values.
// Each index contains the bit-reversed value of that index (e.g., Rev8Arr[0x01] = 0x80).
private const Rev8Arr: [256] u8 = [
    0x00, 0x80, 0x40, 0xC0, 0x20, 0xA0, 0x60, 0xE0, 0x10, 0x90, 0x50, 0xD0, 0x30, 0xB0, 0x70, 0xF0,
    0x08, 0x88, 0x48, 0xC8, 0x28, 0xA8, 0x68, 0xE8, 0x18, 0x98, 0x58, 0xD8, 0x38, 0xB8, 0x78, 0xF8,
    0x04, 0x84, 0x44, 0xC4, 0x24, 0xA4, 0x64, 0xE4, 0x14, 0x94, 0x54, 0xD4, 0x34, 0xB4, 0x74, 0xF4,
    0x0C, 0x8C, 0x4C, 0xCC, 0x2C, 0xAC, 0x6C, 0xEC, 0x1C, 0x9C, 0x5C, 0xDC, 0x3C, 0xBC, 0x7C, 0xFC,
    0x02, 0x82, 0x42, 0xC2, 0x22, 0xA2, 0x62, 0xE2, 0x12, 0x92, 0x52, 0xD2, 0x32, 0xB2, 0x72, 0xF2,
    0x0A, 0x8A, 0x4A, 0xCA, 0x2A, 0xAA, 0x6A, 0xEA, 0x1A, 0x9A, 0x5A, 0xDA, 0x3A, 0xBA, 0x7A, 0xFA,
    0x06, 0x86, 0x46, 0xC6, 0x26, 0xA6, 0x66, 0xE6, 0x16, 0x96, 0x56, 0xD6, 0x36, 0xB6, 0x76, 0xF6,
    0x0E, 0x8E, 0x4E, 0xCE, 0x2E, 0xAE, 0x6E, 0xEE, 0x1E, 0x9E, 0x5E, 0xDE, 0x3E, 0xBE, 0x7E, 0xFE,
    0x01, 0x81, 0x41, 0xC1, 0x21, 0xA1, 0x61, 0xE1, 0x11, 0x91, 0x51, 0xD1, 0x31, 0xB1, 0x71, 0xF1,
    0x09, 0x89, 0x49, 0xC9, 0x29, 0xA9, 0x69, 0xE9, 0x19, 0x99, 0x59, 0xD9, 0x39, 0xB9, 0x79, 0xF9,
    0x05, 0x85, 0x45, 0xC5, 0x25, 0xA5, 0x65, 0xE5, 0x15, 0x95, 0x55, 0xD5, 0x35, 0xB5, 0x75, 0xF5,
    0x0D, 0x8D, 0x4D, 0xCD, 0x2D, 0xAD, 0x6D, 0xED, 0x1D, 0x9D, 0x5D, 0xDD, 0x3D, 0xBD, 0x7D, 0xFD,
    0x03, 0x83, 0x43, 0xC3, 0x23, 0xA3, 0x63, 0xE3, 0x13, 0x93, 0x53, 0xD3, 0x33, 0xB3, 0x73, 0xF3,
    0x0B, 0x8B, 0x4B, 0xCB, 0x2B, 0xAB, 0x6B, 0xEB, 0x1B, 0x9B, 0x5B, 0xDB, 0x3B, 0xBB, 0x7B, 0xFB,
    0x07, 0x87, 0x47, 0xC7, 0x27, 0xA7, 0x67, 0xE7, 0x17, 0x97, 0x57, 0xD7, 0x37, 0xB7, 0x77, 0xF7,
    0x0F, 0x8F, 0x4F, 0xCF, 0x2F, 0xAF, 0x6F, 0xEF, 0x1F, 0x9F, 0x5F, 0xDF, 0x3F, 0xBF, 0x7F, 0xFF]

#[ConstExpr, Inline]
{
    // Returns the number of leading zero bits from the most significant bit.
    // Counts consecutive zero bits starting from the left (most significant) side.
    func leadingZeros(x: u8)->u8   => @bitcountlz(x)
    func leadingZeros(x: u16)->u16 => @bitcountlz(x)
    func leadingZeros(x: u32)->u32 => @bitcountlz(x)
    func leadingZeros(x: u64)->u64 => @bitcountlz(x)

    // Returns the number of trailing zero bits from the least significant bit.
    // Counts consecutive zero bits starting from the right (least significant) side.
    func trailingZeros(x: u8)->u8   => @bitcounttz(x)
    func trailingZeros(x: u16)->u16 => @bitcounttz(x)
    func trailingZeros(x: u32)->u32 => @bitcounttz(x)
    func trailingZeros(x: u64)->u64 => @bitcounttz(x)

    // Returns the total number of bits set to 1 in the value.
    // Also known as population count or Hamming weight.
    func countOnes(x: u8)->u8   => @bitcountnz(x)
    func countOnes(x: u16)->u16 => @bitcountnz(x)
    func countOnes(x: u32)->u32 => @bitcountnz(x)
    func countOnes(x: u64)->u64 => @bitcountnz(x)

    // Rotate bits left by 'y' positions.
    // Bits that overflow from the left side wrap around to the right side.
    func rol(x: u8, y: u8)  => @rol(x, y)
    func rol(x: u16, y: u8) => @rol(x, y)
    func rol(x: u32, y: u8) => @rol(x, y)
    func rol(x: u64, y: u8) => @rol(x, y)

    // Rotate bits right by 'y' positions.
    // Bits that overflow from the right side wrap around to the left side.
    func ror(x: u8, y: u8)  => @ror(x, y)
    func ror(x: u16, y: u8) => @ror(x, y)
    func ror(x: u32, y: u8) => @ror(x, y)
    func ror(x: u64, y: u8) => @ror(x, y)

    // Reverse the byte order of the value.
    // Converts between little-endian and big-endian representations.
    func byteswap(x: u16) => @byteswap(x)
    func byteswap(x: u32) => @byteswap(x)
    func byteswap(x: u64) => @byteswap(x)
}

// Reverse all bits in an 8-bit value using lookup table.
// Uses the precomputed 'Rev8Arr' table for optimal performance.
#[ConstExpr]
func reverse(x: u8)->u8
{
    return Rev8Arr[x]
}

// Reverse all bits in a 16-bit value.
// Splits the value into two bytes, reverses each using the lookup table, then recombines.
#[ConstExpr]
func reverse(x: u16)->u16
{
    return cast(u16) Rev8Arr[x >> 8] | cast(u16) Rev8Arr[x & 0xFF] << 8
}

// Reverse all bits in a 32-bit value using bit manipulation.
// Uses a series of parallel bit operations with magic constants for efficiency.
#[ConstExpr, Safety(.Overflow, false)]
func reverse(x: u32)->u32
{
    const m0 = 0x55555555     // Binary: 01010101... (alternating bits)
    const m1 = 0x33333333     // Binary: 00110011... (2-bit groups)
    const m2 = 0x0F0F0F0F     // Binary: 00001111... (4-bit groups)
    var v    = ((x >> 1) & m0) | ((x & m0) << 1)
    v = ((v >> 2) & m1) | ((v & m1) << 2)
    v = ((v >> 4) & m2) | ((v & m2) << 4)
    return @byteswap(v)
}

// Reverse all bits in a 64-bit value using bit manipulation.
// Uses the same parallel bit operation technique as the 32-bit version with 64-bit constants.
#[ConstExpr, Safety(.Overflow, false)]
func reverse(x: u64)->u64
{
    const m0 = 0x55555555_55555555     // Binary: 01010101... (alternating bits)
    const m1 = 0x33333333_33333333     // Binary: 00110011... (2-bit groups)
    const m2 = 0x0F0F0F0F_0F0F0F0F     // Binary: 00001111... (4-bit groups)
    var v    = ((x >> 1) & m0) | ((x & m0) << 1)
    v = ((v >> 2) & m1) | ((v & m1) << 2)
    v = ((v >> 4) & m2) | ((v & m2) << 4)
    return @byteswap(v)
}
