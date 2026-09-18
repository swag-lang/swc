// @LICENCE: BSD-3-Clause
// @ORIGIN: Go standard library, https://github.com/golang/go
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#go-standard-library

#global public
#global namespace Math

using Swag

// Returns the full 128-bit product of `x` and `y`, split into its high and low 64-bit halves.
#[Swag.Safety(.Overflow, false)]
func mulU64(x, y: u64)->{ hi: u64, lo: u64 }
{
    const mask32 = (1'u64 << 32) - 1
    let x0 = x & mask32
    let x1 = x >> 32
    let y0 = y & mask32
    let y1 = y >> 32
    let w0 = x0 * y0
    let t  = (x1 * y0) + (w0 >> 32)
    var w1 = t & mask32
    let w2 = t >> 32
    w1 += x0 * y1

    var result: retval
    result.hi = (x1 * y1) + w2 + (w1 >> 32)
    result.lo = x * y
    return result
}

// Stores a signed 128-bit integer in two's complement, as two 64-bit halves.
struct Int128
{
    public
    {
        lo: u64     // Low 64 bits
        hi: s64     // High 64 bits, which carry the sign
    }
}

impl Int128
{
    // Returns a negative value, zero, or a positive value as this value is less than, equal to, or greater than `other`.
    mtd const opCompare(other: Int128)->s32
    {
        if .hi != other.hi do
            return .hi <=> other.hi
        return .lo <=> other.lo
    }

    // Returns this value converted to `f64`.
    //
    // Values beyond 2^53 in magnitude lose their low bits, as with any conversion to `f64`.
    mtd const opCast()->f64
    {
        const Shift64: f64 = cast #bit (f64) 0x43F0000000000000     // 2^64
        if .hi < 0
        {
            if .lo == 0 do
                return cast(f64) (.hi * Shift64)

            let lo = cast(f64) (~.lo + 1)
            let hi = cast(f64) ~.hi * Shift64
            return -(lo + hi)
        }

        return cast(f64) (.lo + .hi * Shift64)
    }

    // Returns the exact 128-bit product of `x` and `y`.
    //
    // Unlike a 64-bit multiplication, it cannot overflow, including for `Swag.S64.Min`.
    #[Swag.Safety(.Overflow, false)]
    func mul(x, y: s64)->Int128
    {
        var lhs = x
        var rhs = y

        var result: retval

        let negate = (lhs < 0) != (rhs < 0)

        if lhs < 0 do
            lhs = -lhs
        let int1Hi = cast(u64) lhs >> 32
        let int1Lo = cast(u64) (lhs & 0xFFFFFFFF)

        if rhs < 0 do
            rhs = -rhs
        let int2Hi = cast(u64) rhs >> 32
        let int2Lo = cast(u64) (rhs & 0xFFFFFFFF)

        let a = int1Hi * int2Hi
        let b = int1Lo * int2Lo
        let c = int1Hi * int2Lo + int1Lo * int2Hi

        result.hi = cast(s64) (a + (c >> 32))
        result.lo = c << 32
        result.lo += b
        if result.lo < b do
            result.hi += 1

        if negate
        {
            if result.lo == 0 do
                result.hi = -result.hi
            else
            {
                result.hi = ~result.hi
                result.lo = ~result.lo + 1
            }
        }

        return result
    }
}
