//! Format: H.264/AVC bitstream writing.
//! Supported: Exp-Golomb codes, CAVLC residual blocks, and length-prefixed escaped NAL units.
//! Not supported: CABAC.
//! Role: This file is the bit-level writer the encoder paths share.
//
#global namespace H264
#global internal

using Core

struct EncoderBits
{
    bytes:   Array'u8
    current: u8
    used:    u32
}

impl EncoderBits
{
    mtd bit(value: u32)
    {
        .current = cast(u8, (cast(u32, .current) << 1) | (value & 1))
        .used += 1
        if .used == 8
        {
            .bytes.add(.current)
            .current = 0
            .used    = 0
        }
    }

    mtd bits(value: u32, count: u32)
    {
        var remaining = count
        while remaining
        {
            let take = Math.min(remaining, 8 - .used)
            let part = (value >> (remaining - take)) & ((1'u32 << take) - 1)
            .current = cast(u8, (cast(u32, .current) << take) | part)
            .used += take
            remaining -= take
            if .used == 8
            {
                .bytes.add(.current)
                .current = 0
                .used = 0
            }
        }
    }

    mtd unsigned(value: u32)
    {
        let code = value + 1
        var size = 0'u32
        var copy = code
        while copy
        {
            size += 1
            copy >>= 1
        }
        .bits(0, size - 1)
        .bits(code, size)
    }

    mtd signed(value: s32)
    {
        .unsigned(cast(u32, value > 0 ? value * 2 - 1 : -value * 2))
    }

    mtd alignZero()
    {
        while .used do
            .bit(0)
    }

    mtd trailing()
    {
        .bit(1)
        .alignZero()
    }

    mtd byte(value: u8)
    {
        Swag.assert(not .used)
        .bytes.add(value)
    }

    mtd alignedBytes(values: const [..] u8)
    {
        Swag.assert(not .used)
        .bytes.add(values)
    }

    // CAVLC for a 4x4 block with zero or one DC coefficient. The one-coefficient
    // case has no leading zeros in scan order and therefore no run_before syntax.
    mtd singleDc(level: s32, nC: u32)
    {
        let table = nC < 2 ? 0'u64 : (nC < 4 ? 1'u64 : (nC < 8 ? 2'u64 : 3'u64))
        let trailing = level == 1 or level == -1
        let token = level == 0 ? 0'u64 : (trailing ? 5'u64 : 4'u64)
        let offset = table * 68 + token
        .bits(CoeffTokenBits[offset], CoeffTokenLen[offset])
        if not level do
            return
        if trailing do
            .bit(level < 0 ? 1 : 0)
        else
        {
            let code = level > 0 ? level * 2 - 2 : -level * 2 - 1
            let value = cast(u32, code - 2)
            let prefix = value < 14 ? value : (value < 30 ? 14'u32 : 15'u32)
            .bits(0, prefix)
            .bit(1)
            if prefix == 14 do
                .bits(value - 14, 4)
            elif prefix == 15 do
                .bits(value - 30, 12)
        }
        .bit(1) // total_zeros = 0 for totalCoeff = 1.
    }

    // CAVLC for a quantized 4x4 block in zigzag order. Returns false only when
    // a level exceeds the bounded level-prefix form this encoder emits.
    mtd residual4(levels: const [*] s16, nC: u32)->bool
        => .residual(levels, nC, 16, false)

    mtd residual15(levels: const [*] s16, nC: u32)->bool
        => .residual(levels, nC, 15, false)

    // Chroma DC uses four coefficients and its own token/zero tables.
    mtd chromaDc(levels: const [*] s16)->bool
        => .residual(levels, 0, 4, true)

    mtd residual(levels: const [*] s16, nC, maxCoeffs: u32, chromaDc: bool)->bool
    {
        var positions: [16] u32
        var total = 0'u32
        for scan in maxCoeffs where levels[scan] != 0
        {
            positions[total] = scan
            total += 1
        }
        var trailing = 0'u32
        while trailing < total and trailing < 3 and
              Math.abs(cast(s32, levels[positions[total - trailing - 1]])) == 1 do
            trailing += 1

        let table = nC < 2 ? 0'u64 : (nC < 4 ? 1'u64 : (nC < 8 ? 2'u64 : 3'u64))
        let token = cast(u64, total * 4 + trailing)
        let tokenOffset = table * 68 + token
        let tokenLength = chromaDc ? ChromaDcCoeffTokenLen[token] : CoeffTokenLen[tokenOffset]
        if not tokenLength do
            return false
        .bits(chromaDc ? ChromaDcCoeffTokenBits[token] : CoeffTokenBits[tokenOffset], tokenLength)
        if not total do
            return true

        for index in trailing
        {
            let level = levels[positions[total - index - 1]]
            .bit(level < 0 ? 1 : 0)
        }
        var suffixLength = total > 10 and trailing < 3 ? 1'u32 : 0'u32
        for index in trailing until total
        {
            let level = cast(s32, levels[positions[total - index - 1]])
            var code = level > 0 ? level * 2 - 2 : -level * 2 - 1
            if index == trailing and trailing < 3 do
                code -= 2
            if code < 0 do
                return false
            let value = cast(u32, code)
            var prefix = 15'u32
            var suffixSize = 12'u32
            var suffixBase = (15'u32 << suffixLength) + (suffixLength == 0 ? 15'u32 : 0'u32)
            if value < (14'u32 << suffixLength)
            {
                prefix = value >> suffixLength
                suffixSize = suffixLength
                suffixBase = prefix << suffixLength
            }
            elif suffixLength == 0 and value < 30
            {
                prefix = 14
                suffixSize = 4
                suffixBase = 14
            }
            elif suffixLength != 0 and value < (15'u32 << suffixLength)
            {
                prefix = 14
                suffixSize = suffixLength
                suffixBase = 14'u32 << suffixLength
            }
            if value < suffixBase or value - suffixBase >= (1'u32 << suffixSize) do
                return false
            .bits(0, prefix)
            .bit(1)
            .bits(value - suffixBase, suffixSize)
            if suffixLength == 0 do
                suffixLength = 1
            if Math.abs(level) > (3's32 << (suffixLength - 1)) and suffixLength < 6 do
                suffixLength += 1
        }

        let totalZeros = positions[total - 1] + 1 - total
        if total < maxCoeffs
        {
            let stride = chromaDc ? 4'u32 : 16'u32
            let offset = cast(u64, (total - 1) * stride + totalZeros)
            if chromaDc do
                .bits(ChromaDcTotalZerosBits[offset], ChromaDcTotalZerosLen[offset])
            else do
                .bits(TotalZerosBits[offset], TotalZerosLen[offset])
        }
        var zerosLeft = totalZeros
        for index in total - 1
        {
            if not zerosLeft do
                break
            let run = positions[total - index - 1] - positions[total - index - 2] - 1
            let offset = cast(u64, Math.min(zerosLeft - 1, 6) * 16 + run)
            .bits(RunBeforeBits[offset], RunBeforeLen[offset])
            zerosLeft -= run
        }
        return true
    }
}

// Writes an escaped NAL with MP4's four-byte length prefix.
func appendEncoderNal(packet: *Array'u8, header: u8, payload: const [..] u8)
{
    let start = packet.count
    for 4 do
        packet.add(0'u8)
    packet.add(header)
    var zeros = 0'u32
    for value in payload
    {
        if zeros == 2 and value <= 3
        {
            packet.add(3'u8)
            zeros = 0
        }
        packet.add(value)
        zeros = value == 0 ? zeros + 1 : 0
        if zeros > 2 do
            zeros = 2
    }
    let length = cast(u32, packet.count - start - 4)
    packet[start]     = cast #wrap(u8, length >> 24)
    packet[start + 1] = cast #wrap(u8, length >> 16)
    packet[start + 2] = cast #wrap(u8, length >> 8)
    packet[start + 3] = cast #wrap(u8, length)
}
