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

// Table 9-44 laid out for one lookup from the packed state and the two range bits that select
// its column: index `2 * (range & 0xC0) + state`.
const CabacLpsRange: [512] u8 = #run buildCabacLpsRange()

// The state after a bin, one table for both outcomes: `128 + state` on the MPS path and
// `128 + (state ^ -1)` on the LPS path, which flips valMPS at pStateIdx 0 as Table 9-45 says.
const CabacNextState: [256] u8 = #run buildCabacNextState()

// The renormalization shift bringing a range below 256 back to the interval; zero above.
const CabacNormShift: [512] u8 = #run buildCabacNormShift()

func buildCabacLpsRange()->[512] u8
{
    var result: retval
    for column in 4'u64
    {
        for state in 128'u64 do
            result[column * 128 + state] = CabacRangeLps[(state >> 1) * 4 + column]
    }

    return result
}

func buildCabacNextState()->[256] u8
{
    var result: retval
    for state in 128'u64
    {
        let mps  = cast(u32) (state & 1)
        let flip = (state >> 1) == 0 ? 1'u32 : 0'u32
        result[128 + state] = cast(u8) ((cast(u32) CabacTransMps[state >> 1] << 1) | mps)
        result[127 - state] = cast(u8) ((cast(u32) CabacTransLps[state >> 1] << 1) | (mps ^ flip))
    }

    return result
}

