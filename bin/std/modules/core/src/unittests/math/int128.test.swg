#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

#test
{
    let zero = Math.mulU64(0'u64, 0xFFFF_FFFF_FFFF_FFFF'u64)
    @assert(zero.hi == 0'u64)
    @assert(zero.lo == 0'u64)

    let lowOnly = Math.mulU64(0xFFFF_FFFF'u64, 0xFFFF_FFFF'u64)
    @assert(lowOnly.hi == 0'u64)
    @assert(lowOnly.lo == 0xFFFF_FFFE_0000_0001'u64)

    let highOnly = Math.mulU64(0x1_0000_0000'u64, 0x1_0000_0000'u64)
    @assert(highOnly.hi == 1'u64)
    @assert(highOnly.lo == 0'u64)

    let carry = Math.mulU64(0x8000_0000_0000_0000'u64, 2'u64)
    @assert(carry.hi == 1'u64)
    @assert(carry.lo == 0'u64)

    let max = Math.mulU64(0xFFFF_FFFF_FFFF_FFFF'u64, 0xFFFF_FFFF_FFFF_FFFF'u64)
    @assert(max.hi == 0xFFFF_FFFF_FFFF_FFFE'u64)
    @assert(max.lo == 1'u64)
}

#test
{
    let negative = Math.Int128{lo: 0xFFFF_FFFF_FFFF_FFFB'u64, hi: -1's64}
    let zero     = Math.Int128{lo: 0'u64, hi: 0's64}
    let one      = Math.Int128{lo: 1'u64, hi: 0's64}
    let two      = Math.Int128{lo: 2'u64, hi: 0's64}
    let high     = Math.Int128{lo: 0'u64, hi: 1's64}

    @assert(negative.opCompare(zero) < 0)
    @assert(zero.opCompare(negative) > 0)
    @assert(one.opCompare(one) == 0)
    @assert(two.opCompare(one) > 0)
    @assert(one.opCompare(two) < 0)
    @assert(high.opCompare(two) > 0)
}

#test
{
    let zero     = Math.Int128{lo: 0'u64, hi: 0's64}
    let five     = Math.Int128{lo: 5'u64, hi: 0's64}
    let high     = Math.Int128{lo: 0'u64, hi: 1's64}
    let negative = Math.Int128{lo: 0xFFFF_FFFF_FFFF_FFFB'u64, hi: -1's64}
    let lowZero  = Math.Int128{lo: 0'u64, hi: -1's64}

    let zeroF64     = zero.opCast()
    let fiveF64     = five.opCast()
    let highF64     = high.opCast()
    let negativeF64 = negative.opCast()
    let lowZeroF64  = lowZero.opCast()

    @assert(zeroF64 == 0'f64)
    @assert(fiveF64 == 5'f64)
    @assert(highF64 == 18446744073709551616'f64)
    @assert(negativeF64 == -5'f64)
    @assert(lowZeroF64 == -18446744073709551616'f64)
}

#test
{
    let zero = Math.Int128.mul(0's64, -123's64)
    @assert(zero.hi == 0's64)
    @assert(zero.lo == 0'u64)

    let positive = Math.Int128.mul(7's64, 6's64)
    @assert(positive.hi == 0's64)
    @assert(positive.lo == 42'u64)

    let negativeLeft = Math.Int128.mul(-7's64, 6's64)
    @assert(negativeLeft.hi == -1's64)
    @assert(negativeLeft.lo == 0xFFFF_FFFF_FFFF_FFD6'u64)

    let negativeRight = Math.Int128.mul(7's64, -6's64)
    @assert(negativeRight.hi == -1's64)
    @assert(negativeRight.lo == 0xFFFF_FFFF_FFFF_FFD6'u64)

    let negativeBoth = Math.Int128.mul(-7's64, -6's64)
    @assert(negativeBoth.hi == 0's64)
    @assert(negativeBoth.lo == 42'u64)

    let highPositive = Math.Int128.mul(0x4000_0000_0000_0000's64, 4's64)
    @assert(highPositive.hi == 1's64)
    @assert(highPositive.lo == 0'u64)

    let highNegative = Math.Int128.mul(-0x4000_0000_0000_0000's64, 4's64)
    @assert(highNegative.hi == -1's64)
    @assert(highNegative.lo == 0'u64)
}
