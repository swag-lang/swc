//! Format: H.264/AVC decoder component.
//! Supported: Progressive 8-bit 4:2:0 Baseline, Main, and High-profile streams with CAVLC/CABAC, I/P/B slices, weighted prediction, cropping, reordering, and deblocking.
//! Not supported: Interlacing, non-4:2:0 chroma, bit depths above 8, slice groups, data partitioning, scalable/multiview extensions, and lossless transform bypass.
//! Role: This file owns CABAC arithmetic contexts and syntax decoding.
//
#global namespace H264
#global internal

using Core, Core.Errors

// The CABAC arithmetic decoding engine of section 9.3.
//
// Raw slice bits stream through a 64-bit buffer refilled whole words at a time, and
// renormalization shifts in one step, so the per-bin cost stays flat whatever the bin rate.
struct CabacReader
{
    data:      #null const [*] u8     // Slice data, still carrying emulation prevention removed upstream.
    size:      u64
    position:  u64           // Next data byte to load into the bit buffer.
    padBytes:  u64           // Synthetic zero bytes loaded past the end of the data.
    bitBuffer: u64           // Raw slice bits, most significant first.
    bitCount:  s32           // Valid bits at the top of `bitBuffer`.
    low:       u32           // codIOffset.
    range:     u32           // codIRange.
    contexts:  [1024] u8     // Packed state: `(pStateIdx << 1) | valMPS`.
}

// Arithmetic registers kept local across a complete significance-map run.
private struct CabacArithmetic
{
    low:   u32
    range: u32
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

    // Starts the arithmetic engine on the byte-aligned slice data, section 9.3.1.2.
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

    // Reports whether decoding consumed bits past the end of the slice data.
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

    // Decodes one bin with the context at `contextIndex`, section 9.3.3.2.1.
    //
    // The two arithmetic registers are held in locals for the whole bin. They are read and written
    // several times each, and the context update in between writes into this same structure, so
    // left in place they are reloaded after every step: the emitted code read `range` five times
    // and wrote it three for one bin. Renormalization is shared by the two outcomes for the same
    // reason, since it is the same code on a value the branches only have to agree on.
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
            let lpsMps = mps ^ cast(u32) ((pState - #wrap 1) >> 63)
            .contexts[contextIndex] = cast(u8) ((cast(u32) CabacTransLps[pState] << 1) | lpsMps)
            result = mps ^ 1
        }

        let shift = max0S32(cast(s32) @bitcountlz(range) - 23)
        if shift != 0
        {
            range <<= cast(u32) shift
            low   = (low << cast(u32) shift) | .takeBits(cast(u32) shift)
        }

        .range = range
        .low   = low
        return result
    }

