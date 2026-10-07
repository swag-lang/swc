//! Format: H.264/AVC decoder component.
//! Supported: Progressive 8-bit 4:2:0 and 4:4:4 Baseline, Main, High, and High 4:4:4 Predictive streams with CAVLC/CABAC, I/P/B slices, weighted prediction, cropping, reordering, and deblocking.
//! Not supported: Interlacing, 4:2:2 chroma, bit depths above 8, slice groups, data partitioning, scalable/multiview extensions, and lossless transform bypass.
//! Role: This file owns CABAC arithmetic contexts and syntax decoding.
//
#global namespace H264
#global internal

using Core, Core.Errors

// The CABAC arithmetic decoding engine of section 9.3, in the register layout of FFmpeg's
// `cabac_functions.h`.
//
// `low` holds codIOffset scaled by 2^17, the next sixteen stream bits below it and a marker bit
// under those; `range` is codIRange. A bin subtracts the LPS range, selects its outcome with one
// mask, steps the context through one table that serves both outcomes, and renormalizes both
// registers by a table-driven shift, reloading two bytes when the marker crosses the sixteen-bit
// line. That is about twenty instructions with no branch but the reload, half of what the direct
// transcription of the standard took. The reload has no slow path: the payload carries
// [[RbspPadding]] zero bytes past its end, so a function decoding bins contains no call — which is
// what lets the allocator keep its values in registers.
//
// The bins themselves are decoded by the mixins of `Slice` below, on the caller's own locals.
struct CabacReader
{
    data:     const [*] u8?     // Slice data, free of emulation prevention, padded past `size`.
    size:     u64
    position: u64           // Next data byte to load.
    low:      u32           // codIOffset << 17, then sixteen look-ahead bits, then the marker.
    range:    u32           // codIRange.
    contexts: [1024] u8     // Packed state: `(pStateIdx << 1) | valMPS`.
    invalid:  bool          // A syntax element did not decode; the macroblock loop reports it.
}

// Every table a residual block reads while it is decoded, in one object.
//
// Separate objects are separate addresses, and an address that a relocation supplies is remade
// where it stands rather than given a register of its own, so the innermost loop of the decoder
// rebuilt one address for every table it touched, on every bin. Behind a single base they are
// one address and a displacement, which the addressing of a memory operand already carries at no
// cost, and the two registers this frees are two the loop no longer spills.
const CabacLpsAt            = 0'u64       // Table 9-44, read as `2 * (range & 0xC0) + state`.
const CabacStateAt          = 512'u64     // The state after a bin, read as `128 + state`.
const CabacSigAt            = 768'u64     // Table 9-43 frame coding, significance context per 8x8 scan position.
const CabacLastAt           = 832'u64     // Table 9-43 frame coding, last-coefficient context per 8x8 scan position.
const CabacLevel1At         = 896'u64     // Context of a level's first bin, per level node.
const CabacLevelGtAt        = 904'u64     // Context of a level's later bins, per level node.
const CabacNodeAt           = 912'u64     // The level node after a level of one, then after a larger level.
const CabacTables: [928] u8 = #run buildCabacTables()

func buildCabacTables()->[928] u8
{
    var result: retval

    // Table 9-44 laid out for one lookup from the packed state and the two range bits that
    // select its column.
    for column in 4'u64
    {
        for state in 128'u64 do
            result[CabacLpsAt + column * 128 + state] = CabacRangeLps[(state >> 1) * 4 + column]
    }

    // One table for both outcomes: `128 + state` on the MPS path and `128 + (state ^ -1)` on the
    // LPS path, which flips valMPS at pStateIdx 0 as Table 9-45 says.
    for state in 128'u64
    {
        let mps  = cast(u32, (state & 1))
        let flip = (state >> 1) == 0 ? 1'u32 : 0'u32
        result[CabacStateAt + 128 + state] = cast(u8, ((cast(u32, CabacTransMps[state >> 1]) << 1) | mps))
        result[CabacStateAt + 127 - state] = cast(u8, ((cast(u32, CabacTransLps[state >> 1]) << 1) | (mps ^ flip)))
    }

    for scan in 63'u64
    {
        result[CabacSigAt + scan]  = SigCoeffCtx8x8[scan]
        result[CabacLastAt + scan] = LastCoeffCtx8x8[scan]
    }

    for node in 8'u64
    {
        result[CabacLevel1At + node]  = CoeffAbsLevel1Ctx[node]
        result[CabacLevelGtAt + node] = CoeffAbsLevelGt1Ctx[node]
    }

    for index in 16'u64 do
        result[CabacNodeAt + index] = CoeffAbsLevelTransition[index]

    return result
}

impl CabacReader
{
    // Initializes the contexts for one slice, section 9.3.1.1.
    mtd initContexts(sliceQp: s32, sliceType: u32, cabacInitIdc: u32)
    {
        for index in 1024'u64
        {
            var m, n: s32
            if sliceType == SliceTypeI
            {
                m = cast(s32, CabacInitI[index * 2])
                n = cast(s32, CabacInitI[index * 2 + 1])
            }
            else
            {
                let base = cast(u64, cabacInitIdc) * 2048 + index * 2
                m = cast(s32, CabacInitPB[base])
                n = cast(s32, CabacInitPB[base + 1])
            }

            let preState = Math.clamp(((m * Math.clamp(sliceQp, 0, 51)) >> 4) + n, 1, 126)
            if preState <= 63 do
                .contexts[index] = cast(u8, ((63 - preState) << 1))
            else do
                .contexts[index] = cast(u8, (((preState - 64) << 1) | 1))
        }
    }

