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
    const Low32Mask = (1'u64 << 32) - 1
    let xLow  = x & Low32Mask
    let xHigh = x >> 32
    let yLow  = y & Low32Mask
    let yHigh = y >> 32

    // Carry each partial product into the next 32-bit column.
    let lowProduct    = xLow * yLow
    let middleProduct = (xHigh * yLow) + (lowProduct >> 32)
    var middleLow     = middleProduct & Low32Mask
    let middleHigh    = middleProduct >> 32
    middleLow += xLow * yHigh

    with var result: retval
    {
        .hi = (xHigh * yHigh) + middleHigh + (middleLow >> 32)
        .lo = x * y
    }

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
        const Shift64: f64 = cast #bit (f64, 0x43F0000000000000)     // 2^64
        if .hi < 0
        {
            if .lo == 0 do
                return cast(f64, (.hi * Shift64))

            let lo = cast(f64, (~.lo + 1))
            let hi = cast(f64, ~.hi) * Shift64
            return -(lo + hi)
        }

        return cast(f64, (.lo + .hi * Shift64))
    }

    // Returns the exact 128-bit product of `x` and `y`.
    //
    // Unlike a 64-bit multiplication, it cannot overflow, including for `Swag.S64.Min`.
    #[Swag.Safety(.Overflow, false)]
    func mul(x, y: s64)->Int128
    {
        var lhs    = x
        var rhs    = y
        var result: retval
        let negate = (lhs < 0) != (rhs < 0)

        if lhs < 0 do
            lhs = -lhs
        let lhsHigh = cast(u64, lhs) >> 32
        let lhsLow  = cast(u64, (lhs & 0xFFFFFFFF))

        if rhs < 0 do
            rhs = -rhs
        let rhsHigh = cast(u64, rhs) >> 32
        let rhsLow  = cast(u64, (rhs & 0xFFFFFFFF))

        let highProduct  = lhsHigh * rhsHigh
        let lowProduct   = lhsLow * rhsLow
        let crossProduct = lhsHigh * rhsLow + lhsLow * rhsHigh

        // Combine the magnitude, carrying overflow from the low half.
        result.hi = cast(s64, (highProduct + (crossProduct >> 32)))
        result.lo = crossProduct << 32
        result.lo += lowProduct
        if result.lo < lowProduct do
            result.hi += 1

        // Restore the sign in two's complement.
        if negate
        {
            if result.lo == 0
            {
                result.hi = -result.hi
            }
            else
            {
                result.hi = ~result.hi
                result.lo = ~result.lo + 1
            }
        }

        return result
    }
}
