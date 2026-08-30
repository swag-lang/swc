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
internal func ilog(value: u32)->u32 => value ? 32 - cast(u32) Swag.bitCountLz(value) : 0

// Pulls symbols out of one frame, both from its front through the range coder and from its
// back as raw bits.
internal struct RangeDecoder
{
    data:      #null const [*] u8
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
        var result: retval
        result.data      = frame.buffer
        result.storage   = cast(u32) frame.count
        result.bitsTotal = 9
        result.range     = 1'u32 << CodeExtra
        result.remainder = result.readByte()
        result.value     = result.range - 1 - (result.remainder >> (SymBits - CodeExtra))
        result.normalize()
        return result
    }

    mtd readByte()->u32
    {
        if .offset >= .storage do
            return 0
        let byte = cast(u32) .data![.offset]
        .offset += 1
        return byte
    }

    mtd readByteFromEnd()->u32
    {
        if .endOffset >= .storage do
            return 0
        .endOffset += 1
        return cast(u32) .data![.storage - .endOffset]
    }

    mtd normalize()
    {
        while .range <= CodeBottom
        {
            .bitsTotal += cast(s32) SymBits
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
        let s = .value / .extent
        return total - Math.min(s + 1, total)
    }

    mtd decodeBinary(bits: u32)->u32
    {
        .extent = .range >> bits
        let s = .value / .extent
        return (1'u32 << bits) - Math.min(s + 1, 1'u32 << bits)
    }

    mtd update(low, high, total: u32)
    {
        let s = .extent * (total - high)
        .value -= s
        .range = low > 0 ? .extent * (high - low) : .range - s
        .normalize()
    }

    // Decodes one bit whose probability of being set is `1 / 2^logp`.
    mtd decodeBit(logp: u32)->bool
    {
        let r   = .range
        let d   = .value
        let s   = r >> logp
        let set = d < s
        if !set do
            .value = d - s
        .range = set ? s : r - s
        .normalize()
        return set
    }

    // Decodes one symbol against an inverse cumulative distribution scaled to `1 << bits`.
    mtd decodeIcdf(icdf: const [..] u8, bits: u32)->u32
    {
        var s     = .range
        let d     = .value
        let r     = s >> bits
        var index = 0'u32
        var t     = s
        while true
        {
            t = s
            s = r * cast(u32) icdf[index]
            if d >= s do
                break
            index += 1
        }

        .value = d - s
        .range = t - s
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
            let shift = bits - UintBits
            let high  = (limit >> shift) + 1
            let s     = .decode(high)
            .update(s, s + 1, high)
            let t = (s << shift) | .decodeBits(shift)
            if t <= limit do
                return t
            .error = true
            return limit
        }

        limit += 1
        let s = .decode(limit)
        .update(s, s + 1, limit)
        return s
    }

    // Reads `bits` raw bits from the end of the frame, least significant first.
    mtd decodeBits(bits: u32)->u32
    {
        var window    = .endWindow
        var available = .endBits
        if available < cast(s32) bits
        {
            while true
            {
                window    |= .readByteFromEnd() << cast(u32) available
                available += cast(s32) SymBits
                if available > cast(s32) (WindowBits - SymBits) do
                    break
            }
        }

        let result = window & ((1'u32 << bits) - 1)
        window     >>= bits
        available  -= cast(s32) bits
        .endWindow = window
        .endBits   = available
        .bitsTotal += cast(s32) bits
        return result
    }

    // Returns the number of bits consumed so far, rounded up.
    mtd const tell()->s32 => .bitsTotal - cast(s32) ilog(.range)

    // Returns the number of bits consumed so far in eighths of a bit, rounded up.
    mtd const tellFrac()->u32
    {
        let nbits = cast(u32) .bitsTotal << BitRes
        var l     = ilog(.range)
        var r     = .range >> (l - 16)
        for BitRes
        {
            r = (r * r) >> 15
            let b = r >> 16
            l = (l << 1) | b
            r >>= b
        }

        return nbits - l
    }
}
