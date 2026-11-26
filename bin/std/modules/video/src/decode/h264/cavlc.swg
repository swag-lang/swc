//! Format: H.264/AVC decoder component.
//! Supported: Progressive 8-bit 4:2:0 and 4:4:4 Baseline, Main, High, and High 4:4:4 Predictive streams with CAVLC/CABAC, I/P/B slices, weighted prediction, cropping, reordering, and deblocking.
//! Not supported: Interlacing, 4:2:2 chroma, bit depths above 8, slice groups, data partitioning, scalable/multiview extensions, and lossless transform bypass.
//! Role: This file owns CAVLC residual decoding.
//
#global namespace H264
#global internal

using Core, Core.Errors

// CAVLC residual decoding, section 9.2. Coefficients come out in scan order, highest index
// first, exactly as the syntax carries them; the caller maps scan positions and dequantizes.

// A leaf packs the consumed bit count and the zero-based symbol plus one.
// A marked primary entry instead packs the suffix width and its table offset.
private const VlcSubtable = 0x8000'u16

private struct CoeffTokenLookup
{
    primary: [4 * 256] u16
    tails:   [364] u16     // Expanded entries for the long-code prefixes of the four syntax tables.
}

private const CoeffTokens = #run buildCoeffTokens()

private func buildCoeffTokens()->CoeffTokenLookup
{
    var result: CoeffTokenLookup
    var nextTail = 0'u32
    for table in 4'u64
    {
        let length = cast(u32, lengths[index])
        if length == 0
        {
            continue
        }

        if (peek >> (16 - length)) == cast(u32, values[index])
        {
            let length = cast(u32, CoeffTokenLen[codes + symbol])
            if length > 8
            {
                let prefix = cast(u32, CoeffTokenBits[codes + symbol]) >> (length - 8)
                widths[prefix] = Math.max(widths[prefix], length - 8)
            }
        }

        for width, prefix in widths where width
        {
            result.primary[first + prefix] = VlcSubtable | cast(u16, ((width << 9) | nextTail))
            nextTail += 1'u32 << width
        }

        for symbol in 68'u64
        {
            let length = cast(u32, CoeffTokenLen[codes + symbol])
            if not length do
                continue

            let code = cast(u32, CoeffTokenBits[codes + symbol])
            let leaf = cast(u16, ((length << 8) | cast(u32, symbol + 1)))
            if length <= 8
            {
                let size = 1'u32 << (8 - length)
                for suffix in size do
                    result.primary[first + code * size + suffix] = leaf
            }
            else
            {
                let prefix = code >> (length - 8)
                let width  = widths[prefix]
                let tail   = code & ((1'u32 << (length - 8)) - 1)
                let offset = cast(u32, (result.primary[first + prefix] & 0x1FF))
                let size   = 1'u32 << (8 + width - length)
                for suffix in size do
                    result.tails[offset + tail * size + suffix] = leaf
            }
        }
    }

    Swag.require(nextTail == result.tails.count)
    return result
}

private func(const Rows: u64, const Width: u64) buildVlcLookup(lengths, codes: const [..] u8)->[Rows * (1 << Width)] u16
{
    var result: #returntype
    for table in 4_u64
    {
        for prefix in 256_u64
        {
            for index in 68_u64
            {
                let offset = table * 68 + index
                let length = cast(u32, CoeffTokenLen[offset])
                let value  = cast(u32, CoeffTokenBits[offset])
                if not length
                {
                    continue
                }

                if length > 8
                {
                    if value >> (length - 8) == prefix
                    {
                        break
                    }
                }
                else if prefix >> (8 - length) == value
                {
                    result[table * 256 + prefix] = cast(u16, ((length << 8) | cast(u32, (index + 1))))
                    break
                }
            }
        }
    }

    return result
}

private const ChromaTokens     = #run buildVlcLookup'(1, 8)(ChromaDcCoeffTokenLen, ChromaDcCoeffTokenBits)
private const FirstTotalZeros  = #run buildVlcLookup'(1, 9)(TotalZerosLen[0 until 16], TotalZerosBits[0 until 16])
private const OtherTotalZeros  = #run buildVlcLookup'(14, 6)(TotalZerosLen[16 until 240], TotalZerosBits[16 until 240])
private const ChromaTotalZeros = #run buildVlcLookup'(3, 3)(ChromaDcTotalZerosLen, ChromaDcTotalZerosBits)
private const ShortRuns        = #run buildVlcLookup'(6, 3)(RunBeforeLen[0 until 96], RunBeforeBits[0 until 96])
private const LongRuns         = #run buildVlcLookup'(1, 11)(RunBeforeLen[96 until 112], RunBeforeBits[96 until 112])

#[Swag.Inline]
private func readVlcLeaf(bits: *BitReader, leaf: u16, missing: u64)->u64
{
    if not leaf do
        return missing
    bits.skip(cast(u32, (leaf >> 8)))
    return cast(u64, ((leaf & 255) - 1))
}

func matchCoeffToken(bits: *BitReader, table: u64)->u64
{
    let peek = bits.peek16()
    var leaf = CoeffTokens.primary[table * 256 + (peek >> 8)]
    if leaf & VlcSubtable
    {
        let width  = cast(u32, ((leaf >> 9) & 15))
        let suffix = (peek & 255) >> (8 - width)
        leaf = CoeffTokens.tails[cast(u32, (leaf & 0x1FF)) + suffix]
    }

    return readVlcLeaf(bits, leaf, 68)
}

// Decodes one CAVLC residual block into `coeffs`, filled in scan order.
//
// `nC` is the predicted nonzero count of section 9.2.1, with -1 selecting the chroma DC
// table. Returns the number of nonzero coefficients.
func(const MaxCoeffs: u32) residualCavlc(bits: *BitReader, nC: s32, coeffs: [*] s16)->u32 fail
{
    for index in cast(u64, maxCoeffs)
    {
        coeffs[index] = 0
    }

    // coeff_token: total coefficients and trailing ones.
    var totalCoeff   = 0_u32
    var trailingOnes = 0_u32
    if nC == -1
    {
        let index = matchVlc(bits, ChromaDcCoeffTokenLen, ChromaDcCoeffTokenBits)
        if index == ChromaDcCoeffTokenLen.count
        {
            fail InvalidFormatError{"H.264 chroma DC coefficient token does not decode"}
        }

        totalCoeff   = cast(u32, (index / 4))
        trailingOnes = cast(u32, (index % 4))
    }
    else
    {
        var table = 3_u64
        if nC < 2
        {
            table = 0
        }
        else if nC < 4
        {
            table = 1
        }
        else if nC < 8
        {
            table = 2
        }

        let index = matchCoeffToken(bits, table)
        if index == 68
        {
            fail InvalidFormatError{"H.264 coefficient token does not decode"}
        }

        totalCoeff   = cast(u32, (index / 4))
        trailingOnes = cast(u32, (index % 4))
    }

    if totalCoeff > maxCoeffs
    {
        fail InvalidFormatError{"H.264 block declares more coefficients than it can hold"}
    }

    if totalCoeff == 0
    {
        return 0
    }

    // Levels, most significant coefficient first.
    var levels: [16] s32
    for index in cast(u64, trailingOnes)
    {
        levels[index] = bits.bit() != 0 ? -1 : 1
    }

    var suffixLength = totalCoeff > 10 and trailingOnes < 3 ? 1_u32 : 0_u32
    for index in cast(u64, trailingOnes) until cast(u64, totalCoeff)
    {
        // level_prefix: leading zeros before a one.
        var prefix = 0_u32
        while bits.bit() == 0
        {
            prefix += 1
            if prefix > 31 or bits.overran
            {
                fail InvalidFormatError{"H.264 coefficient level prefix does not decode"}
            }
        }

        var suffixSize = suffixLength
        if prefix == 14 and suffixLength == 0
        {
            suffixSize = 4
        }
        else if prefix >= 15
        {
            suffixSize = prefix - 3
        }

        var levelCode = cast(s32, (Math.min(15, prefix) << suffixLength))
        if suffixSize > 0
        {
            levelCode += cast(s32, bits.read(suffixSize))
        }

        if prefix >= 15 and suffixLength == 0
        {
            levelCode += 15
        }

        if prefix >= 16
        {
            levelCode += (1_s32 << (prefix - 3)) - 4096
        }

        if index == cast(u64, trailingOnes) and trailingOnes < 3
        {
            levelCode += 2
        }

        levels[index] = levelCode % 2 == 0 ? (levelCode + 2) >> 1 : -((levelCode + 1) >> 1)

        if suffixLength == 0
        {
            suffixLength = 1
        }

        if Math.abs(levels[index]) > (3_s32 << (suffixLength - 1)) and suffixLength < 6
        {
            suffixLength += 1
        }
    }

    // total_zeros.
    var totalZeros = 0_u32
    if totalCoeff < maxCoeffs
    {
        if nC == -1
        {
            let row   = cast(u64, (totalCoeff - 1)) * 4
            let index = matchVlc(bits, ChromaDcTotalZerosLen[row until row + 4], ChromaDcTotalZerosBits[row until row + 4])
            if index == 4
            {
                fail InvalidFormatError{"H.264 chroma DC zero count does not decode"}
            }

            totalZeros = cast(u32, index)
        }
        else
        {
            let row   = cast(u64, (totalCoeff - 1)) * 16
            let index = matchVlc(bits, TotalZerosLen[row until row + 16], TotalZerosBits[row until row + 16])
            if index == 16
            {
                fail InvalidFormatError{"H.264 zero count does not decode"}
            }

            totalZeros = cast(u32, index)
        }
    }

    // Placement from the highest scan position down, decoding the zero run before each
    // coefficient except the lowest one.
    var position  = totalCoeff + totalZeros - 1
    var zerosLeft = totalZeros
    for index in cast(u64, totalCoeff)
    {
        if position >= maxCoeffs
        {
            fail InvalidFormatError{"H.264 coefficient runs place a coefficient out of range"}
        }

        coeffs[position] = cast(s16, Math.clamp(levels[index], -32768, 32767))

        if index + 1 == cast(u64, totalCoeff)
        {
            break
        }

        var run = 0_u32
        if zerosLeft > 0
        {
            let row     = cast(u64, Math.min(zerosLeft - 1, 6)) * 16
            let matched = matchVlc(bits, RunBeforeLen[row until row + 16], RunBeforeBits[row until row + 16])
            if matched == 16
            {
                fail InvalidFormatError{"H.264 coefficient run does not decode"}
            }

            run = cast(u32, matched)
        }

        if run > zerosLeft
        {
            fail InvalidFormatError{"H.264 coefficient run exceeds the remaining zeros"}
        }

        zerosLeft -= run
        if position < run + 1
        {
            fail InvalidFormatError{"H.264 coefficient runs place a coefficient out of range"}
        }

        position -= run + 1
    }

    if bits.overran
    {
        fail InvalidFormatError{"H.264 residual block is truncated"}
    }

    return totalCoeff
}