    // Starts the arithmetic engine on the byte-aligned slice data, section 9.3.1.2: nine bits of
    // offset, fifteen bits of look-ahead, and the marker under them.
    //
    // `data` must be followed by [[RbspPadding]] readable zero bytes past `size`, which is how
    // `unescapeRbsp` leaves a payload.
    mtd start(data: const [*] u8, size: u64)
    {
        .data     = data
        .size     = size
        .position = 3
        .low      = (cast(u32, data[0]) << 18) | (cast(u32, data[1]) << 10) | (cast(u32, data[2]) << 2) | 2
        .range    = 0x1FE
    }

    // Reports whether decoding consumed bits past the end of the slice data.
    //
    // The bits loaded and not yet consumed sit between the marker and the offset, so the marker's
    // position says how many of the loaded bits are still ahead.
    mtd const hasOverrun()->bool => .position * 8 + cast(u64, Swag.bitCountTz(.low)) > .size * 8 + 16

    // Loads the two bytes due once the marker has crossed the sixteen-bit line, as FFmpeg's
    // `refill2`: the marker moves down sixteen bits and the new bits land above it. Past the end
    // of the data the bytes read as zeros, which is what reading past the end yields, and the
    // position keeps advancing so the overrun stays measurable.
    #[Swag.Inline]
    private mtd reload(low: u32)->u32
    {
        let extra = cast(u32, Swag.bitCountTz(low)) - 16
        var bits  = 0'u32
        if .position <= .size do
            bits = (cast(u32, .data![.position]) << 9) | (cast(u32, .data[.position + 1]) << 1)
        .position += 2
        return low - #wrap (0xFFFF'u32 << extra) + #wrap (bits << extra)
    }
}

// Context index bases per residual block category, frame coding: 0 luma DC, 1 luma AC of
// Intra_16x16, 2 luma 4x4, 3 chroma DC, 4 chroma AC, 5 luma 8x8, then the same four luma
// categories again for Cb (6, 7, 8, 9) and for Cr (10, 11, 12, 13), which is how a 4:4:4 colour
// plane is coded. Each base already carries the `ctxBlockCatOffset` of Table 9-42.
const CabacCbfBase:  [14] u32 = [85, 89, 93, 97, 101, 1012, 460, 464, 468, 1016, 472, 476, 480, 1020]
const CabacSigBase:  [14] u32 = [105, 120, 134, 149, 152, 402, 484, 499, 513, 660, 528, 543, 557, 718]
const CabacLastBase: [14] u32 = [166, 181, 195, 210, 213, 417, 572, 587, 601, 690, 616, 631, 645, 748]
const CabacAbsBase:  [14] u32 = [227, 237, 247, 257, 266, 426, 952, 962, 972, 708, 982, 992, 1002, 766]

// Residual categories of one colour plane, luma first: the Intra_16x16 DC, the Intra_16x16 AC,
// the 4x4 block, then the 8x8 block.
const CatPlaneDc:    [3] u32 = [0, 6, 10]
const CatPlaneI16Ac: [3] u32 = [1, 7, 11]
const CatPlane4x4:   [3] u32 = [2, 8, 12]
const CatPlane8x8:   [3] u32 = [5, 9, 13]

// Context of the first `coeff_abs_level_minus1` bin for each level node state.
const CoeffAbsLevel1Ctx:   [8] u8 = [1, 2, 3, 4, 0, 0, 0, 0]
const CoeffAbsLevelGt1Ctx: [8] u8 = [5, 5, 5, 5, 6, 7, 8, 9]

impl Slice
{
    // Decodes the skip flag of the macroblock at the current address, section 9.3.3.1.1.1.
    mtd decodeSkipFlagCabac()->bool
    {
        var ctx = 0'u32
        if .neighbors.a.available and not .neighbors.a.info!.skipped do
            ctx += 1
        if .neighbors.b.available and not .neighbors.b.info!.skipped do
            ctx += 1
        if .header.type == SliceTypeB do
            ctx += 13

        // Once per macroblock of an inter slice: decoded here rather than through a call.
        var range = .cabac.range
        var low   = .cabac.low
        var binState: s64
        .binDecision(11 + ctx)
        .cabac.range = range
        .cabac.low   = low
        return (binState & 1) != 0
    }

