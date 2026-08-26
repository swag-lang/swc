//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns the CABAC arithmetic engine, its contexts, and their saved states.
//
#global namespace Hevc
#global internal

using Core

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
// Slice bits stream through a 64-bit buffer refilled a word at a time, and renormalization shifts
// in one step, so the cost of a bin stays flat whatever the bin rate.
struct CabacReader
{
    data:      #null const [*] u8     // Substream bytes, with emulation prevention already removed.
    size:      u64
    position:  u64                   // Next byte to load into the bit buffer.
    padBytes:  u64                   // Synthetic zero bytes loaded past the end of the data.
    bitBuffer: u64                   // Raw bits, most significant first.
    bitCount:  s32                   // Valid bits at the top of `bitBuffer`.
    low:       u32                   // ivlOffset.
    range:     u32                   // ivlCurrRange.
    contexts:  [ContextCount] u8     // Packed state: `(pStateIdx << 1) | valMps`.

    // Clause 9.3.2.3: the Rice parameter each of the four coefficient statistics starts from.
    // Persistent Rice adaptation belongs to the range extensions; Main 10 leaves these at zero.
    riceInit: [4] u8
}

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

            for index in cast(u32) group.count
            {
                let initValue = cast(s32) ContextInitValues[cast(u32) initBase + index]
                let m         = (initValue >> 4) * 5 - 45
                let n         = ((initValue & 15) << 3) - 16
                let preState  = Math.clamp(((m * qp) >> 4) + n, 1, 126)
                if preState <= 63 do
                    .contexts[cast(u32) group.offset + index] = cast(u8) ((63 - preState) << 1)
                else do
                    .contexts[cast(u32) group.offset + index] = cast(u8) (((preState - 64) << 1) | 1)
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
    mtd start(data: const [*] u8, size: u64)
    {
        .data      = data
        .size      = size
        .position  = 0
        .padBytes  = 0
        .bitBuffer = 0
        .bitCount  = 0
        .range     = 510
        .low       = .takeBits(9)
    }

    // Reports whether decoding consumed bits past the end of the substream.
    #[Swag.Inline]
    mtd const hasOverrun()->bool => (.position + .padBytes) * 8 - cast(u64) .bitCount > .size * 8

    // Refills the top of the bit buffer, padding with zero bytes past the end of the data.
    private mtd refill()
    {
        // An empty buffer with a whole word of data left loads it in one swapped read.
        if .bitCount <= 0 and .position + 8 <= .size
        {
            .bitBuffer = @byteswap((cast(const [*] u64) (.data! + .position))[0])
            .bitCount  = 64
            .position  += 8
            return
        }

        while .bitCount <= 56
        {
            var value = 0'u8
            if .position < .size
            {
                value     = .data![.position]
                .position += 1
            }
            else
            {
                .padBytes += 1
            }

            .bitBuffer |= cast(u64) value << cast(u32) (56 - .bitCount)
            .bitCount  += 8
        }
    }

    // Takes `count` raw bits, most significant first; `count` is 1 to 9.
    #[Swag.Inline]
    private mtd takeBits(count: u32)->u32
    {
        if .bitCount < cast(s32) count do
            .refill()
        let bits = cast(u32) (.bitBuffer >> cast(u32) (64 - count))
        .bitBuffer <<= count
        .bitCount  -= cast(s32) count
        return bits
    }

    // Decodes one bin against the context at `contextIndex`, clause 9.3.4.3.2.
    //
    // The two arithmetic registers are held in locals for the whole bin. They are read and written
    // several times each, and the context update in between writes into this same structure, so
    // left in place they would be reloaded after every step.
    #[Swag.Inline]
    mtd decision(contextIndex: u32)->u32
    {
        var range  = .range
        var low    = .low
        let state  = cast(u32) .contexts[contextIndex]
        let pState = cast(u64) (state >> 1)
        let mps    = state & 1
        let lps    = cast(u32) CabacRangeLps[pState * 4 + cast(u64) ((range >> 6) & 3)]

        range -= lps
        var result: u32
        if low < range
        {
            .contexts[contextIndex] = cast(u8) ((cast(u32) CabacTransMps[pState] << 1) | mps)
            result = mps
        }
        else
        {
            low   -= range
            range = lps

            // State zero is the only one where the least probable symbol swaps the meaning of
            // the most probable one; the shift turns that test into a mask.
            let lpsMps = mps ^ cast(u32) ((pState - #wrap 1) >> 63)
            .contexts[contextIndex] = cast(u8) ((cast(u32) CabacTransLps[pState] << 1) | lpsMps)
            result = mps ^ 1
        }

        let shift = Math.max(cast(s32) @bitcountlz(range) - 23, 0)
        if shift != 0
        {
            range <<= cast(u32) shift
            low   = (low << cast(u32) shift) | .takeBits(cast(u32) shift)
        }

        .range = range
        .low   = low
        return result
    }

    // Decodes one bypass bin, clause 9.3.4.3.4.
    #[Swag.Inline]
    mtd bypass()->u32
    {
        .low = (.low << 1) | .takeBits(1)
        if .low >= .range
        {
            .low -= .range
            return 1
        }

        return 0
    }

    // Decodes `count` bypass bins as an unsigned value, most significant bin first.
    #[Swag.Inline]
    mtd bypassBits(count: u32)->u32
    {
        var result = 0'u32
        for count do
            result = (result << 1) | .bypass()
        return result
    }

    // Decodes the termination bin, clause 9.3.4.3.5.
    //
    // A returned one ends the slice segment or the substream; the caller is what knows which.
    #[Swag.Inline]
    mtd terminate()->u32
    {
        .range -= 2
        if .low >= .range do
            return 1

        let shift = Math.max(cast(s32) @bitcountlz(.range) - 23, 0)
        if shift != 0
        {
            .range <<= cast(u32) shift
            .low   = (.low << cast(u32) shift) | .takeBits(cast(u32) shift)
        }

        return 0
    }
}
