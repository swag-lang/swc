//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns the CABAC arithmetic engine, its contexts, and their saved states.
//
#global namespace Hevc
#global internal

using Core, Core.Errors

// The saved context state of one slice segment, clause 9.3.2.4.
//
// Wavefront parallel processing and dependent slice segments both resume a later substream from
// the adaptation an earlier one reached, rather than from the slice-level initialization. A
// decoder that ignored this would desynchronize on the first substream of any stream that uses
// either, so the storage exists even when only one substream is decoded.
struct CabacState
{
    contexts: [ContextCount] u8
    riceInit: [4] u8
    valid:    bool
}

// The arithmetic decoding engine of clause 9.3.4.
//
// H.265 specifies the same engine as H.264: the same 9-bit offset, the same range table, the same
// state transitions and the same renormalization. What differs is which contexts exist and how
// they are initialized, so this reads the shared tables and keeps its own context array.
//
// The offset carries its look-ahead bits and a marker. Renormalization advances both the
// offset and its input in one shift. Refilling is needed only when the marker reaches bit 32.
struct CabacReader
{
    data:     const [*] u8?     // Substream bytes, with emulation prevention already removed.
    size:     u64
    position: u64     // Next byte to load, including synthetic zero bytes beyond size.
    low:      u64     // ivlOffset << 33, then look-ahead bits and the marker.
    range:    u32     // ivlCurrRange.
    contexts: [ContextCount] u8     // Packed state: `(pStateIdx << 1) | valMps`.

    // Clause 9.3.2.3: the Rice parameter each of the four coefficient statistics starts from.
    // Persistent Rice adaptation belongs to the range extensions; Main 10 leaves these at zero.
    riceInit: [4] u8
}

private const CabacDecisionTables = #run buildCabacDecisionTables()
private const LookAheadBits       = 32'u32
private const OffsetShift         = LookAheadBits + 1
private const RefillMask          = 0xFFFFFFFF'u64

