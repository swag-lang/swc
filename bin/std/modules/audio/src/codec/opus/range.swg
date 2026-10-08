//! Format: Opus range decoder.
//! Supported: The entropy decoder of RFC 6716 clause 4.1: symbols coded against frequency counts or inverse cumulative tables, binary decisions, uniform integers, raw bits read from the end of the frame, and the bit-usage queries both layers make their allocation decisions from.
//! Not supported: Encoding.
//! Role: This file owns the arithmetic every Opus symbol is pulled through.
//
#global namespace Opus

using Core

private const SymBits    = 8'u32
private const SymMax     = 255'u32
private const CodeTop    = 1'u32 << 31
private const CodeBottom = CodeTop >> SymBits
private const CodeExtra  = 7'u32
private const WindowBits = 32'u32
private const UintBits   = 8'u32

// Bit counts the allocation logic works in are scaled by this many fractional bits.
internal const BitRes = 3'u32

// Returns the number of bits needed to hold `value`.
internal func ilog(value: u32)->u32 => value ? 32 - cast(u32, Swag.bitCountLz(value)) : 0

// Pulls symbols out of one frame, both from its front through the range coder and from its
// back as raw bits.
internal struct RangeDecoder
{
    data:      const [*] u8?
    storage:   u32
    offset:    u32     // Next byte read from the front.
    endOffset: u32     // Bytes consumed from the back.
    endWindow: u32
    endBits:   s32
    bitsTotal: s32     // Bits consumed so far, in the coder's own accounting.
    range:     u32
    value:     u32
    extent:    u32
    remainder: u32
    error:     bool
}

internal impl RangeDecoder
{
    func create(frame: const [..] u8)->RangeDecoder
    {
        with var result: retval
        {
            .data      = frame.buffer
            .storage   = cast(u32, frame.count)
            .bitsTotal = 9
            .range     = 1'u32 << CodeExtra
            .remainder = .readByte()
            .value     = .range - 1 - (.remainder >> (SymBits - CodeExtra))
            .normalize()
        }

        return result
    }

    mtd readByte()->u32
    {
        if .offset >= .storage do
            return 0
        let byte = cast(u32, .data![.offset])
        .offset += 1
        return byte
    }

    mtd readByteFromEnd()->u32
    {
        if .endOffset >= .storage do
            return 0
        .endOffset += 1
        return cast(u32, .data![.storage - .endOffset])
    }

    mtd normalize()
    {
        while .range <= CodeBottom
        {
            .bitsTotal += cast(s32, SymBits)
            .range     <<= SymBits
            let symbol = .remainder
            .remainder = .readByte()
            let mixed = ((symbol << SymBits) | .remainder) >> (SymBits - CodeExtra)
            .value = ((.value << SymBits) + (SymMax & ~mixed)) & (CodeTop - 1)
        }
    }

    // Returns the cumulative frequency of the next symbol out of `total`; [[update]] consumes it.
    mtd decode(total: u32)->u32
    {
        .extent = .range / total
        let scaledValue = .value / .extent
        return total - Math.min(scaledValue + 1, total)
    }

    mtd decodeBinary(bits: u32)->u32
    {
        .extent = .range >> bits
        let scaledValue = .value / .extent
        return (1'u32 << bits) - Math.min(scaledValue + 1, 1'u32 << bits)
    }

    mtd update(low, high, total: u32)
    {
        let rangeOffset = .extent * (total - high)
        .value -= rangeOffset
        .range = low > 0 ? .extent * (high - low) : .range - rangeOffset
        .normalize()
    }

    // Decodes one bit whose probability of being set is `1 / 2^logp`.
    mtd decodeBit(logp: u32)->bool
    {
        let currentRange = .range
        let currentValue = .value
        let splitRange   = currentRange >> logp
        let isSet        = currentValue < splitRange
        if not isSet do
            .value = currentValue - splitRange
        .range = isSet ? splitRange : currentRange - splitRange
        .normalize()
        return isSet
    }

    // Decodes one symbol against an inverse cumulative distribution scaled to `1 << bits`.
    mtd decodeIcdf(icdf: const [..] u8, bits: u32)->u32
    {
        var lowerBound     = .range
        let currentValue   = .value
        let frequencyScale = lowerBound >> bits
        var index          = 0'u32
        var upperBound     = lowerBound
        while true
        {
            upperBound = lowerBound
            lowerBound = frequencyScale * cast(u32, icdf[index])
            if currentValue >= lowerBound do
                break
            index += 1
        }

        .value = currentValue - lowerBound
        .range = upperBound - lowerBound
        .normalize()
        return index
    }

    // Decodes a uniformly distributed integer below `total`, which is at least two.
    mtd decodeUint(total: u32)->u32
    {
        var limit = total - 1
        let bits  = ilog(limit)
        if bits > UintBits
        {
            let shift  = bits - UintBits
            let high   = (limit >> shift) + 1
            let symbol = .decode(high)
            .update(symbol, symbol + 1, high)
            let value = (symbol << shift) | .decodeBits(shift)
            if value <= limit do
                return value
            .error = true
            return limit
        }

        limit += 1
        let symbol = .decode(limit)
        .update(symbol, symbol + 1, limit)
        return symbol
    }

    // Reads `bits` raw bits from the end of the frame, least significant first.
    mtd decodeBits(bits: u32)->u32
    {
        var window        = .endWindow
        var availableBits = .endBits
        if availableBits < cast(s32, bits)
        {
            while true
            {
                window        |= .readByteFromEnd() << cast(u32, availableBits)
                availableBits += cast(s32, SymBits)
                if availableBits > cast(s32, (WindowBits - SymBits)) do
                    break
            }
        }

        let result = window & ((1'u32 << bits) - 1)
        window        >>= bits
        availableBits -= cast(s32, bits)
        .endWindow    = window
        .endBits      = availableBits
        .bitsTotal    += cast(s32, bits)
        return result
    }

    // Returns the number of bits consumed so far, rounded up.
    mtd const tell()->s32 => .bitsTotal - cast(s32, ilog(.range))

    // Returns the number of bits consumed so far in eighths of a bit, rounded up.
    mtd const tellFrac()->u32
    {
        let totalFractionalBits = cast(u32, .bitsTotal) << BitRes
        var logRange            = ilog(.range)
        var normalizedRange     = .range >> (logRange - 16)
        for BitRes
        {
            normalizedRange = (normalizedRange * normalizedRange) >> 15
            let nextBit = normalizedRange >> 16
            logRange        = (logRange << 1) | nextBit
            normalizedRange >>= nextBit
        }

        return totalFractionalBits - logRange
    }
}
