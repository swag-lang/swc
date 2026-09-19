// Several of these bit tricks come from https://graphics.stanford.edu/~seander/bithacks.html

#global export
#global namespace Math

using Swag

#[ConstExpr, Safety(.Overflow, false)]
{
    // Returns the smallest power of two greater than or equal to `x`.
    //
    // Both 0 and 1 answer 1. The result must be representable, so `x` must not exceed the largest
    // power of two of its type.
    func roundUpToPowerOf2(x: u32)->u32 => x <= 1 ? 1 : 1'u32 << (32 - Math.leadingZeros(x - 1))
    func roundUpToPowerOf2(x: u64)->u64 => x <= 1 ? 1 : 1'u64 << cast(u32) (64 - Math.leadingZeros(x - 1))

    // Returns the largest power of two less than or equal to `x`, or 0 when `x` is 0.
    func roundDownToPowerOf2(x: u32)->u32 => x == 0 ? 0 : 1'u32 << (31 - Math.leadingZeros(x))
    func roundDownToPowerOf2(x: u64)->u64 => x == 0 ? 0 : 1'u64 << cast(u32) (63 - Math.leadingZeros(x))

    // Returns whether `x` is a power of two; 0 is not one.
    func isPowerOf2(x: u8)->bool  => x and not (x & (x - 1))
    func isPowerOf2(x: u16)->bool => x and not (x & (x - 1))
    func isPowerOf2(x: u32)->bool => x and not (x & (x - 1))
    func isPowerOf2(x: u64)->bool => x and not (x & (x - 1))
}

// Returns whether any byte of `v` is zero.
#[ConstExpr, Inline, Safety(.Overflow, false)]
func hasZeroByte(v: u16)->bool
{
    let v32 = cast(u32) v
    return cast(bool) ((v32 - #wrap 0x0101'u32) & ~v32 & 0x8080'u32)
}

#[ConstExpr, Inline, Safety(.Overflow, false)]
func hasZeroByte(v: u32)->bool => cast(bool) ((v - #wrap 0x01010101) & ~v & 0x80808080)

#[ConstExpr, Inline, Safety(.Overflow, false)]
func hasZeroByte(v: u64)->bool => cast(bool) ((v - #wrap 0x01010101_01010101) & ~v & 0x80808080_80808080)

// Returns a 16-bit value holding `v` in each of its two bytes.
//
// For example, 0x20 gives 0x2020.
#[ConstExpr, Inline]
func makeRepeat16(v: u8)->u16 => (~0'u16 / 255'u16 * cast(u16) v)

// Returns a 32-bit value holding `v` in each of its four bytes.
//
// For example, 0x20 gives 0x20202020.
#[ConstExpr, Inline]
func makeRepeat32(v: u8)->u32 => (~0'u32 / 255 * v)

// Returns a 64-bit value holding `v` in each of its eight bytes.
//
// For example, 0x20 gives 0x20202020_20202020.
#[ConstExpr, Inline]
func makeRepeat64(v: u8)->u64 => (~0'u64 / 255 * v)

// Returns the 64-bit value whose upper half is `high` and lower half is `low`.
#[ConstExpr, Inline]
func make64(high, low: u32)->u64 => (cast(u64) high << 32) | low

// Returns whether any byte of `value` equals `byte`.
#[ConstExpr, Inline]
func hasByte(value: u16, byte: u8)->bool => hasZeroByte(value ^ makeRepeat16(byte))

#[ConstExpr, Inline]
func hasByte(value: u32, byte: u8)->bool => hasZeroByte(value ^ makeRepeat32(byte))

#[ConstExpr, Inline]
func hasByte(value: u64, byte: u8)->bool => hasZeroByte(value ^ makeRepeat64(byte))

#[ConstExpr, Inline]
{
    // Returns the sign of `x`: -1 when negative, 1 when positive, and 0 for zero.
    func sign(x: s8)  => cast(s8) (x > 0) - cast(s8) (x < 0)
    func sign(x: s16) => cast(s16) (x > 0) - cast(s16) (x < 0)
    func sign(x: s32) => cast(s32) (x > 0) - cast(s32) (x < 0)
    func sign(x: s64) => cast(s64) (x > 0) - cast(s64) (x < 0)
}

#[ConstExpr, Inline]
{
    // Returns the smaller of `x` and `y`.
    func min(x, y: s8)  => Swag.min(x, y)
    func min(x, y: s16) => Swag.min(x, y)
    func min(x, y: s32) => Swag.min(x, y)
    func min(x, y: s64) => Swag.min(x, y)

    // Returns the larger of `x` and `y`.
    func max(x, y: s8)  => Swag.max(x, y)
    func max(x, y: s16) => Swag.max(x, y)
    func max(x, y: s32) => Swag.max(x, y)
    func max(x, y: s64) => Swag.max(x, y)

    func min(x, y: u8)  => Swag.min(x, y)
    func min(x, y: u16) => Swag.min(x, y)
    func min(x, y: u32) => Swag.min(x, y)
    func min(x, y: u64) => Swag.min(x, y)

    func max(x, y: u8)  => Swag.max(x, y)
    func max(x, y: u16) => Swag.max(x, y)
    func max(x, y: u32) => Swag.max(x, y)
    func max(x, y: u64) => Swag.max(x, y)

    // Returns the absolute value of `x`.
    func abs(x: s8)  => Swag.abs(x)
    func abs(x: s16) => Swag.abs(x)
    func abs(x: s32) => Swag.abs(x)
    func abs(x: s64) => Swag.abs(x)
}

// Returns the greatest common divisor of `a` and `b`.
//
// The result is never negative, and `gcd(0, 0)` is 0.
#[ConstExpr]
func gcd(a, b: s64)->s64
{
    var x = a
    var y = b
    while y != 0
    {
        let remainder = x % y
        x = y
        y = remainder
    }

    return abs(x)
}

// Returns the least common multiple of `a` and `b`, or 0 when either is 0.
//
// The result is never negative.
#[ConstExpr]
func lcm(a, b: s64)->s64
{
    if a == 0 or b == 0 do
        return 0
    return abs(a / gcd(a, b) * b)
}