impl CabacReader
{
    // Initializes every context variable for one slice, clause 9.3.2.2.
    //
    // A group whose syntax element cannot occur under this initialization type is left alone: an
    // I slice never reads a merge flag, so there is no value to give it.
    mtd initContexts(initType: u32, sliceQp: s32)
    {
        let qp = Math.clamp(sliceQp, 0, 51)
        for group in ContextGroups
        {
            let initBase = group.init[initType]
            if initBase == NoInit do
                continue

            for index in cast(u32, group.count)
            {
                let initValue = cast(s32, ContextInitValues[cast(u32, initBase) + index])
                let m         = (initValue >> 4) * 5 - 45
                let n         = ((initValue & 15) << 3) - 16
                let preState  = Math.clamp(((m * qp) >> 4) + n, 1, 126)
                if preState <= 63 do
                    .contexts[cast(u32, group.offset) + index] = cast(u8, ((63 - preState) << 1))
                else do
                    .contexts[cast(u32, group.offset) + index] = cast(u8, (((preState - 64) << 1) | 1))
            }
        }

        Memory.set(&.riceInit, 0, #sizeof(.riceInit))
    }

    // Copies the adapted contexts out, clause 9.3.2.4.
    mtd const save(state: *CabacState)
    {
        Memory.copy(&state.contexts, &.contexts, #sizeof(.contexts))
        Memory.copy(&state.riceInit, &.riceInit, #sizeof(.riceInit))
        state.valid = true
    }

    // Restores contexts saved by an earlier substream, clause 9.3.2.2.
    mtd restore(state: const *CabacState)
    {
        Memory.copy(&.contexts, &state.contexts, #sizeof(.contexts))
        Memory.copy(&.riceInit, &state.riceInit, #sizeof(.riceInit))
    }

    // Starts the arithmetic engine on byte-aligned substream data, clause 9.3.2.5.
    mtd start(data: const [*] u8, size: u64) fail
    {
        .data     = data
        .size     = size
        .position = 5
        .range    = 510
        let head = .lookAhead(0)
        if head >> (LookAheadBits - 9) >= .range do
            fail InvalidFormatError{"HEVC CABAC initial offset is outside the range 0 through 509"}

        let tail = size > 4 ? cast(u64, data[4]) : 0'u64
        .low = (cast(u64, head) << 10) | (tail << 2) | 2
    }

    // The marker starts at bit one with 31 unread bits. Its position and the loaded byte
    // count record consumption even after the substream supplies only synthetic zeros.
    #[Swag.Inline]
    mtd const hasOverrun()->bool => .position * 8 + cast(u64, Swag.trailingZeros(.low)) > .size * 8 + LookAheadBits

    // A WPP row or tile ends inside the RBSP. Its look-ahead zero-pads at that boundary.
    #[Swag.Inline]
    private mtd const lookAhead(offset: u64)->u32
    {
        if offset >= .size do
            return 0
        let remaining = .size - offset
        let data      = unwrap .data + offset
        if remaining >= 4 do
            return Swag.byteSwap(cast(const [*] u32, data)[0])
        return readTail(data, remaining)
    }

    // The last one to three bytes may be followed by another substream in the same buffer.
    #[Swag.NoInline]
    private func readTail(data: const [*] u8, count: u64)->u32
    {
        var result = 0'u32
        for index in count do
            result |= cast(u32, data[index]) << (24 - cast(u32, index) * 8)
        return result
    }

    // Move the marker down by 32 and insert the next four bytes above it.
    #[Swag.Inline]
    private mtd reload(low: u64)->u64
    {
        let extra = cast(u32, Swag.trailingZeros(low)) - LookAheadBits
        let bits  = cast(u64, .lookAhead(.position)) << 1
        .position += 4
        return low - #wrap (RefillMask << extra) + #wrap (bits << extra)
    }

    // Decodes one bin against the context at `contextIndex`, clause 9.3.4.3.2.
    //
    // The two arithmetic registers are held in locals for the whole bin. They are read and written
    // several times each, and the context update in between writes into this same structure, so
    // left in place they would be reloaded after every step.
    #[Swag.Inline]
    mtd decision(contextIndex: u32)->u32
    {
        let state = cast(s64, .contexts[contextIndex])
        let lps   = cast(u32, CabacDecisionTables[CabacLpsAt + cast(u64, (2 * (.range & 0xC0))) + cast(u64, state)])
        var range = .range - lps
        var low   = .low

        let scaledRange = cast(u64, range) << OffsetShift
        let isLps       = low >= scaledRange
        let offset      = low - #wrap scaledRange
        low   = isLps ? offset : low
        range = isLps ? lps : range
        let symbol = isLps ? ~state : state
        .contexts[contextIndex] = CabacDecisionTables[CabacStateAt + cast(u64, (128 + symbol))]

        let shift = Swag.leadingZeros(range) - 23
        range <<= shift
        low   <<= shift
        if (low & RefillMask) == 0 do
            low = .reload(low)

        .range = range
        .low   = low
        return cast(u32, (symbol & 1))
    }

    // Decodes one bypass bin, clause 9.3.4.3.4.
    #[Swag.Inline]
    mtd bypass()->u32
    {
        var low = .low << 1
        if (low & RefillMask) == 0 do
            low = .reload(low)

        let range  = cast(u64, .range) << OffsetShift
        let offset = low - #wrap range
        let one    = low >= range
        .low = one ? offset : low
        return one ? 1'u32 : 0'u32
    }

    // Decodes `count` bypass bins as an unsigned value, most significant bin first.
    #[Swag.Inline]
    mtd bypassBits(count: u32)->u32
    {
        let range  = cast(u64, .range) << OffsetShift
        var low    = .low
        var result = 0'u32
        for count
        {
            low <<= 1
            if (low & RefillMask) == 0 do
                low = .reload(low)
            let offset = low - #wrap range
            let one    = low >= range
            low    = one ? offset : low
            result = (result << 1) | (one ? 1'u32 : 0'u32)
        }

        .low = low
        return result
    }

    // Decodes the termination bin, clause 9.3.4.3.5.
    //
    // A returned one ends the slice segment or the substream; the caller is what knows which.
    #[Swag.Inline]
    mtd terminate()->u32
    {
        .range -= 2
        if .low >= (cast(u64, .range) << OffsetShift) do
            return 1

        if .range < 256
        {
            .range <<= 1
            .low   <<= 1
            if (.low & RefillMask) == 0 do
                .low = .reload(.low)
        }

        return 0
    }
}