    // Parses one full macroblock with CABAC entropy coding.
    mtd parseMbCabac(mb: *Mb) fail
    {
        let dec = .dec!
        let pps = dec.pps!

        var isIntra = false
        var mbType  = 0'u32
        if .header.type == SliceTypeI
        {
            isIntra = true
            mbType  = .intraMbTypeCabac(mb, 3, intraSlice: true)
        }
        else
        {
            // The inter macroblock type is a few bins decoded against local arithmetic
            // registers, written back before an intra type takes over the reader.
            var range     = .cabac.range
            var low       = .cabac.low
            var binState: s64
            var intraBase = 0'u32
            if .header.type == SliceTypeP
            {
                .binDecision(14)
                if (binState & 1) != 0
                {
                    intraBase = 17
                }
                else
                {
                    .binDecision(15)
                    if (binState & 1) == 0
                    {
                        .binDecision(16)
                        mbType = 3 * cast(u32, (binState & 1))
                    }
                    else
                    {
                        .binDecision(17)
                        mbType = 2 - cast(u32, (binState & 1))
                    }
                }
            }
            else
            {
                var ctx = 0'u32
                if .neighbors.a.available and not .neighbors.a.info!.direct do
                    ctx += 1
                if .neighbors.b.available and not .neighbors.b.info!.direct do
                    ctx += 1

                let states = .cabac.contexts.buffer + 32
                .binDecision(27 + ctx)
                if (binState & 1) != 0
                {
                    .binDecision(30)
                    if (binState & 1) == 0
                    {
                        .binDecisionAt(states)
                        mbType = 1 + cast(u32, (binState & 1))
                    }
                    else
                    {
                        .binDecision(31)
                        var bits = cast(u32, (binState & 1)) << 3
                        .binDecisionAt(states)
                        bits += cast(u32, (binState & 1)) << 2
                        .binDecisionAt(states)
                        bits += cast(u32, (binState & 1)) << 1
                        .binDecisionAt(states)
                        bits += cast(u32, (binState & 1))
                        if bits < 8
                        {
                            mbType = bits + 3
                        }
                        elif bits == 13
                        {
                            intraBase = 32
                        }
                        elif bits == 14
                        {
                            mbType = 11
                        }
                        elif bits == 15
                        {
                            mbType = 22
                        }
                        else
                        {
                            .binDecisionAt(states)
                            mbType = (bits << 1) + cast(u32, (binState & 1)) - 4
                        }
                    }
                }
            }

            .cabac.range = range
            .cabac.low   = low
            if intraBase != 0
            {
                isIntra = true
                mbType  = .intraMbTypeCabac(mb, intraBase, intraSlice: false)
            }
        }

        if isIntra do
            try .parseIntraMb(mb, mbType, fromCabac: true)
        elif .header.type == SliceTypeP do
            try .parseInterMbP(mb, mbType)
        else do
            try .parseInterMbB(mb, mbType)

        if mb.class == MbClassIPcm do
            return

        if mb.class != MbClassIntra16x16
        {
            mb.cbpLuma   = .cbpLumaCabac(mb)
            mb.cbpChroma = dec.sps!.is444() ? 0 : .cbpChromaCabac(mb)

            if mb.cbpLuma != 0 and pps.transform8x8 and mb.class == MbClassInter and .allowsTransform8x8(mb) do
                mb.transform8x8 = .transformFlagCabac(mb) != 0
        }

        if mb.cbpLuma != 0 or mb.cbpChroma != 0 or mb.class == MbClassIntra16x16
        {
            let delta = .qpDeltaCabac()
            if delta < -26 or delta > 25 do
                fail InvalidFormatError{"H.264 macroblock QP delta is out of range"}
            .qp = (.qp + delta + 52) % 52
            .lastQpDelta = delta
        }
        else
        {
            .lastQpDelta = 0
        }

        mb.qp = .qp
        .parseResidualCabac(mb)
    }

    // Decodes one intra macroblock type, with its slice-dependent context base.
    mtd intraMbTypeCabac(mb: *Mb, ctxBase: u32, intraSlice: bool)->u32
    {
        var base = ctxBase
        if intraSlice
        {
            var ctx = 0'u32
            if .neighbors.a.available and .neighbors.a.info!.class == MbClassIntra16x16 do
                ctx += 1
            if .neighbors.b.available and .neighbors.b.info!.class == MbClassIntra16x16 do
                ctx += 1
            if .decision(base + ctx) == 0 do
                return 0
            base += 2
        }
        elif .decision(base) == 0
        {
            return 0
        }

        if .terminate() != 0 do
            return 25

        var mbType = 1'u32
        mbType += 12 * .decision(base + 1)
        if .decision(base + 2) != 0 do
            mbType += 4 + 4 * .decision(base + (intraSlice ? 3 : 2))
        mbType += 2 * .decision(base + (intraSlice ? 4 : 3))
        mbType += .decision(base + (intraSlice ? 5 : 3))
        return mbType
    }

    // Decodes one P sub-macroblock type.
    mtd subMbTypePCabac()->u32
    {
        var range  = .cabac.range
        var low    = .cabac.low
        var binState: s64
        var result = 0'u32
        .binDecision(21)
        if (binState & 1) == 0
        {
            result = 1
            .binDecision(22)
            if (binState & 1) != 0
            {
                .binDecision(23)
                result = (binState & 1) != 0 ? 2 : 3
            }
        }

        .cabac.range = range
        .cabac.low   = low
        return result
    }

    // Decodes one B sub-macroblock type.
    mtd subMbTypeBCabac()->u32
    {
        var range  = .cabac.range
        var low    = .cabac.low
        var binState: s64
        let last   = .cabac.contexts.buffer + 39
        var result = 0'u32
        .binDecision(36)
        if (binState & 1) != 0
        {
            .binDecision(37)
            if (binState & 1) == 0
            {
                .binDecisionAt(last)
                result = 1 + cast(u32, (binState & 1))
            }
            else
            {
                result = 3
                var small = true
                .binDecision(38)
                if (binState & 1) != 0
                {
                    .binDecisionAt(last)
                    if (binState & 1) != 0
                    {
                        .binDecisionAt(last)
                        result = 11 + cast(u32, (binState & 1))
                        small  = false
                    }
                    else
                    {
                        result += 4
                    }
                }

                if small
                {
                    .binDecisionAt(last)
                    result += 2 * cast(u32, (binState & 1))
                    .binDecisionAt(last)
                    result += cast(u32, (binState & 1))
                }
            }
        }

        .cabac.range = range
        .cabac.low   = low
        return result
    }