    // Kept separate from the generic decision so only the significance-map loop pays the code
    // growth needed to keep the arithmetic state in registers.
    #[Swag.Inline]
    private mtd significanceDecision(contextIndex: u32, arithmetic: *CabacArithmetic)->u32
    {
        let state  = cast(u32) .contexts[contextIndex]
        let pState = cast(u64) (state >> 1)
        let mps    = state & 1
        let lps    = cast(u32) CabacRangeLps[pState * 4 + cast(u64) ((arithmetic.range >> 6) & 3)]

        arithmetic.range -= lps
        let diff = cast(s32) arithmetic.low - cast(s32) arithmetic.range
        let mask = cast #wrap (u32) (diff >> 31)
        arithmetic.low   = (arithmetic.low & mask) | ((cast #wrap (u32) diff) & ~mask)
        arithmetic.range = (arithmetic.range & mask) | (lps & ~mask)
        let lpsMps   = mps ^ cast(u32) ((pState - #wrap 1) >> 63)
        let mpsState = (cast(u32) CabacTransMps[pState] << 1) | mps
        let lpsState = (cast(u32) CabacTransLps[pState] << 1) | lpsMps
        .contexts[contextIndex] = cast(u8) ((mpsState & mask) | (lpsState & ~mask))

        let shift = max0S32(cast(s32) @bitcountlz(arithmetic.range) - 23)
        if shift != 0
        {
            arithmetic.range <<= cast(u32) shift
            arithmetic.low   = (arithmetic.low << cast(u32) shift) | .takeBits(cast(u32) shift)
        }

        return mps ^ (1 & ~mask)
    }

    // Decodes one bypass bin, section 9.3.3.2.3.
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

    // Decodes a bypass sign and applies it without branching.
    #[Swag.Inline]
    private mtd bypassSign(magnitude: s32)->s32
    {
        let low  = (.low << 1) | .takeBits(1)
        let diff = cast(s32) low - cast(s32) .range
        let keep = cast #wrap (u32) (diff >> 31)
        .low = (low & keep) | ((cast #wrap (u32) diff) & ~keep)

        let sign = cast #bit(s32) ~keep
        return (magnitude ^ sign) - sign
    }

    // Decodes the end-of-slice bin, section 9.3.3.2.4.
    mtd terminate()->u32
    {
        .range -= 2
        if .low >= .range do
            return 1

        let shift = max0S32(cast(s32) @bitcountlz(.range) - 23)
        if shift != 0
        {
            .range <<= cast(u32) shift
            .low   = (.low << cast(u32) shift) | .takeBits(cast(u32) shift)
        }

        return 0
    }

    // Decodes `count` bypass bins as an unsigned value.
    mtd bypassBits(count: u32)->u32
    {
        var result = 0'u32
        for count do
            result = (result << 1) | .bypass()
        return result
    }
}

// Context index bases per residual block category (0 luma DC, 1 luma AC of Intra_16x16,
// 2 luma 4x4, 3 chroma DC, 4 chroma AC, 5 luma 8x8), frame coding.
const CabacCbfBase:  [6] u32 = [85, 89, 93, 97, 101, 1012]
const CabacSigBase:  [6] u32 = [105, 120, 134, 149, 152, 402]
const CabacLastBase: [6] u32 = [166, 181, 195, 210, 213, 417]
const CabacAbsBase:  [6] u32 = [227, 237, 247, 257, 266, 426]

// Context of the first `coeff_abs_level_minus1` bin for each level node state.
const CoeffAbsLevel1Ctx:   [8] u8 = [1, 2, 3, 4, 0, 0, 0, 0]
const CoeffAbsLevelGt1Ctx: [8] u8 = [5, 5, 5, 5, 6, 7, 8, 9]

impl Slice
{
    // Decodes the skip flag of the macroblock at the current address, section 9.3.3.1.1.1.
    mtd decodeSkipFlagCabac()->bool
    {
        let dec   = .dec!
        let width = dec.sps!.mbWidth
        var ctx   = 0'u32
        if .mbX > 0
        {
            let left = &dec.mbInfo[.mbAddr - 1]
            if left.sliceId == .sliceId and !left.skipped do
                ctx += 1
        }

        if .mbY > 0
        {
            let top = &dec.mbInfo[.mbAddr - cast(u32) width]
            if top.sliceId == .sliceId and !top.skipped do
                ctx += 1
        }

        if .header.type == SliceTypeB do
            ctx += 13
        return .cabac.decision(11 + ctx) != 0
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
            if .cabac.decision(14) != 0
            {
                isIntra = true
                mbType  = .intraMbTypeCabac(mb, 17, intraSlice: false)
            }
            elif .cabac.decision(15) == 0
            {
                mbType = 3 * .cabac.decision(16)
            }
            else
            {
                mbType = 2 - .cabac.decision(17)
            }
        }
        else
        {
            var ctx = 0'u32
            if .mbAvailable(mb.mbX - 1, mb.mbY) and !.mbInfoAt(mb.mbX - 1, mb.mbY).direct do
                ctx += 1
            if .mbAvailable(mb.mbX, mb.mbY - 1) and !.mbInfoAt(mb.mbX, mb.mbY - 1).direct do
                ctx += 1

            if .cabac.decision(27 + ctx) == 0
            {
                mbType = 0
            }
            elif .cabac.decision(30) == 0
            {
                mbType = 1 + .cabac.decision(32)
            }
            else
            {
                var bits = .cabac.decision(31) << 3
                bits += .cabac.decision(32) << 2
                bits += .cabac.decision(32) << 1
                bits += .cabac.decision(32)
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
                    bits   = (bits << 1) + .cabac.decision(32)
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
            mb.cbpChroma = .cbpChromaCabac(mb)

            if mb.cbpLuma != 0 and pps.transform8x8 and mb.class == MbClassInter and .allowsTransform8x8(mb) do
                mb.transform8x8 = .transformFlagCabac(mb) != 0
        }

        if mb.cbpLuma != 0 or mb.cbpChroma != 0 or mb.class == MbClassIntra16x16
        {
            let delta = .qpDeltaCabac()
            if delta < -26 or delta > 25 do
                fail InvalidFormatError{"H.264 macroblock QP delta is out of range"}
            .qp          = (.qp + delta + 52) % 52
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
            if .mbAvailable(mb.mbX - 1, mb.mbY) and .mbInfoAt(mb.mbX - 1, mb.mbY).class == MbClassIntra16x16 do
                ctx += 1
            if .mbAvailable(mb.mbX, mb.mbY - 1) and .mbInfoAt(mb.mbX, mb.mbY - 1).class == MbClassIntra16x16 do
                ctx += 1
            if .cabac.decision(base + ctx) == 0 do
                return 0
            base += 2
        }
        elif .cabac.decision(base) == 0
        {
            return 0
        }

        if .cabac.terminate() != 0 do
            return 25

        var mbType = 1'u32
        mbType += 12 * .cabac.decision(base + 1)
        if .cabac.decision(base + 2) != 0 do
            mbType += 4 + 4 * .cabac.decision(base + (intraSlice ? 3 : 2))
        mbType += 2 * .cabac.decision(base + (intraSlice ? 4 : 3))
        mbType += .cabac.decision(base + (intraSlice ? 5 : 3))
        return mbType
    }

    // Decodes one P sub-macroblock type.
    mtd subMbTypePCabac()->u32
    {
        if .cabac.decision(21) != 0 do
            return 0
        if .cabac.decision(22) == 0 do
            return 1
        if .cabac.decision(23) != 0 do
            return 2
        return 3
    }

    // Decodes one B sub-macroblock type.
    mtd subMbTypeBCabac()->u32
    {
        if .cabac.decision(36) == 0 do
            return 0
        if .cabac.decision(37) == 0 do
            return 1 + .cabac.decision(39)
        var result = 3'u32
        if .cabac.decision(38) != 0
        {
            if .cabac.decision(39) != 0 do
                return 11 + .cabac.decision(39)
            result += 4
        }

        result += 2 * .cabac.decision(39)
        result += .cabac.decision(39)
        return result
    }

    // Decodes one intra 4x4 or 8x8 prediction mode against its neighbor prediction.
    mtd intraModeCabac(predicted: u32)->u32
    {
        if .cabac.decision(68) != 0 do
            return predicted
        var mode = .cabac.decision(69)
        mode += 2 * .cabac.decision(69)
        mode += 4 * .cabac.decision(69)
        return mode >= predicted ? mode + 1 : mode
    }

    // Decodes the intra chroma prediction mode.
    mtd chromaModeCabac(mb: *Mb)->u32
    {
        var ctx = 0'u32
        if .mbAvailable(mb.mbX - 1, mb.mbY) and .mbInfoAt(mb.mbX - 1, mb.mbY).chromaMode != 0 do
            ctx += 1
        if .mbAvailable(mb.mbX, mb.mbY - 1) and .mbInfoAt(mb.mbX, mb.mbY - 1).chromaMode != 0 do
            ctx += 1
        if .cabac.decision(64 + ctx) == 0 do
            return 0
        if .cabac.decision(67) == 0 do
            return 1
        if .cabac.decision(67) == 0 do
            return 2
        return 3
    }

    // Decodes the 8x8 transform flag with its neighbor context.
    mtd transformFlagCabac(mb: *Mb)->u32
    {
        var ctx = 0'u32
        if .mbAvailable(mb.mbX - 1, mb.mbY) and .mbInfoAt(mb.mbX - 1, mb.mbY).transform8x8 do
            ctx += 1
        if .mbAvailable(mb.mbX, mb.mbY - 1) and .mbInfoAt(mb.mbX, mb.mbY - 1).transform8x8 do
            ctx += 1
        return .cabac.decision(399 + ctx)
    }

    // Decodes the luma coded block pattern, four bins with spatial contexts.
    mtd cbpLumaCabac(mb: *Mb)->u32
    {
        // An unavailable neighbor reads as fully coded, so it never raises the context.
        var leftCbp = 0xF'u32
        var topCbp  = 0xF'u32
        if .mbAvailable(mb.mbX - 1, mb.mbY) do
            leftCbp = cast(u32) .mbInfoAt(mb.mbX - 1, mb.mbY).cbpLuma
        if .mbAvailable(mb.mbX, mb.mbY - 1) do
            topCbp = cast(u32) .mbInfoAt(mb.mbX, mb.mbY - 1).cbpLuma

        var cbp = 0'u32
        var ctx = (leftCbp & 0x02 ? 0'u32 : 1) + 2 * (topCbp & 0x04 ? 0'u32 : 1)
        cbp += .cabac.decision(73 + ctx)
        ctx = (cbp & 0x01 ? 0'u32 : 1) + 2 * (topCbp & 0x08 ? 0'u32 : 1)
        cbp += .cabac.decision(73 + ctx) << 1
        ctx = (leftCbp & 0x08 ? 0'u32 : 1) + 2 * (cbp & 0x01 ? 0'u32 : 1)
        cbp += .cabac.decision(73 + ctx) << 2
        ctx = (cbp & 0x04 ? 0'u32 : 1) + 2 * (cbp & 0x02 ? 0'u32 : 1)
        cbp += .cabac.decision(73 + ctx) << 3
        return cbp
    }

    // Decodes the chroma coded block pattern, two bins.
    mtd cbpChromaCabac(mb: *Mb)->u32
    {
        var leftCbp = 0'u32
        var topCbp  = 0'u32
        if .mbAvailable(mb.mbX - 1, mb.mbY) do
            leftCbp = cast(u32) .mbInfoAt(mb.mbX - 1, mb.mbY).cbpChroma
        if .mbAvailable(mb.mbX, mb.mbY - 1) do
            topCbp = cast(u32) .mbInfoAt(mb.mbX, mb.mbY - 1).cbpChroma

        var ctx = 0'u32
        if leftCbp > 0 do
            ctx += 1
        if topCbp > 0 do
            ctx += 2
        if .cabac.decision(77 + ctx) == 0 do
            return 0

        ctx = 4
        if leftCbp == 2 do
            ctx += 1
        if topCbp == 2 do
            ctx += 2
        return 1 + .cabac.decision(77 + ctx)
    }

    // Decodes the macroblock QP delta.
    mtd qpDeltaCabac()->s32
    {
        var ctx   = .lastQpDelta != 0 ? 1'u32 : 0'u32
        var count = 0's32
        while .cabac.decision(60 + ctx) != 0
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
        if .refCtxFlag(mb, list, mb.mbX * 4 + x4 - 1, mb.mbY * 4 + y4) do
            ctx += 1
        if .refCtxFlag(mb, list, mb.mbX * 4 + x4, mb.mbY * 4 + y4 - 1) do
            ctx += 2

        var ref = 0'u32
        while .cabac.decision(54 + ctx) != 0
        {
            ref += 1
            ctx = (ctx >> 2) + 4
            if ref >= 32 do
                break
        }

        return ref
    }

    // Reports whether the neighbor block contributes to the reference-index context: it must
    // hold a positive reference that was not produced by a direct mode.
    mtd const refCtxFlag(mb: *Mb, list: u32, x4, y4: s32)->bool
    {
        let dec = .dec!
        let gw  = dec.sps!.mbWidth * 4
        if x4 < 0 or y4 < 0 or x4 >= gw or y4 >= dec.sps!.mbHeight * 4 do
            return false

        let nMbX = x4 >> 2
        let nMbY = y4 >> 2
        if nMbX == mb.mbX and nMbY == mb.mbY
        {
            let quad = cast(u64) (((y4 & 3) >> 1) * 2 + ((x4 & 3) >> 1))
            if mb.subDirect[quad] or mb.directMb do
                return false
            return mb.ctxRef[cast(u64) list, quad] > 0
        }

        if dec.mbInfo[cast(u64) (nMbY * dec.sps!.mbWidth + nMbX)].sliceId != .sliceId do
            return false
        let info = &dec.mbInfo[cast(u64) (nMbY * dec.sps!.mbWidth + nMbX)]
        if info.class != MbClassInter do
            return false
        if .header.type == SliceTypeP and info.skipped do
            return false

        let index = cast(u64) (y4 * gw + x4)
        if dec.directFlags[index] != 0 and .header.type == SliceTypeB do
            return false
        let ref = list == 0 ? dec.refIdxL0[index] : dec.refIdxL1[index]
        return ref > 0
    }

    // Decodes one motion vector difference pair, section 9.3.3.1.1.7.
    mtd mvdCabac(mb: *Mb, list: u32, x4, y4: s32)->[2] s16 fail
    {
        let a = .motionAt(mb, list, mb.mbX * 4 + x4 - 1, mb.mbY * 4 + y4)
        let b = .motionAt(mb, list, mb.mbX * 4 + x4, mb.mbY * 4 + y4 - 1)

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

            if .cabac.decision(ctxBase + ctx) == 0
            {
                result[component] = 0
                continue
            }

            var value    = 1'u32
            var unaryCtx = ctxBase + 3
            while value < 9 and .cabac.decision(unaryCtx) != 0
            {
                if value < 4 do
                    unaryCtx += 1
                value += 1
            }

            if value >= 9
            {
                // Exp-Golomb suffix of order three, in bypass bins.
                var k = 3'u32
                while .cabac.bypass() != 0
                {
                    value += 1'u32 << k
                    k     += 1
                    if k > 24 do
                        fail InvalidFormatError{"H.264 motion vector difference does not decode"}
                }

                while k > 0
                {
                    k     -= 1
                    value += .cabac.bypass() << k
                }
            }

            let sign      = .cabac.bypass()
            let magnitude = cast(s32) value
            result[component] = cast(s16) clampS32(sign != 0 ? -magnitude : magnitude, -32768, 32767)
        }

        return result
    }

    // Decodes one residual block, sections 9.3.3.1.1.9 and 9.3.3.1.3.
    //
    // `cat` is the block category, `coeffs` the scan-ordered destination, `maxCoeffs` its
    // length. Categories other than 5 first decode a coded-block flag against the neighbor
    // flags `nzA` and `nzB` (-1 for an unavailable neighbor). Returns the coefficient count.
    mtd residualCabac(mb: *Mb, cat: u32, coeffs: [*] s16, maxCoeffs: u32, nzA, nzB: s32)->u32 fail
    {
        if cat != 5
        {
            var ctx   = CabacCbfBase[cat]
            let intra = mb.class != MbClassInter
            if nzA > 0 or (nzA < 0 and intra) do
                ctx += 1
            if nzB > 0 or (nzB < 0 and intra) do
                ctx += 2
            if .cabac.decision(ctx) == 0 do
                return 0
        }

        // Significance map.
        var indices: [64] u32 = undefined
        var count             = 0'u32
        let sigBase           = CabacSigBase[cat]
        let lastBase          = CabacLastBase[cat]
        var scan              = 0'u32
        var foundLast         = false
        var arithmetic        = CabacArithmetic{.cabac.low, .cabac.range}

        // The 8x8 category maps every scan position through a table while every other category
        // uses the position itself. Choosing once instead of per coefficient keeps the two
        // decisions of the inner loop back to back.
        if cat == 5
        {
            while scan < maxCoeffs - 1
            {
                if .cabac.significanceDecision(sigBase + cast(u32) SigCoeffCtx8x8[scan], &arithmetic) != 0
                {
                    indices[count] = scan
                    count          += 1
                    if .cabac.significanceDecision(lastBase + cast(u32) LastCoeffCtx8x8[scan], &arithmetic) != 0
                    {
                        foundLast = true
                        break
                    }
                }

                scan += 1
            }
        }
        else
        {
            while scan < maxCoeffs - 1
            {
                if .cabac.significanceDecision(sigBase + scan, &arithmetic) != 0
                {
                    indices[count] = scan
                    count          += 1
                    if .cabac.significanceDecision(lastBase + scan, &arithmetic) != 0
                    {
                        foundLast = true
                        break
                    }
                }

                scan += 1
            }
        }

        .cabac.low   = arithmetic.low
        .cabac.range = arithmetic.range

        if !foundLast and scan == maxCoeffs - 1
        {
            indices[count] = scan
            count          += 1
        }

        if count == 0 do
            return 0

        // Levels, last significant coefficient first.
        let absBase   = CabacAbsBase[cat]
        var node      = 0'u32
        var remaining = count
        while remaining > 0
        {
            remaining -= 1
            let position  = indices[remaining]
            var magnitude = 1's32
            if .cabac.decision(absBase + cast(u32) CoeffAbsLevel1Ctx[node]) == 0
            {
                node = cast(u32) CoeffAbsLevelTransition[node]
            }
            else
            {
                magnitude = 2
                let gt1Ctx = absBase + cast(u32) CoeffAbsLevelGt1Ctx[node]
                node = cast(u32) CoeffAbsLevelTransition[8 + node]
                while magnitude < 15 and .cabac.decision(gt1Ctx) != 0 do
                    magnitude += 1

                if magnitude >= 15
                {
                    // Exp-Golomb order zero suffix in bypass bins.
                    var zeros = 0'u32
                    while .cabac.bypass() != 0 and zeros < 23 do
                        zeros += 1
                    var value = 1'u32
                    while zeros > 0
                    {
                        zeros -= 1
                        value = (value << 1) + .cabac.bypass()
                    }

                    magnitude = cast(s32) value + 14
                }
            }

            magnitude        = .cabac.bypassSign(magnitude)
            coeffs[position] = cast(s16) clampS32(magnitude, -32768, 32767)
        }

        if .cabac.hasOverrun() do
            fail InvalidFormatError{"H.264 residual block is truncated"}
        return count
    }

    // Parses every residual block of the macroblock with CABAC coding.
    mtd parseResidualCabac(mb: *Mb) fail
    {
        let dec   = .dec!
        let mbIdx = cast(u64) (mb.mbY * dec.sps!.mbWidth + mb.mbX)

        if mb.class == MbClassIntra16x16
        {
            let nzA   = .dcFlagNeighbor(mb, -1, 0, 0)
            let nzB   = .dcFlagNeighbor(mb, 0, -1, 0)
            let count = .residualCabac(mb, 0, @dataof(mb.residual!.lumaDc), 16, nzA, nzB)
            mb.dcFlags[0] = count > 0 ? 1 : 0
            if count > 0
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
                let count = .residualCabac(mb, 5, @dataof(mb.residual!.luma8) + cast(u64) quad * 64, 64, 0, 0)
                for cell in 4's32
                {
                    let raster = (quad >> 1) * 8 + (quad & 1) * 2 + (cell >> 1) * 4 + (cell & 1)
                    mb.nzLuma[cast(u64) raster]      = cast(u8) minS32(count, 16)
                    mb.codedBlocks[cast(u64) raster] = 1
                }

                continue
            }

            for cell in 4's32
            {
                let raster = (quad >> 1) * 8 + (quad & 1) * 2 + (cell >> 1) * 4 + (cell & 1)
                let bx     = raster & 3
                let by     = raster >> 2
                let nzA    = .blockNz(mb, mb.mbX * 4 + bx - 1, mb.mbY * 4 + by)
                let nzB    = .blockNz(mb, mb.mbX * 4 + bx, mb.mbY * 4 + by - 1)
                var count: u32
                if mb.class == MbClassIntra16x16 do
                    count = .residualCabac(mb, 1, @dataof(mb.residual!.lumaAc) + cast(u64) raster * 16 + 1, 15, nzA, nzB)
                else do
                    count = .residualCabac(mb, 2, @dataof(mb.residual!.lumaAc) + cast(u64) raster * 16, 16, nzA, nzB)
                mb.nzLuma[cast(u64) raster]      = cast(u8) count
                mb.codedBlocks[cast(u64) raster] = count > 0 ? 1 : 0
            }
        }

        if mb.cbpChroma != 0
        {
            for plane in 2's32
            {
                let nzA   = .dcFlagNeighbor(mb, -1, 0, 1 + plane)
                let nzB   = .dcFlagNeighbor(mb, 0, -1, 1 + plane)
                let count = .residualCabac(mb, 3, @dataof(mb.residual!.chromaDc) + cast(u64) plane * 4, 4, nzA, nzB)
                mb.dcFlags[cast(u64) (1 + plane)] = count > 0 ? 1 : 0
            }
        }

        if mb.cbpChroma == 2
        {
            for plane in 2's32
            {
                for block in 4's32
                {
                    let nzA   = .chromaBlockNz(mb, cast(u32) plane, mb.mbX * 2 + (block & 1) - 1, mb.mbY * 2 + (block >> 1))
                    let nzB   = .chromaBlockNz(mb, cast(u32) plane, mb.mbX * 2 + (block & 1), mb.mbY * 2 + (block >> 1) - 1)
                    let count = .residualCabac(mb, 4, @dataof(mb.residual!.chromaAc) + cast(u64) plane * 64 + cast(u64) block * 16 + 1, 15, nzA, nzB)
                    if plane == 0 do
                        mb.nzCb[cast(u64) block] = cast(u8) count
                    else do
                        mb.nzCr[cast(u64) block] = cast(u8) count
                }
            }
        }
    }

    // Returns the DC coded flag of the neighbor macroblock at the given offset, or -1 when
    // it is unavailable; `which` selects luma, Cb, or Cr.
    mtd const dcFlagNeighbor(mb: *Mb, dx, dy: s32, which: s32)->s32
    {
        let dec = .dec!
        if !.mbAvailable(mb.mbX + dx, mb.mbY + dy) do
            return -1
        let index = cast(u64) ((mb.mbY + dy) * dec.sps!.mbWidth + mb.mbX + dx)
        if dec.mbInfo[index].skipped do
            return 0
        return cast(s32) dec.dcFlags[index * 3 + cast(u64) which]
    }
}
