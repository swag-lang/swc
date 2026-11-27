#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let zero = Math.mulU64(0_u64, 0xFFFF_FFFF_FFFF_FFFF_u64)
    Swag.require(zero.hi == 0_u64)
    Swag.require(zero.lo == 0_u64)

    let lowOnly = Math.mulU64(0xFFFF_FFFF_u64, 0xFFFF_FFFF_u64)
    Swag.require(lowOnly.hi == 0_u64)
    Swag.require(lowOnly.lo == 0xFFFF_FFFE_0000_0001_u64)

    let highOnly = Math.mulU64(0x1_0000_0000_u64, 0x1_0000_0000_u64)
    Swag.require(highOnly.hi == 1_u64)
    Swag.require(highOnly.lo == 0_u64)

    let carry = Math.mulU64(0x8000_0000_0000_0000_u64, 2_u64)
    Swag.require(carry.hi == 1_u64)
    Swag.require(carry.lo == 0_u64)

    let max = Math.mulU64(0xFFFF_FFFF_FFFF_FFFF_u64, 0xFFFF_FFFF_FFFF_FFFF_u64)
    Swag.require(max.hi == 0xFFFF_FFFF_FFFF_FFFE_u64)
    Swag.require(max.lo == 1_u64)
}

#test
{
    let negative = Math.Int128{lo: 0xFFFF_FFFF_FFFF_FFFB_u64, hi: -1_s64}
    let zero     = Math.Int128{lo: 0_u64, hi: 0_s64}
    let one      = Math.Int128{lo: 1_u64, hi: 0_s64}
    let two      = Math.Int128{lo: 2_u64, hi: 0_s64}
    let high     = Math.Int128{lo: 0_u64, hi: 1_s64}

    Swag.require(negative.opCompare(zero) < 0)
    Swag.require(zero.opCompare(negative) > 0)
    Swag.require(one.opCompare(one) == 0)
    Swag.require(two.opCompare(one) > 0)
    Swag.require(one.opCompare(two) < 0)
    Swag.require(high.opCompare(two) > 0)
}

#test
{
    let zero     = Math.Int128{lo: 0_u64, hi: 0_s64}
    let five     = Math.Int128{lo: 5_u64, hi: 0_s64}
    let high     = Math.Int128{lo: 0_u64, hi: 1_s64}
    let negative = Math.Int128{lo: 0xFFFF_FFFF_FFFF_FFFB_u64, hi: -1_s64}
    let lowZero  = Math.Int128{lo: 0_u64, hi: -1_s64}

    let zeroF64     = zero.opCast()
    let fiveF64     = five.opCast()
    let highF64     = high.opCast()
    let negativeF64 = negative.opCast()
    let lowZeroF64  = lowZero.opCast()

    Swag.require(zeroF64 == 0_f64)
    Swag.require(fiveF64 == 5_f64)
    Swag.require(highF64 == 18446744073709551616_f64)
    Swag.require(negativeF64 == -5_f64)
    Swag.require(lowZeroF64 == -18446744073709551616_f64)
}

#test
{
    let zero = Math.Int128.mul(0_s64, -123_s64)
    Swag.require(zero.hi == 0_s64)
    Swag.require(zero.lo == 0_u64)

    let positive = Math.Int128.mul(7_s64, 6_s64)
    Swag.require(positive.hi == 0_s64)
    Swag.require(positive.lo == 42_u64)

    let negativeLeft = Math.Int128.mul(-7_s64, 6_s64)
    Swag.require(negativeLeft.hi == -1_s64)
    Swag.require(negativeLeft.lo == 0xFFFF_FFFF_FFFF_FFD6_u64)

    let negativeRight = Math.Int128.mul(7_s64, -6_s64)
    Swag.require(negativeRight.hi == -1_s64)
    Swag.require(negativeRight.lo == 0xFFFF_FFFF_FFFF_FFD6_u64)

    let negativeBoth = Math.Int128.mul(-7_s64, -6_s64)
    Swag.require(negativeBoth.hi == 0_s64)
    Swag.require(negativeBoth.lo == 42_u64)

    let highPositive = Math.Int128.mul(0x4000_0000_0000_0000_s64, 4_s64)
    Swag.require(highPositive.hi == 1_s64)
    Swag.require(highPositive.lo == 0_u64)

    let highNegative = Math.Int128.mul(-0x4000_0000_0000_0000_s64, 4_s64)
    Swag.require(highNegative.hi == -1_s64)
    Swag.require(highNegative.lo == 0_u64)
}

#test
{
    let minTimesOne = Math.Int128.mul(Swag.S64.Min, 1)
    Swag.require(minTimesOne.hi == -1_s64)
    Swag.require(minTimesOne.lo == 0x8000_0000_0000_0000_u64)

    let minTimesNegativeOne = Math.Int128.mul(Swag.S64.Min, -1)
    Swag.require(minTimesNegativeOne.hi == 0_s64)
    Swag.require(minTimesNegativeOne.lo == 0x8000_0000_0000_0000_u64)

    let minSquared = Math.Int128.mul(Swag.S64.Min, Swag.S64.Min)
    Swag.require(minSquared.hi == 0x4000_0000_0000_0000_s64)
    Swag.require(minSquared.lo == 0_u64)

    let maxTimesOne = Math.Int128.mul(Swag.S64.Max, 1)
    Swag.require(maxTimesOne.hi == 0_s64)
    Swag.require(maxTimesOne.lo == cast(u64, Swag.S64.Max))

    let maxTimesNegativeOne = Math.Int128.mul(Swag.S64.Max, -1)
    Swag.require(maxTimesNegativeOne.hi == -1_s64)
    Swag.require(maxTimesNegativeOne.lo == 0x8000_0000_0000_0001_u64)
}