    // Decodes one intra 4x4 or 8x8 prediction mode against its neighbor prediction.
    //
    // This and the other syntax elements of several bins decode against local arithmetic
    // registers written back once, like a residual block, rather than one call per bin.
    mtd intraModeCabac(predicted: u32)->u32
    {
        var range = .cabac.range
        var low   = .cabac.low
        var binState: s64
        var mode  = predicted
        .binDecision(68)
        if (binState & 1) == 0
        {
            let states = .cabac.contexts.buffer + 69
            .binDecisionAt(states)
            mode = cast(u32, (binState & 1))
            .binDecisionAt(states)
            mode += 2 * cast(u32, (binState & 1))
            .binDecisionAt(states)
            mode += 4 * cast(u32, (binState & 1))
            if mode >= predicted do
                mode += 1
        }

        .cabac.range = range
        .cabac.low   = low
        return mode
    }

    // Decodes the intra chroma prediction mode.
    mtd chromaModeCabac(mb: *Mb)->u32
    {
        var ctx = 0'u32
        if .neighbors.a.available and .neighbors.a.info!.chromaMode != 0 do
            ctx += 1
        if .neighbors.b.available and .neighbors.b.info!.chromaMode != 0 do
            ctx += 1
        var range = .cabac.range
        var low   = .cabac.low
        var binState: s64
        var mode  = 0'u32
        .binDecision(64 + ctx)
        if (binState & 1) != 0
        {
            mode = 1
            let states = .cabac.contexts.buffer + 67
            .binDecisionAt(states)
            if (binState & 1) != 0
            {
                .binDecisionAt(states)
                mode = (binState & 1) != 0 ? 3 : 2
            }
        }

        .cabac.range = range
        .cabac.low   = low
        return mode
    }

    // Decodes the 8x8 transform flag with its neighbor context.
    mtd transformFlagCabac(mb: *Mb)->u32
    {
        var ctx = 0'u32
        if .neighbors.a.available and .neighbors.a.info!.transform8x8 do
            ctx += 1
        if .neighbors.b.available and .neighbors.b.info!.transform8x8 do
            ctx += 1
        return .decision(399 + ctx)
    }

    // Decodes the luma coded block pattern, four bins with spatial contexts.
    mtd cbpLumaCabac(mb: *Mb)->u32
    {
        // An unavailable neighbor reads as fully coded, so it never raises the context.
        var leftCbp = 0xF'u32
        var topCbp  = 0xF'u32
        if .neighbors.a.available do
            leftCbp = cast(u32, .neighbors.a.info!.cbpLuma)
        if .neighbors.b.available do
            topCbp = cast(u32, .neighbors.b.info!.cbpLuma)

        var range  = .cabac.range
        var low    = .cabac.low
        var binState: s64
        let states = .cabac.contexts.buffer + 73
        var cbp    = 0'u32
        var ctx    = (leftCbp & 0x02 ? 0'u64 : 1) + 2 * (topCbp & 0x04 ? 0'u64 : 1)
        .binDecisionAt(states + ctx)
        cbp += cast(u32, (binState & 1))
        ctx = (cbp & 0x01 ? 0'u64 : 1) + 2 * (topCbp & 0x08 ? 0'u64 : 1)
        .binDecisionAt(states + ctx)
        cbp += cast(u32, (binState & 1)) << 1
        ctx = (leftCbp & 0x08 ? 0'u64 : 1) + 2 * (cbp & 0x01 ? 0'u64 : 1)
        .binDecisionAt(states + ctx)
        cbp += cast(u32, (binState & 1)) << 2
        ctx = (cbp & 0x04 ? 0'u64 : 1) + 2 * (cbp & 0x02 ? 0'u64 : 1)
        .binDecisionAt(states + ctx)
        cbp          += cast(u32, (binState & 1)) << 3
        .cabac.range = range
        .cabac.low   = low
        return cbp
    }

    // Decodes the chroma coded block pattern, two bins.
    mtd cbpChromaCabac(mb: *Mb)->u32
    {
        var leftCbp = 0'u32
        var topCbp  = 0'u32
        if .neighbors.a.available do
            leftCbp = cast(u32, .neighbors.a.info!.cbpChroma)
        if .neighbors.b.available do
            topCbp = cast(u32, .neighbors.b.info!.cbpChroma)

        var range = .cabac.range
        var low   = .cabac.low
        var binState: s64
        var ctx   = 0'u32
        if leftCbp > 0 do
            ctx += 1
        if topCbp > 0 do
            ctx += 2
        var cbp = 0'u32
        .binDecision(77 + ctx)
        if (binState & 1) != 0
        {
            ctx = 4
            if leftCbp == 2 do
                ctx += 1
            if topCbp == 2 do
                ctx += 2
            .binDecision(77 + ctx)
            cbp = 1 + cast(u32, (binState & 1))
        }

        .cabac.range = range
        .cabac.low   = low
        return cbp
    }

    // Decodes the macroblock QP delta.
    mtd qpDeltaCabac()->s32
    {
        var range = .cabac.range
        var low   = .cabac.low
        var binState: s64
        var ctx   = .lastQpDelta != 0 ? 1'u32 : 0'u32
        var count = 0's32
        while true
        {
            .binDecision(60 + ctx)
            if (binState & 1) == 0 do
                break
            ctx   = ctx < 2 ? 2 : 3
            count += 1
            if count > 104 do
                break
        }

        .cabac.range = range
        .cabac.low   = low
        return count & 1 ? (count + 1) >> 1 : -(count >> 1)
    }

