//! Format: H.264/AVC decoder component.
//! Supported: Progressive 8-bit 4:2:0 Baseline, Main, and High-profile streams with CAVLC/CABAC, I/P/B slices, weighted prediction, cropping, reordering, and deblocking.
//! Not supported: Interlacing, non-4:2:0 chroma, bit depths above 8, slice groups, data partitioning, scalable/multiview extensions, and lossless transform bypass.
//! Role: This file owns CAVLC residual decoding.
//
#global namespace H264
#global internal

using Core, Core.Errors

// CAVLC residual decoding, section 9.2. Coefficients come out in scan order, highest index
// first, exactly as the syntax carries them; the caller maps scan positions and dequantizes.

// Matches one variable-length code against a `(length, value)` table slice.
//
// Returns the matched entry index, or the entry count when nothing matches, which a valid
// stream never produces.
private func matchVlc(bits: *BitReader, lengths, values: const [..] u8)->u64
{
    let peek  = bits.peek16()
    let count = lengths.count
    for index in count
    {
        let length = cast(u32) lengths[index]
        if length == 0 do
            continue
        if (peek >> (16 - length)) == cast(u32) values[index]
        {
            bits.skip(length)
            return index
        }
    }

    return count
}

// Decodes one CAVLC residual block into `coeffs`, filled in scan order.
//
// `nC` is the predicted nonzero count of section 9.2.1, with -1 selecting the chroma DC
// table. Returns the number of nonzero coefficients.
func residualCavlc(bits: *BitReader, nC: s32, maxCoeffs: u32, coeffs: [*] s16)->u32 fail
{
    for index in cast(u64) maxCoeffs do
        coeffs[index] = 0

    // coeff_token: total coefficients and trailing ones.
    var totalCoeff   = 0'u32
    var trailingOnes = 0'u32
    if nC == -1
    {
        let index = matchVlc(bits, ChromaDcCoeffTokenLen, ChromaDcCoeffTokenBits)
        if index == ChromaDcCoeffTokenLen.count do
            fail InvalidFormatError{"H.264 chroma DC coefficient token does not decode"}
        totalCoeff   = cast(u32) (index / 4)
        trailingOnes = cast(u32) (index % 4)
    }
    else
    {
        var table = 3'u64
        if nC < 2 do
            table = 0
        elif nC < 4 do
            table = 1
        elif nC < 8 do
            table = 2
        let index = matchVlc(bits, CoeffTokenLen[table * 68 until table * 68 + 68], CoeffTokenBits[table * 68 until table * 68 + 68])
        if index == 68 do
            fail InvalidFormatError{"H.264 coefficient token does not decode"}
        totalCoeff   = cast(u32) (index / 4)
        trailingOnes = cast(u32) (index % 4)
    }

    if totalCoeff > maxCoeffs do
        fail InvalidFormatError{"H.264 block declares more coefficients than it can hold"}
    if totalCoeff == 0 do
        return 0

    // Levels, most significant coefficient first.
    var levels: [16] s32 = undefined
    for index in cast(u64) trailingOnes do
        levels[index] = bits.bit() != 0 ? -1 : 1

    var suffixLength = totalCoeff > 10 and trailingOnes < 3 ? 1'u32 : 0'u32
    for index in cast(u64) trailingOnes until cast(u64) totalCoeff
    {
        // level_prefix: leading zeros before a one.
        var prefix = 0'u32
        while bits.bit() == 0
        {
            prefix += 1
            if prefix > 31 or bits.overran do
                fail InvalidFormatError{"H.264 coefficient level prefix does not decode"}
        }

        var suffixSize = suffixLength
        if prefix == 14 and suffixLength == 0 do
            suffixSize = 4
        elif prefix >= 15 do
            suffixSize = prefix - 3

        var levelCode = cast(s32) (Math.min(15, prefix) << suffixLength)
        if suffixSize > 0 do
            levelCode += cast(s32) bits.read(suffixSize)
        if prefix >= 15 and suffixLength == 0 do
            levelCode += 15
        if prefix >= 16 do
            levelCode += (1's32 << (prefix - 3)) - 4096

        if index == cast(u64) trailingOnes and trailingOnes < 3 do
            levelCode += 2

        levels[index] = levelCode % 2 == 0 ? (levelCode + 2) >> 1 : -((levelCode + 1) >> 1)

        if suffixLength == 0 do
            suffixLength = 1
        if Math.abs(levels[index]) > (3's32 << (suffixLength - 1)) and suffixLength < 6 do
            suffixLength += 1
    }

    // total_zeros.
    var totalZeros = 0'u32
    if totalCoeff < maxCoeffs
    {
        if nC == -1
        {
            let row   = cast(u64) (totalCoeff - 1) * 4
            let index = matchVlc(bits, ChromaDcTotalZerosLen[row until row + 4], ChromaDcTotalZerosBits[row until row + 4])
            if index == 4 do
                fail InvalidFormatError{"H.264 chroma DC zero count does not decode"}
            totalZeros = cast(u32) index
        }
        else
        {
            let row   = cast(u64) (totalCoeff - 1) * 16
            let index = matchVlc(bits, TotalZerosLen[row until row + 16], TotalZerosBits[row until row + 16])
            if index == 16 do
                fail InvalidFormatError{"H.264 zero count does not decode"}
            totalZeros = cast(u32) index
        }
    }

    // Placement from the highest scan position down, decoding the zero run before each
    // coefficient except the lowest one.
    var position  = totalCoeff + totalZeros - 1
    var zerosLeft = totalZeros
    for index in cast(u64) totalCoeff
    {
        if position >= maxCoeffs do
            fail InvalidFormatError{"H.264 coefficient runs place a coefficient out of range"}
        coeffs[position] = cast(s16) Math.clamp(levels[index], -32768, 32767)

        if index + 1 == cast(u64) totalCoeff do
            break

        var run = 0'u32
        if zerosLeft > 0
        {
            let row     = cast(u64) Math.min(zerosLeft - 1, 6) * 16
            let matched = matchVlc(bits, RunBeforeLen[row until row + 16], RunBeforeBits[row until row + 16])
            if matched == 16 do
                fail InvalidFormatError{"H.264 coefficient run does not decode"}
            run = cast(u32) matched
        }

        if run > zerosLeft do
            fail InvalidFormatError{"H.264 coefficient run exceeds the remaining zeros"}
        zerosLeft -= run
        if position < run + 1 do
            fail InvalidFormatError{"H.264 coefficient runs place a coefficient out of range"}
        position -= run + 1
    }

    if bits.overran do
        fail InvalidFormatError{"H.264 residual block is truncated"}
    return totalCoeff
}
