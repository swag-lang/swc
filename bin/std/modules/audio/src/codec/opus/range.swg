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

// Uniform CELT symbols have totals up to 256. For non-power-of-two totals,
// this precision keeps the reciprocal error below 1 / total at CodeTop.
// That is smaller than the gap from any nonintegral quotient to the next integer.
private const UniformDivision: [257] u64 = #run
{
    var result: [257] u64
    for total in 1'u32 until result.count
    {
        let shift = (total & (total - 1)) ? 63 - cast(u32, Swag.leadingZeros(total)) : 31
        let scale = 1'u64 << shift
        let magic = (scale + total - 1) / total
        result[total] = magic | (cast(u64, shift) << 32)
    }

    return result
}

#[Swag.Inline]
private func divideUniformRange(range, total: u32)->u32
{
    let plan  = UniformDivision[total]
    let magic = cast #wrap(u32, plan)
    let shift = cast(u32, plan >> 32)
    return cast(u32, (cast(u64, range) * magic) >> shift)
}

// Each interval of 4096 normalized range values has one possible eighth-bit correction.
private const TellBoundaries: [8] u32 = #run
{
    var boundaries: [8] u32
    for initial in 32768 until 65536
    {
        var normalized = cast(u32, initial)
        var fraction   = 0'u32
        for 3
        {
            normalized = (normalized * normalized) >> 15
            let next = normalized >> 16
            fraction   = (fraction << 1) | next
            normalized >>= next
        }

        let region = (initial >> 12) - 8
        if fraction == region do
            boundaries[region] = cast(u32, initial)
    }

    return boundaries
}

// Bit counts the allocation logic works in are scaled by this many fractional bits.
internal const BitRes = 3'u32

// Returns the number of bits needed to hold `value`.
internal func ilog(value: u32)->u32 => value ? 32 - cast(u32, Swag.leadingZeros(value)) : 0

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
        with var result: #returntype
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

    #[Swag.Inline]
    mtd readByte()->u32
    {
        if .offset >= .storage do
            return 0
        let byte = cast(u32, .data![.offset])
        .offset += 1
        return byte
    }

    #[Swag.Inline]
    mtd readByteFromEnd()->u32
    {
        if .endOffset >= .storage do
            return 0
        .endOffset += 1
        return cast(u32, .data![.storage - .endOffset])
    }

    #[Swag.Inline]
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
    #[Swag.Inline]
    mtd decode(total: u32)->u32
    {
        .extent = total < UniformDivision.count ? divideUniformRange(.range, total) : .range / total
        let scaledValue = .value / .extent
        return total - Math.min(scaledValue + 1, total)
    }

    #[Swag.Inline]
    mtd decodeBinary(bits: u32)->u32
    {
        .extent = .range >> bits
        let scaledValue = .value / .extent
        return (1'u32 << bits) - Math.min(scaledValue + 1, 1'u32 << bits)
    }

    #[Swag.Inline]
    mtd update(low, high, total: u32)
    {
        let rangeOffset = .extent * (total - high)
        .value -= rangeOffset
        .range = low > 0 ? .extent * (high - low) : .range - rangeOffset
        .normalize()
    }

    // Decodes one bit whose probability of being set is `1 / 2^logp`.
    #[Swag.Inline]
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

    // Range decoding with uniform frequencies consumes one interval of the same width.
    #[Swag.Inline]
    mtd decodeUniform(total: u32)->u32
    {
        let extent = divideUniformRange(.range, total)
        let last   = total - 1
        let top    = Math.min(.value / extent, last)
        let offset = top * extent
        .value -= offset
        .range = top == last ? .range - offset : extent
        .normalize()
        return last - top
    }

    // Decodes a uniformly distributed integer below `total`, which is at least two.
    #[Swag.Inline]
    mtd decodeUint(total: u32)->u32
    {
        let limit = total - 1
        let bits  = ilog(limit)
        if bits > UintBits
        {
            let shift  = bits - UintBits
            let high   = (limit >> shift) + 1
            let symbol = .decodeUniform(high)
            let value  = (symbol << shift) | .decodeBits(shift)
            if value <= limit do
                return value
            .error = true
            return limit
        }

        return .decodeUniform(total)
    }

    // Reads `bits` raw bits from the end of the frame, least significant first.
    #[Swag.Inline]
    mtd decodeBits(bits: u32)->u32
    {
        var window        = .endWindow
        var availableBits = .endBits
        if availableBits < cast(s32, bits)
        {
            if .storage - .endOffset >= 4 and availableBits <= cast(s32, (WindowBits - SymBits))
            {
                // The window consumes the last byte first. Reverse one load and
                // retain only the whole bytes that fit beside the pending bits.
                let pending = cast(u32, availableBits)
                let bytes   = (WindowBits - pending) / SymBits
                let unused  = WindowBits - bytes * SymBits
                let tail    = (unwrap .data) + .storage - .endOffset
                let reverse = Swag.byteSwap(cast(const [*] u32, tail - 4)[0])
                window        |= ((reverse << unused) >> unused) << pending
                .endOffset    += bytes
                availableBits += cast(s32, bytes * SymBits)
            }
            else
            {
                while true
                {
                    window        |= .readByteFromEnd() << cast(u32, availableBits)
                    availableBits += cast(s32, SymBits)
                    if availableBits > cast(s32, (WindowBits - SymBits)) do
                        break
                }
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
        let logRange   = ilog(.range)
        let normalized = .range >> (logRange - 16)
        let region     = (normalized >> 12) - 8
        let fraction   = region + cast(u32, normalized > TellBoundaries[region])
        return totalFractionalBits - ((logRange << BitRes) + fraction)
    }
}