    // Decodes one reference index, section 9.3.3.1.1.6.
    mtd refIdxCabac(mb: *Mb, list: u32, x4, y4: s32)->u32
    {
        var ctx = 0'u32
        if .refCtxFlag(mb, list, x4 - 1, y4) do
            ctx += 1
        if .refCtxFlag(mb, list, x4, y4 - 1) do
            ctx += 2

        var range = .cabac.range
        var low   = .cabac.low
        var binState: s64
        var ref   = 0'u32
        while true
        {
            .binDecision(54 + ctx)
            if (binState & 1) == 0 do
                break
            ref += 1
            ctx = (ctx >> 2) + 4
            if ref >= 32 do
                break
        }

        .cabac.range = range
        .cabac.low   = low
        return ref
    }

    // Reports whether the block at `rx`, `ry` relative to the macroblock contributes to the
    // reference-index context: it must hold a positive reference that was not produced by a
    // direct mode.
    mtd const refCtxFlag(mb: *Mb, list: u32, rx, ry: s32)->bool
    {
        if rx >= 0 and ry >= 0
        {
            let quad = cast(u64, ((ry >> 1) * 2 + (rx >> 1)))
            if mb.subDirect[quad] or mb.directMb do
                return false
            return mb.ctxRef[cast(u64, list), quad] > 0
        }

        let neighbor = rx < 0 ? &.neighbors.a : &.neighbors.b
        if not neighbor.available do
            return false
        let info = neighbor.info!
        if info.class != MbClassInter do
            return false
        if .header.type == SliceTypeP and info.skipped do
            return false

        let dec   = .dec!
        let index = neighbor.blockBase + cast(u64, ((ry & 3) * (dec.sps!.mbWidth * 4) + (rx & 3)))
        if dec.directFlags[index] != 0 and .header.type == SliceTypeB do
            return false
        let ref = list == 0 ? dec.motionL0[index].refIdx : dec.motionL1[index].refIdx
        return ref > 0
    }

    // Decodes one motion vector difference pair, section 9.3.3.1.1.7.
    //
    // A pair is up to two dozen bins, decoded like a residual block's against local arithmetic
    // registers that are written back once, rather than one call per bin that reloads and
    // stores them.
    mtd mvdCabac(mb: *Mb, list: u32, x4, y4: s32)->[2] s16
    {
        let a = .neighborMvd(mb, list, x4 - 1, y4)
        let b = .neighborMvd(mb, list, x4, y4 - 1)

        var range = .cabac.range
        var low   = .cabac.low
        var bin:      u32
        var binState: s64
        var level:    s32
        var result:   retval
        for component in 2'u32
        {
            let sumA    = Math.abs(cast(s32, a[component]))
            let sumB    = Math.abs(cast(s32, b[component]))
            let amvd    = sumA + sumB
            var ctxBase = component == 0 ? 40'u32 : 47'u32
            var ctx     = 0'u32
            if amvd > 2 do
                ctx += 1
            if amvd > 32 do
                ctx += 1

            .binDecision(ctxBase + ctx)
            if (binState & 1) == 0
            {
                result[component] = 0
                continue
            }

            // The unary prefix walks its contexts through one state pointer.
            var value = 1'u32
            var unary = .cabac.contexts.buffer + cast(u64, (ctxBase + 3))
            while value < 9
            {
                .binDecisionAt(unary)
                if (binState & 1) == 0 do
                    break
                if value < 4 do
                    unary += 1
                value += 1
            }

            if value >= 9
            {
                // Exp-Golomb suffix of order three, in bypass bins.
                var k = 3'u32
                while true
                {
                    .binBypass()
                    if bin == 0 do
                        break
                    value += 1'u32 << k
                    k     += 1
                    if k > 24
                    {
                        .cabac.invalid = true
                        break
                    }
                }

                while k > 0
                {
                    k -= 1
                    .binBypass()
                    value += bin << k
                }
            }

            .binSign(cast(s32, value))
            result[component] = cast(s16, Math.clamp(level, -32768, 32767))
        }

        .cabac.range = range
        .cabac.low   = low
        return result
    }

    // Decodes one bin against the caller's arithmetic registers, section 9.3.3.2.1.
    //
    // A mixin rather than a call: `range` and `low` are locals of the function decoding a whole
    // residual block, so every bin of the block computes in two registers and the reader is
    // written back once at the end. Through a call, or through a structure whose address an
    // inlined function takes, both registers went through memory at every step of every bin, and
    // the significance loops spent a fifth of their time on those round trips. The two outcomes
    // are selected without a branch, since a bin's value is close to unpredictable by design.
    //
    // The decoded bin is the low bit of `binState`, the context's packed state after the bin, as
    // FFmpeg's `get_cabac` leaves it: a caller branching on the bin tests that bit, where a bin
    // extracted first cost a copy and a mask on every bin.
    #[Swag.Mixin]
    private mtd binDecision(binCtx: u32)
    {
        .binDecisionAt(.cabac.contexts.buffer + cast(u64, binCtx))
    }