func buildCabacNormShift()->[512] u8
{
    var result: retval
    for range in 512'u64
    {
        var shift = 0'u8
        var value = range
        while value < 256 and shift < 9
        {
            value <<= 1
            shift += 1
        }

        result[range] = shift
    }

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
                m = cast(s32) CabacInitI[index * 2]
                n = cast(s32) CabacInitI[index * 2 + 1]
            }
            else
            {
                let base = cast(u64) cabacInitIdc * 2048 + index * 2
                m = cast(s32) CabacInitPB[base]
                n = cast(s32) CabacInitPB[base + 1]
            }

            let preState = Math.clamp(((m * Math.clamp(sliceQp, 0, 51)) >> 4) + n, 1, 126)
            if preState <= 63 do
                .contexts[index] = cast(u8) ((63 - preState) << 1)
            else do
                .contexts[index] = cast(u8) (((preState - 64) << 1) | 1)
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
        .low      = (cast(u32) data[0] << 18) | (cast(u32) data[1] << 10) | (cast(u32) data[2] << 2) | 2
        .range    = 0x1FE
    }

    // Reports whether decoding consumed bits past the end of the slice data.
    //
    // The bits loaded and not yet consumed sit between the marker and the offset, so the marker's
    // position says how many of the loaded bits are still ahead.
    mtd const hasOverrun()->bool => .position * 8 + cast(u64) Swag.bitCountTz(.low) > .size * 8 + 16

    // Loads the two bytes due once the marker has crossed the sixteen-bit line, as FFmpeg's
    // `refill2`: the marker moves down sixteen bits and the new bits land above it. Past the end
    // of the data the bytes read as zeros, which is what reading past the end yields, and the
    // position keeps advancing so the overrun stays measurable.
    #[Swag.Inline]
    private mtd reload(low: u32)->u32
    {
        let extra = cast(u32) Swag.bitCountTz(low) - 16
        var bits  = 0'u32
        if .position <= .size do
            bits = (cast(u32) .data![.position] << 9) | (cast(u32) .data![.position + 1] << 1)
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
        return .decision(11 + ctx) != 0
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
        elif .header.type == SliceTypeP
        {
            if .decision(14) != 0
            {
                isIntra = true
                mbType  = .intraMbTypeCabac(mb, 17, intraSlice: false)
            }
            elif .decision(15) == 0
            {
                mbType = 3 * .decision(16)
            }
            else
            {
                mbType = 2 - .decision(17)
            }
        }
        else
        {
            var ctx = 0'u32
            if .neighbors.a.available and not .neighbors.a.info!.direct do
                ctx += 1
            if .neighbors.b.available and not .neighbors.b.info!.direct do
                ctx += 1

            if .decision(27 + ctx) == 0
            {
                mbType = 0
            }
            elif .decision(30) == 0
            {
                mbType = 1 + .decision(32)
            }
            else
            {
                var bits = .decision(31) << 3
                bits += .decision(32) << 2
                bits += .decision(32) << 1
                bits += .decision(32)
                if bits < 8
                {
                    mbType = bits + 3
                }
                elif bits == 13
                {
                    isIntra = true
                    mbType  = .intraMbTypeCabac(mb, 32, intraSlice: false)
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
                    bits   = (bits << 1) + .decision(32)
                    mbType = bits - 4
                }
            }
        }

        if isIntra do
            .parseIntraMb(mb, mbType, fromCabac: true)
        elif .header.type == SliceTypeP do
            .parseInterMbP(mb, mbType)
        else do
            .parseInterMbB(mb, mbType)

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
        if .decision(21) != 0 do
            return 0
        if .decision(22) == 0 do
            return 1
        if .decision(23) != 0 do
            return 2
        return 3
    }

    // Decodes one B sub-macroblock type.
    mtd subMbTypeBCabac()->u32
    {
        if .decision(36) == 0 do
            return 0
        if .decision(37) == 0 do
            return 1 + .decision(39)
        var result = 3'u32
        if .decision(38) != 0
        {
            if .decision(39) != 0 do
                return 11 + .decision(39)
            result += 4
        }

        result += 2 * .decision(39)
        result += .decision(39)
        return result
    }

    // Decodes one intra 4x4 or 8x8 prediction mode against its neighbor prediction.
    mtd intraModeCabac(predicted: u32)->u32
    {
        if .decision(68) != 0 do
            return predicted
        var mode = .decision(69)
        mode += 2 * .decision(69)
        mode += 4 * .decision(69)
        return mode >= predicted ? mode + 1 : mode
    }

    // Decodes the intra chroma prediction mode.
    mtd chromaModeCabac(mb: *Mb)->u32
    {
        var ctx = 0'u32
        if .neighbors.a.available and .neighbors.a.info!.chromaMode != 0 do
            ctx += 1
        if .neighbors.b.available and .neighbors.b.info!.chromaMode != 0 do
            ctx += 1
        if .decision(64 + ctx) == 0 do
            return 0
        if .decision(67) == 0 do
            return 1
        if .decision(67) == 0 do
            return 2
        return 3
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
            leftCbp = cast(u32) .neighbors.a.info!.cbpLuma
        if .neighbors.b.available do
            topCbp = cast(u32) .neighbors.b.info!.cbpLuma

        var cbp = 0'u32
        var ctx = (leftCbp & 0x02 ? 0'u32 : 1) + 2 * (topCbp & 0x04 ? 0'u32 : 1)
        cbp += .decision(73 + ctx)
        ctx = (cbp & 0x01 ? 0'u32 : 1) + 2 * (topCbp & 0x08 ? 0'u32 : 1)
        cbp += .decision(73 + ctx) << 1
        ctx = (leftCbp & 0x08 ? 0'u32 : 1) + 2 * (cbp & 0x01 ? 0'u32 : 1)
        cbp += .decision(73 + ctx) << 2
        ctx = (cbp & 0x04 ? 0'u32 : 1) + 2 * (cbp & 0x02 ? 0'u32 : 1)
        cbp += .decision(73 + ctx) << 3
        return cbp
    }

    // Decodes the chroma coded block pattern, two bins.
    mtd cbpChromaCabac(mb: *Mb)->u32
    {
        var leftCbp = 0'u32
        var topCbp  = 0'u32
        if .neighbors.a.available do
            leftCbp = cast(u32) .neighbors.a.info!.cbpChroma
        if .neighbors.b.available do
            topCbp = cast(u32) .neighbors.b.info!.cbpChroma

        var ctx = 0'u32
        if leftCbp > 0 do
            ctx += 1
        if topCbp > 0 do
            ctx += 2
        if .decision(77 + ctx) == 0 do
            return 0

        ctx = 4
        if leftCbp == 2 do
            ctx += 1
        if topCbp == 2 do
            ctx += 2
        return 1 + .decision(77 + ctx)
    }

    // Decodes the macroblock QP delta.
    mtd qpDeltaCabac()->s32
    {
        var ctx   = .lastQpDelta != 0 ? 1'u32 : 0'u32
        var count = 0's32
        while .decision(60 + ctx) != 0
        {
            ctx   = ctx < 2 ? 2 : 3
            count += 1
            if count > 104 do
                break
        }

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

        var ref = 0'u32
        while .decision(54 + ctx) != 0
        {
            ref += 1
            ctx = (ctx >> 2) + 4
            if ref >= 32 do
                break
        }

        return ref
    }

    // Reports whether the block at `rx`, `ry` relative to the macroblock contributes to the
    // reference-index context: it must hold a positive reference that was not produced by a
    // direct mode.
    mtd const refCtxFlag(mb: *Mb, list: u32, rx, ry: s32)->bool
    {
        if rx >= 0 and ry >= 0
        {
            let quad = cast(u64) ((ry >> 1) * 2 + (rx >> 1))
            if mb.subDirect[quad] or mb.directMb do
                return false
            return mb.ctxRef[cast(u64) list, quad] > 0
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
        let index = neighbor.blockBase + cast(u64) ((ry & 3) * (dec.sps!.mbWidth * 4) + (rx & 3))
        if dec.directFlags[index] != 0 and .header.type == SliceTypeB do
            return false
        let ref = list == 0 ? dec.motionL0[index].refIdx : dec.motionL1[index].refIdx
        return ref > 0
    }

    // Decodes one motion vector difference pair, section 9.3.3.1.1.7.
    mtd mvdCabac(mb: *Mb, list: u32, x4, y4: s32)->[2] s16
    {
        let a = .motionAt(mb, list, x4 - 1, y4)
        let b = .motionAt(mb, list, x4, y4 - 1)

        var result: retval
        for component in 2'u32
        {
            let sumA    = component == 0 ? absS32(cast(s32) a.mvdX) : absS32(cast(s32) a.mvdY)
            let sumB    = component == 0 ? absS32(cast(s32) b.mvdX) : absS32(cast(s32) b.mvdY)
            let amvd    = sumA + sumB
            var ctxBase = component == 0 ? 40'u32 : 47'u32
            var ctx     = 0'u32
            if amvd > 2 do
                ctx += 1
            if amvd > 32 do
                ctx += 1

            if .decision(ctxBase + ctx) == 0
            {
                result[component] = 0
                continue
            }

            var value    = 1'u32
            var unaryCtx = ctxBase + 3
            while value < 9 and .decision(unaryCtx) != 0
            {
                if value < 4 do
                    unaryCtx += 1
                value += 1
            }

            if value >= 9
            {
                // Exp-Golomb suffix of order three, in bypass bins.
                var k = 3'u32
                while .bypass() != 0
                {
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
                    k     -= 1
                    value += .bypass() << k
                }
            }

            let sign      = .bypass()
            let magnitude = cast(s32) value
            result[component] = cast(s16) clampS32(sign != 0 ? -magnitude : magnitude, -32768, 32767)
        }

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
    // The decoded bin lands in `bin`.
    #[Swag.Mixin]
    private mtd binDecision(binCtx: u32)
    {
        var #uniq0 = cast(s32) .cabac.contexts[binCtx]
        let #uniq1 = cast(u32) CabacLpsRange[cast(u64) (2 * (range & 0xC0)) + cast(u64) #uniq0]
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
        let #uniq5 = cast(s32) #uniq2 < cast(s32) low
        low    = #uniq5 ? #uniq4 : low
        range  = #uniq5 ? #uniq1 : range
        #uniq0 = #uniq5 ? ~#uniq0 : #uniq0
        .cabac.contexts[binCtx] = CabacNextState[cast(u64) (128 + #uniq0)]
        bin    = cast(u32) (#uniq0 & 1)

        let #uniq3 = cast(u32) CabacNormShift[cast(u64) range]
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
        let #uniq2 = cast(s32) #uniq0 <= cast(s32) low
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

        // Same bin as the bypass, read as a sign: below the range it is positive.
        let #uniq0 = range << 17
        let #uniq1 = low - #wrap #uniq0
        let #uniq2 = cast(s32) #uniq0 <= cast(s32) low
        low   = #uniq2 ? #uniq1 : low
        level = #uniq2 ? -magnitude : magnitude
    }

    // Decodes one bin with the context at `contextIndex`, section 9.3.3.2.1, for the syntax
    // elements decoded one bin at a time.
    mtd decision(contextIndex: u32)->u32
    {
        var range = .cabac.range
        var low   = .cabac.low
        var bin: u32
        .binDecision(contextIndex)
        .cabac.range = range
        .cabac.low   = low
        return bin
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
    // raster position `order` gives it, dequantized by the matching entry of `scale`; a DC block
    // has no `scale` and keeps its levels. Returns the coefficient count.
    //
    // The block size and the DC distinction are compile-time parameters: the four block shapes a
    // stream carries each get a body whose bounds, table choice and store are folded, and only
    // the values the loops read stay live across them.
    func(const MaxCoeffs: u32, const IsDc: bool) residualCabac(me, mb: *Mb, cat: u32, coeffs: [*] s16, nzA, nzB: s32, order: u64, scale: [*] u32?, shift: u32)->u32
    {
        var range = .cabac.range
        var low   = .cabac.low
        var bin: u32

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
            if bin == 0
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
        var count     = 0'u32
        let sigBase   = CabacSigBase[cat]
        let lastBase  = CabacLastBase[cat]
        var scan      = 0'u32
        var foundLast = false
        while scan < MaxCoeffs - 1
        {
            let sigCtx = MaxCoeffs == 64 ? sigBase + cast(u32) SigCoeffCtx8x8[scan] : sigBase + scan
            .binDecision(sigCtx)
            if bin != 0
            {
                indices[count] = cast(u8) scan
                count += 1
                let lastCtx = MaxCoeffs == 64 ? lastBase + cast(u32) LastCoeffCtx8x8[scan] : lastBase + scan
                .binDecision(lastCtx)
                if bin != 0
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
            indices[count] = cast(u8) (MaxCoeffs - 1)
            count += 1
        }

        // Levels, last significant coefficient first.
        let absBase   = CabacAbsBase[cat]
        var node      = 0'u32
        var remaining = count
        var level: s32
        while remaining > 0
        {
            remaining -= 1
            let position  = cast(u64) indices[remaining]
            var magnitude = 1's32
            .binDecision(absBase + cast(u32) CoeffAbsLevel1Ctx[node])
            if bin == 0
            {
                node = cast(u32) CoeffAbsLevelTransition[node]
            }
            else
            {
                magnitude = 2
                let gt1Ctx = absBase + cast(u32) CoeffAbsLevelGt1Ctx[node]
                node = cast(u32) CoeffAbsLevelTransition[8 + node]
                while magnitude < 15
                {
                    .binDecision(gt1Ctx)
                    if bin == 0 do
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

                    magnitude = cast(s32) value + 14
                }
            }

            .binSign(magnitude)
            let raster = cast(u64) ResidualOrder[order + position]
            if IsDc do
                coeffs[raster] = cast(s16) clampS32(level, -32768, 32767)
            else do
                coeffs[raster] = dequantLevel(clampS32(level, -32768, 32767), scale![raster], shift)
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
                let count = .residualCabac'(4, true)(mb, 3, (mb.residual!.chromaDc).buffer + cast(u64) plane * 4, nzA, nzB, ResidualOrderDc, null, 0)
                mb.dcFlags[cast(u64) (1 + plane)] = count > 0 ? 1 : 0
            }
        }

        if mb.cbpChroma == 2
        {
            for plane in 2's32
            {
                let scale = .dequantRow4(mb, cast(u32) plane + 1)
                for block in 4's32
                {
                    let nzA   = .chromaBlockNz(mb, cast(u32) plane, (block & 1) - 1, block >> 1)
                    let nzB   = .chromaBlockNz(mb, cast(u32) plane, block & 1, (block >> 1) - 1)
                    let count = .residualCabac'(15, false)(mb, 4, (mb.residual!.chromaAc).buffer + cast(u64) plane * 64 + cast(u64) block * 16, nzA, nzB, ResidualOrderAc, scale, 4)
                    if plane == 0 do
                        mb.nzCb[cast(u64) block] = cast(u8) count
                    else do
                        mb.nzCr[cast(u64) block] = cast(u8) count
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
            let nzA   = .dcFlagNeighbor(mb, -1, 0, cast(s32) plane)
            let nzB   = .dcFlagNeighbor(mb, 0, -1, cast(s32) plane)
            let count = .residualCabac'(16, true)(mb, CatPlaneDc[cast(u64) plane], storage.dc, nzA, nzB, ResidualOrderDc, null, 0)
            mb.dcFlags[cast(u64) plane] = count > 0 ? 1 : 0
            if count > 0 and isLuma
            {
                for block in 16'u64 do
                    mb.codedBlocks[block] = 1
            }
        }

        for quad in 4's32
        {
            if (mb.cbpLuma & (1'u32 << cast(u32) quad)) == 0 do
                continue
            if mb.transform8x8 and mb.class != MbClassIntra16x16
            {
                // A 4:4:4 8x8 block codes a flag of its own, whose context reads the block left
                // of and above the quadrant's first cell.
                let first = (quad >> 1) * 8 + (quad & 1) * 2
                let nzA   = .blockNz8x8(mb, plane, (first & 3) - 1, first >> 2)
                let nzB   = .blockNz8x8(mb, plane, first & 3, (first >> 2) - 1)
                let count = .residualCabac'(64, false)(mb, CatPlane8x8[cast(u64) plane], storage.t8 + cast(u64) quad * 64, nzA, nzB, ResidualOrder8x8, .dequantRow8(mb, plane), 6)

                // In 4:4:4 the block states a coded flag of its own, so a quadrant the pattern
                // named can still hold nothing.
                for cell in 4's32
                {
                    let raster = (quad >> 1) * 8 + (quad & 1) * 2 + (cell >> 1) * 4 + (cell & 1)
                    storage.nz[cast(u64) raster] = cast(u8) minS32(count, 16)
                    if isLuma do
                        mb.codedBlocks[cast(u64) raster] = count > 0 ? 1 : 0
                }

                continue
            }

            for cell in 4's32
            {
                let raster = (quad >> 1) * 8 + (quad & 1) * 2 + (cell >> 1) * 4 + (cell & 1)
                let bx     = raster & 3
                let by     = raster >> 2
                let nzA    = .blockNz(mb, plane, bx - 1, by)
                let nzB    = .blockNz(mb, plane, bx, by - 1)
                var count: u32
                if mb.class == MbClassIntra16x16 do
                    count = .residualCabac'(15, false)(mb, CatPlaneI16Ac[cast(u64) plane], storage.ac + cast(u64) raster * 16, nzA, nzB, ResidualOrderAc, .dequantRow4(mb, plane), 4)
                else do
                    count = .residualCabac'(16, false)(mb, CatPlane4x4[cast(u64) plane], storage.ac + cast(u64) raster * 16, nzA, nzB, ResidualOrder4x4, .dequantRow4(mb, plane), 4)
                storage.nz[cast(u64) raster] = cast(u8) count
                if isLuma do
                    mb.codedBlocks[cast(u64) raster] = count > 0 ? 1 : 0
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
        return cast(s32) .dec!.dcFlags[neighbor.mbIndex * 3 + cast(u64) which]
    }
}