    // Decodes one bin against the context state at `state`, as [[binDecision]] does.
    //
    // A loop walking consecutive contexts holds one pointer into them, as FFmpeg's significance
    // loop does, rather than the context array and a base index beside its position.
    //
    // The packed state is held at full register width, as FFmpeg's `get_cabac` holds it: its
    // complement then indexes the transition table directly, where a 32-bit complement had to be
    // sign-extended into an address on every bin.
    #[Swag.Mixin]
    private mtd binDecisionAt(state: [*] u8)
    {
        var #uniq0 = cast(s64, state[0])
        let #uniq1 = cast(u32, CabacTables[CabacLpsAt + cast(u64, (2 * (range & 0xC0))) + cast(u64, #uniq0)])
        range -= #uniq1

        // The offset standing above the most probable subrange is what takes the less probable
        // path, and each of the three values it changes is one conditional move. Written as the
        // mask of that comparison folded into an and and an add, as the standard states it, every
        // one of them costs a copy as well: the machine's arithmetic reads and writes the same
        // register, so a value still needed afterwards has to be moved out of the way first.
        //
        // The comparison is exact because both quantities stay well below the sign bit: the range
        // holds nine bits and the offset the sixteen look-ahead bits above it.
        let #uniq2 = range << 17
        let #uniq4 = low - #wrap #uniq2
        let #uniq5 = cast(s32, #uniq2) < cast(s32, low)
        low      = #uniq5 ? #uniq4 : low
        range    = #uniq5 ? #uniq1 : range
        #uniq0   = #uniq5 ? ~#uniq0 : #uniq0
        state[0] = CabacTables[CabacStateAt + cast(u64, (128 + #uniq0))]
        binState = #uniq0

        // The renormalization shift is the distance from the range's highest set bit to bit 8,
        // which the machine counts in one instruction. The table it replaces was 512 bytes the
        // hot loop kept resident and one more memory read on the only chain this decoder cannot
        // widen: a bin is decoded from the range the bin before it left. At a range of zero the
        // count gives 32, which is the shift of 9 the table held there.
        let #uniq3 = Swag.bitCountLz(range) - 23
        range <<= #uniq3
        low   <<= #uniq3
        if (low & 0xFFFF) == 0 do
            low = .cabac.reload(low)
    }

    // Decodes one bypass bin against the caller's arithmetic registers, section 9.3.3.2.3, into
    // `bin`.
    #[Swag.Mixin]
    private mtd binBypass()
    {
        low <<= 1
        if (low & 0xFFFF) == 0 do
            low = .cabac.reload(low)

        // The offset below the range is a zero bin and keeps the offset; above it the bin is one
        // and the range comes off. One comparison and one conditional move each.
        let #uniq0 = range << 17
        let #uniq1 = low - #wrap #uniq0
        let #uniq2 = cast(s32, #uniq0) <= cast(s32, low)
        low = #uniq2 ? #uniq1 : low
        bin = #uniq2 ? 1 : 0
    }

    // Decodes a bypass sign and applies it to `magnitude` without branching, into `level`.
    #[Swag.Mixin]
    private mtd binSign(magnitude: s32)
    {
        low <<= 1
        if (low & 0xFFFF) == 0 do
            low = .cabac.reload(low)

        // Same bin as the bypass, read as a sign: below the range it is positive. The negation
        // comes before the comparison, whose flags then serve both selects: after it, it would
        // overwrite them and the comparison would have to be kept as a boolean and tested again.
        let #uniq0 = range << 17
        let #uniq1 = low - #wrap #uniq0
        let #uniq3 = -magnitude
        let #uniq2 = cast(s32, #uniq0) <= cast(s32, low)
        low   = #uniq2 ? #uniq1 : low
        level = #uniq2 ? #uniq3 : magnitude
    }

    // Decodes one bin with the context at `contextIndex`, section 9.3.3.2.1, for the syntax
    // elements decoded one bin at a time.
    mtd decision(contextIndex: u32)->u32
    {
        var range = .cabac.range
        var low   = .cabac.low
        var binState: s64
        .binDecision(contextIndex)
        .cabac.range = range
        .cabac.low   = low
        return cast(u32, (binState & 1))
    }

    // Decodes one bypass bin, section 9.3.3.2.3.
    mtd bypass()->u32
    {
        var range = .cabac.range
        var low   = .cabac.low
        var bin: u32
        .binBypass()
        .cabac.low = low
        return bin
    }

    // Decodes the end-of-slice bin, section 9.3.3.2.4.
    mtd terminate()->u32
    {
        var range = .cabac.range - 2
        var low   = .cabac.low
        if low >= range << 17 do
            return 1

        // One renormalization step at most: a range below 256 shifts by one.
        let shift = (range - #wrap 256) >> 31
        range <<= shift
        low   <<= shift
        if (low & 0xFFFF) == 0 do
            low = .cabac.reload(low)
        .cabac.range = range
        .cabac.low   = low
        return 0
    }

    // Decodes one residual block of `MaxCoeffs` coefficients, sections 9.3.3.1.1.9 and 9.3.3.1.3.
    //
    // `cat` is the block category. A block first decodes a coded-block flag against the neighbor
    // flags `nzA` and `nzB` (-1 for an unavailable neighbor). Each level lands in `coeffs` at the
    // raster position the block shape's scan gives it, dequantized by the matching entry of
    // `scale`; a DC block has no `scale` and keeps its levels. Returns the coefficient count.
    //
    // The block size and the DC distinction are compile-time parameters: the four block shapes a
    // stream carries each get a body whose bounds, table choice and store are folded, and only
    // the values the loops read stay live across them. The shape also fixes the scan and the
    // dequantization shift, so neither is a value the level loop has to keep.
    func(const MaxCoeffs: u32, const IsDc: bool) residualCabac(me, mb: *Mb, cat: u32, coeffs: [*] s16, nzA, nzB: s32, scale: [*] u32?)->u32
    {
        const Order = IsDc ? ResidualOrderDc : MaxCoeffs == 64 ? ResidualOrder8x8 : MaxCoeffs == 15 ? ResidualOrderAc : ResidualOrder4x4
        const Shift = MaxCoeffs == 64 ? 6'u32 : 4'u32

        var range = .cabac.range
        var low   = .cabac.low
        var bin:      u32
        var binState: s64

        // A block of sixty-four coefficients states nothing of its own, the coded block pattern
        // having said whether it is coded — except in 4:4:4, where every block codes a flag,
        // which is what the three context bases at 1012 exist for.
        if MaxCoeffs != 64 or .dec!.sps!.is444()
        {
            var ctx   = CabacCbfBase[cat]
            let intra = mb.class != MbClassInter
            if nzA > 0 or (nzA < 0 and intra) do
                ctx += 1
            if nzB > 0 or (nzB < 0 and intra) do
                ctx += 2
            .binDecision(ctx)
            if (binState & 1) == 0
            {
                .cabac.range = range
                .cabac.low   = low
                return 0
            }
        }

        // Significance map: the scan positions of the coefficients, in scan order. The 8x8
        // categories map every scan position through a table while every other category uses
        // the position itself.
        var indices: [64] u8
        var count      = 0'u32
        let sigStates  = .cabac.contexts.buffer + cast(u64, CabacSigBase[cat])
        let lastStates = .cabac.contexts.buffer + cast(u64, CabacLastBase[cat])
        var scan       = 0'u64
        var foundLast  = false
        while scan < MaxCoeffs - 1
        {
            .binDecisionAt(sigStates + (MaxCoeffs == 64 ? cast(u64, CabacTables[CabacSigAt + scan]) : scan))
            if (binState & 1) != 0
            {
                indices[count] = cast(u8, scan)
                count += 1
                .binDecisionAt(lastStates + (MaxCoeffs == 64 ? cast(u64, CabacTables[CabacLastAt + scan]) : scan))
                if (binState & 1) != 0
                {
                    foundLast = true
                    break
                }
            }

            scan += 1
        }

        // The last position is significant when no earlier one closed the block.
        if not foundLast
        {
            indices[count] = cast(u8, (MaxCoeffs - 1))
            count += 1
        }

        // Levels, last significant coefficient first, their contexts reached through one pointer
        // like the significance ones.
        let absStates = .cabac.contexts.buffer + cast(u64, CabacAbsBase[cat])
        var node      = 0'u64
        var remaining = count
        var level: s32
        while remaining > 0
        {
            remaining -= 1
            let position  = cast(u64, indices[remaining])
            var magnitude = 1's32
            .binDecisionAt(absStates + cast(u64, CabacTables[CabacLevel1At + node]))
            if (binState & 1) == 0
            {
                node = cast(u64, CabacTables[CabacNodeAt + node])
            }
            else
            {
                magnitude = 2
                let gt1State = absStates + cast(u64, CabacTables[CabacLevelGtAt + node])
                node = cast(u64, CabacTables[CabacNodeAt + 8 + node])
                while magnitude < 15
                {
                    .binDecisionAt(gt1State)
                    if (binState & 1) == 0 do
                        break
                    magnitude += 1
                }

                if magnitude >= 15
                {
                    // Exp-Golomb order zero suffix in bypass bins.
                    var zeros = 0'u32
                    while true
                    {
                        .binBypass()
                        if bin == 0 or zeros >= 23 do
                            break
                        zeros += 1
                    }

                    var value = 1'u32
                    while zeros > 0
                    {
                        zeros -= 1
                        .binBypass()
                        value = (value << 1) + bin
                    }

                    magnitude = cast(s32, value) + 14
                }
            }

            .binSign(magnitude)
            let raster = cast(u64, ResidualOrder[Order + position])
            if IsDc do
                coeffs[raster] = cast(s16, Math.clamp(level, -32768, 32767))
            else do
                coeffs[raster] = dequantLevel(level, scale![raster], Shift)
        }

        .cabac.range = range
        .cabac.low   = low
        return count
    }

    // Parses every residual block of the macroblock with CABAC coding.
    mtd parseResidualCabac(mb: *Mb)
    {
        let dec = .dec!

        // A 4:4:4 macroblock codes its colour planes exactly as luma, one whole plane after
        // another and all three under the same coded block pattern.
        let planes = dec.sps!.is444() ? 3'u32 : 1'u32
        for plane in planes do
            .parsePlaneResidualCabac(mb, plane)
        if planes > 1 do
            return

        if mb.cbpChroma != 0
        {
            for plane in 2's32
            {
                let nzA   = .dcFlagNeighbor(mb, -1, 0, 1 + plane)
                let nzB   = .dcFlagNeighbor(mb, 0, -1, 1 + plane)
                let count = .residualCabac'(4, true)(mb, 3, (mb.residual!.chromaDc).buffer + cast(u64, plane) * 4, nzA, nzB, null)
                mb.dcFlags[cast(u64, (1 + plane))] = count > 0 ? 1 : 0
            }
        }

        if mb.cbpChroma == 2
        {
            for plane in 2's32
            {
                let scale  = .dequantRow4(mb, cast(u32, plane) + 1)
                let counts = plane == 0 ? (mb.nzCb).buffer : (mb.nzCr).buffer
                for block in 4's32
                {
                    // A neighbor inside the macroblock is its own count, decoded just before.
                    let nzA   = block & 1 ? cast(s32, counts[cast(u64, block) - 1]) : .chromaBlockNz(mb, cast(u32, plane), -1, block >> 1)
                    let nzB   = block >> 1 ? cast(s32, counts[cast(u64, block) - 2]) : .chromaBlockNz(mb, cast(u32, plane), block & 1, -1)
                    let count = .residualCabac'(15, false)(mb, 4, (mb.residual!.chromaAc).buffer + cast(u64, plane) * 64 + cast(u64, block) * 16, nzA, nzB, scale)
                    if plane == 0 do
                        mb.nzCb[cast(u64, block)] = cast(u8, count)
                    else do
                        mb.nzCr[cast(u64, block)] = cast(u8, count)
                }
            }
        }
    }

    // Parses the residual of one colour plane coded with the luma syntax and that plane's own
    // block categories.
    //
    // Only luma feeds the deblocking strength: the boundary filter reads the luma transform
    // coefficients whatever the chroma format, so a colour plane writes its nonzero counts for
    // the entropy contexts and nothing else.
    mtd parsePlaneResidualCabac(mb: *Mb, plane: u32)
    {
        let storage = .planeResidual(mb, plane)
        let isLuma  = plane == 0
        if mb.class == MbClassIntra16x16
        {
            let nzA   = .dcFlagNeighbor(mb, -1, 0, cast(s32, plane))
            let nzB   = .dcFlagNeighbor(mb, 0, -1, cast(s32, plane))
            let count = .residualCabac'(16, true)(mb, CatPlaneDc[cast(u64, plane)], storage.dc, nzA, nzB, null)
            mb.dcFlags[cast(u64, plane)] = count > 0 ? 1 : 0
            if count > 0 and isLuma
            {
                for block in 16'u64 do
                    mb.codedBlocks[block] = 1
            }
        }

        if mb.cbpLuma == 0 do
            return

        // One transform size and one quantizer serve the whole macroblock, so its row of
        // dequantization factors is looked up once rather than for every block.
        let use8x8       = mb.transform8x8 and mb.class != MbClassIntra16x16
        let codesFlag8x8 = use8x8 and .dec!.sps!.is444()
        let scale        = use8x8 ? .dequantRow8(mb, plane) : .dequantRow4(mb, plane)
        for quad in 4's32
        {
            if (mb.cbpLuma & (1'u32 << cast(u32, quad))) == 0 do
                continue
            if use8x8
            {
                // A 4:4:4 8x8 block codes a flag of its own, whose context reads the block left
                // of and above the quadrant's first cell.
                // Only a 4:4:4 picture codes that flag; the counts are not asked for otherwise.
                let first = (quad >> 1) * 8 + (quad & 1) * 2
                let nzA   = codesFlag8x8 ? .blockNz8x8(mb, plane, (first & 3) - 1, first >> 2) : 0
                let nzB   = codesFlag8x8 ? .blockNz8x8(mb, plane, first & 3, (first >> 2) - 1) : 0
                let count = .residualCabac'(64, false)(mb, CatPlane8x8[cast(u64, plane)], storage.t8 + cast(u64, quad) * 64, nzA, nzB, scale)

                // In 4:4:4 the block states a coded flag of its own, so a quadrant the pattern
                // named can still hold nothing.
                for cell in 4's32
                {
                    let raster = (quad >> 1) * 8 + (quad & 1) * 2 + (cell >> 1) * 4 + (cell & 1)
                    storage.nz[cast(u64, raster)] = cast(u8, Math.min(count, 16))
                    if isLuma do
                        mb.codedBlocks[cast(u64, raster)] = count > 0 ? 1 : 0
                }

                continue
            }

            for cell in 4's32
            {
                let raster = (quad >> 1) * 8 + (quad & 1) * 2 + (cell >> 1) * 4 + (cell & 1)
                let bx     = raster & 3
                let by     = raster >> 2

                // A neighbor inside this macroblock is its own count, already decoded in the
                // block order; only the edge blocks ask about the neighboring macroblocks.
                let nzA = bx > 0 ? cast(s32, storage.nz[cast(u64, raster) - 1]) : .blockNz(mb, plane, bx - 1, by)
                let nzB = by > 0 ? cast(s32, storage.nz[cast(u64, raster) - 4]) : .blockNz(mb, plane, bx, by - 1)
                var count: u32
                if mb.class == MbClassIntra16x16 do
                    count = .residualCabac'(15, false)(mb, CatPlaneI16Ac[cast(u64, plane)], storage.ac + cast(u64, raster) * 16, nzA, nzB, scale)
                else do
                    count = .residualCabac'(16, false)(mb, CatPlane4x4[cast(u64, plane)], storage.ac + cast(u64, raster) * 16, nzA, nzB, scale)
                storage.nz[cast(u64, raster)] = cast(u8, count)
                if isLuma do
                    mb.codedBlocks[cast(u64, raster)] = count > 0 ? 1 : 0
            }
        }
    }

    // Returns the DC coded flag of the neighbor macroblock at the given offset, or -1 when
    // it is unavailable; `which` selects luma, Cb, or Cr.
    mtd const dcFlagNeighbor(mb: *Mb, dx, dy: s32, which: s32)->s32
    {
        let neighbor = dx < 0 ? &.neighbors.a : &.neighbors.b
        if not neighbor.available do
            return -1
        if neighbor.info!.skipped do
            return 0
        return cast(s32, .dec!.dcFlags[neighbor.mbIndex * 3 + cast(u64, which)])
    }
}
