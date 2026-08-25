//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns residual coding syntax and coefficient decoding.
//
#global namespace Hevc
#global internal

using Core, Core.Errors

// Table 9-50: the significance context of each position of a 4x4 transform block.
const SigCtxMap4x4: [16] u8 = [0, 1, 4, 5, 2, 3, 4, 5, 6, 6, 8, 8, 7, 7, 8, 8]

// What one call to residual coding reports back about the block it read.
struct ResidualResult
{
    transformSkip: bool
    lastX:         u32
    lastY:         u32
}

impl Decoder
{
    // Reads the transform coefficients of one block, clause 7.3.8.11.
    //
    // The parsed levels are left in `.coefficients` in raster order, and everything the transform
    // needs to know about where they sit is reported back.
    mtd residualCoding(x0, y0: s32, log2TrafoSize, component: u32, predModeIntra: u32, isIntra, bypass: bool)->ResidualResult fail
    {
        let sps = .activeSps!
        let pps = .activePps!
        let size = 1'u32 << log2TrafoSize

        var result: retval
        Memory.set(&.coefficients, 0, cast(u64) (size * size) * #sizeof(s16))
        Memory.set(&.coefficientRows, 0, #sizeof(.coefficientRows))
        .coefficientColumns = 0

        if pps.transformSkipEnabled and !bypass and log2TrafoSize <= pps.log2MaxTransformSkipSize
        {
            let context = component == 0 ? CtxTransformSkipFlagLuma : CtxTransformSkipFlagChroma
            result.transformSkip = .cabac.decision(context) != 0
        }

        // The scan follows the intra direction in the small blocks where it pays for itself,
        // clause 7.4.9.11.
        var scanIdx = ScanDiagonal
        let directional = isIntra and (log2TrafoSize == 2 or (log2TrafoSize == 3 and component == 0))
        if directional
        {
            if predModeIntra >= 6 and predModeIntra <= 14 do
                scanIdx = ScanVertical
            elif predModeIntra >= 22 and predModeIntra <= 30 do
                scanIdx = ScanHorizontal
        }

        // Both prefixes are stated before either suffix, clause 7.3.8.11.
        let prefixX = .readLastPrefix(component, log2TrafoSize, CtxLastSigCoeffXPrefix)
        let prefixY = .readLastPrefix(component, log2TrafoSize, CtxLastSigCoeffYPrefix)
        var lastX = prefixX
        var lastY = prefixY
        if prefixX > 3 do
            lastX = .readLastSuffix(prefixX)
        if prefixY > 3 do
            lastY = .readLastSuffix(prefixY)

        if scanIdx == ScanVertical
        {
            let swap = lastX
            lastX = lastY
            lastY = swap
        }

        if lastX >= size or lastY >= size do
            fail InvalidFormatError{"HEVC last significant coefficient is outside its transform block"}

        // Walk back from the end of the scan to the sub-block and position the last coefficient
        // sits in; everything after it in scan order is zero.
        let subBlockLog2 = log2TrafoSize - 2
        var lastSubBlock = (1'u32 << (subBlockLog2 * 2)) - 1
        var lastScanPos  = 16'u32
        for
        {
            if !lastScanPos
            {
                lastScanPos = 16
                if !lastSubBlock do
                    break
                lastSubBlock -= 1
            }

            lastScanPos -= 1
            let xS = cast(u32) ScanX[subBlockLog2, scanIdx, lastSubBlock]
            let yS = cast(u32) ScanY[subBlockLog2, scanIdx, lastSubBlock]
            let xC = (xS << 2) + cast(u32) ScanX[2, scanIdx, lastScanPos]
            let yC = (yS << 2) + cast(u32) ScanY[2, scanIdx, lastScanPos]
            if xC == lastX and yC == lastY do
                break
        }

        var codedSubBlock: [64] bool
        var maxX, maxY = 0'u32

        // The greater-than-one context set carries over between the sub-blocks of one block,
        // clause 9.3.4.2.6.
        var anySubBlockCoded  = false
        var previousGreater1Ctx = 0'u32
        var previousGreater1Flag = false

        var subBlock = cast(s32) lastSubBlock
        while subBlock >= 0
        {
            let index = cast(u32) subBlock
            let xS    = cast(u32) ScanX[subBlockLog2, scanIdx, index]
            let yS    = cast(u32) ScanY[subBlockLog2, scanIdx, index]

            var inferDcSignificant = false
            var coded = true
            if index < lastSubBlock and index > 0
            {
                coded = .cabac.decision(CtxCodedSubBlockFlag + .codedSubBlockContext(&codedSubBlock[0], xS, yS, subBlockLog2, component)) != 0
                inferDcSignificant = true
            }

            codedSubBlock[yS * 8 + xS] = coded
            if !coded
            {
                subBlock -= 1
                continue
            }

            // Significance of every coefficient of the sub-block, walked backwards.
            var significant: [16] bool
            var significantCount = 0'u32
            var first = index == lastSubBlock ? cast(s32) lastScanPos - 1 : 15's32
            if index == lastSubBlock
            {
                significant[lastScanPos] = true
                significantCount = 1
            }

            var position = first
            while position >= 0
            {
                let scanPos = cast(u32) position
                let xC      = (xS << 2) + cast(u32) ScanX[2, scanIdx, scanPos]
                let yC      = (yS << 2) + cast(u32) ScanY[2, scanIdx, scanPos]
                if position > 0 or !inferDcSignificant
                {
                    let context = .significanceContext(&codedSubBlock[0], xC, yC, xS, yS, scanIdx, log2TrafoSize, subBlockLog2, component)
                    if .cabac.decision(CtxSigCoeffFlag + context) != 0
                    {
                        significant[scanPos] = true
                        significantCount += 1
                        inferDcSignificant = false
                    }
                }
                elif position == 0
                {
                    // The last coefficient of a coded sub-block is significant by inference when
                    // every other one turned out not to be.
                    significant[0] = true
                    significantCount += 1
                }

                position -= 1
            }

            if !significantCount
            {
                subBlock -= 1
                continue
            }

            // Levels above one, for at most eight coefficients of the sub-block.
            var greater1: [16] bool
            var greater2 = false
            var greater1Count = 0'u32
            var lastGreater1ScanPos = -1's32
            var firstSigScanPos = 16's32
            var lastSigScanPos  = -1's32

            var ctxSet = (index == 0 or component > 0) ? 0'u32 : 2'u32
            var lastCtx = 1'u32
            if anySubBlockCoded
            {
                lastCtx = previousGreater1Ctx
                if lastCtx > 0 do
                    lastCtx = previousGreater1Flag ? 0 : lastCtx + 1
            }

            if !lastCtx do
                ctxSet += 1
            var greater1Ctx = 1'u32
            var greater1Flag = false
            var decodedAny = false

            position = 15
            while position >= 0
            {
                let scanPos = cast(u32) position
                if significant[scanPos]
                {
                    if greater1Count < 8
                    {
                        if decodedAny and greater1Ctx > 0 do
                            greater1Ctx = greater1Flag ? 0 : greater1Ctx + 1

                        var context = ctxSet * 4 + Math.min(3'u32, greater1Ctx)
                        if component > 0 do
                            context += 16
                        greater1Flag = .cabac.decision(CtxCoeffAbsLevelGreater1Flag + context) != 0
                        decodedAny   = true
                        greater1[scanPos] = greater1Flag
                        greater1Count += 1
                        if greater1Flag and lastGreater1ScanPos < 0 do
                            lastGreater1ScanPos = position
                    }

                    if lastSigScanPos < 0 do
                        lastSigScanPos = position
                    firstSigScanPos = position
                }

                position -= 1
            }

            if decodedAny
            {
                previousGreater1Ctx  = greater1Ctx
                previousGreater1Flag = greater1Flag
                anySubBlockCoded     = true
            }

            // The sign of the first coefficient may be carried by the parity of the sub-block
            // rather than by a bin of its own, clause 7.4.9.11.
            let signHidden = !bypass and lastSigScanPos - firstSigScanPos > 3

            if lastGreater1ScanPos >= 0
            {
                var context = ctxSet
                if component > 0 do
                    context += 4
                greater2 = .cabac.decision(CtxCoeffAbsLevelGreater2Flag + context) != 0
            }

            var signs = 0'u32
            var signCount = 0'u32
            position = 15
            while position >= 0
            {
                let scanPos = cast(u32) position
                if significant[scanPos] and (!pps.signDataHiding or !signHidden or position != firstSigScanPos)
                {
                    signs = (signs << 1) | .cabac.bypass()
                    signCount += 1
                }

                position -= 1
            }

            // Remaining magnitude, and the levels themselves.
            var signIndex = signCount
            var numSigCoeff = 0'u32
            var sumAbsLevel = 0'u32
            var riceParam = 0'u32
            var lastAbsLevel = 0'u32
            var firstRemaining = true

            position = 15
            while position >= 0
            {
                let scanPos = cast(u32) position
                if !significant[scanPos]
                {
                    position -= 1
                    continue
                }

                var baseLevel = 1'u32
                if greater1[scanPos] do
                    baseLevel += 1
                if position == lastGreater1ScanPos and greater2 do
                    baseLevel += 1

                let threshold = numSigCoeff < 8 ? (position == lastGreater1ScanPos ? 3'u32 : 2'u32) : 1'u32
                var level = baseLevel
                if baseLevel == threshold
                {
                    if !firstRemaining
                    {
                        riceParam = Math.min(riceParam + (lastAbsLevel > 3 * (1'u32 << riceParam) ? 1'u32 : 0'u32), 4)
                    }

                    let remaining = .readCoeffAbsLevelRemaining(riceParam)
                    level        = baseLevel + remaining
                    lastAbsLevel = level
                    firstRemaining = false
                }

                var sign = false
                if pps.signDataHiding and signHidden and position == firstSigScanPos
                {
                    sumAbsLevel += level
                    sign = (sumAbsLevel & 1) != 0
                }
                else
                {
                    signIndex -= 1
                    sign = ((signs >> signIndex) & 1) != 0
                    if pps.signDataHiding and signHidden do
                        sumAbsLevel += level
                }

                let xC = (xS << 2) + cast(u32) ScanX[2, scanIdx, scanPos]
                let yC = (yS << 2) + cast(u32) ScanY[2, scanIdx, scanPos]
                let value = cast(s32) Math.min(level, 32767'u32)
                .coefficients[yC * size + xC] = cast(s16) (sign ? -value : value)
                .coefficientRows[xC] |= 1'u32 << yC
                .coefficientColumns |= 1'u32 << xC
                maxX = Math.max(maxX, xC)
                maxY = Math.max(maxY, yC)
                numSigCoeff += 1
                position -= 1
            }

            subBlock -= 1
        }

        if .cabac.hasOverrun() do
            fail InvalidFormatError{"HEVC residual data runs past the end of its slice segment"}

        result.lastX = maxX
        result.lastY = maxY
        return result
    }

    // Reads the prefix of one last-significant-coefficient position, clause 9.3.4.2.3.
    private mtd readLastPrefix(component, log2TrafoSize, contextBase: u32)->u32
    {
        var offset, shift: u32
        if !component
        {
            offset = 3 * (log2TrafoSize - 2) + ((log2TrafoSize - 1) >> 2)
            shift  = (log2TrafoSize + 1) >> 2
        }
        else
        {
            offset = 15
            shift  = log2TrafoSize - 2
        }

        let maximum = (log2TrafoSize << 1) - 1
        var prefix  = 0'u32
        while prefix < maximum
        {
            if .cabac.decision(contextBase + (prefix >> shift) + offset) == 0 do
                break
            prefix += 1
        }

        return prefix
    }

    // Turns one last-significant-coefficient prefix into a position, equations 7-75 and 7-77.
    private mtd readLastSuffix(prefix: u32)->u32
    {
        let bits = (prefix >> 1) - 1
        return (1'u32 << bits) * (2 + (prefix & 1)) + .cabac.bypassBits(bits)
    }

    // Reads one `coeff_abs_level_remaining`, clause 9.3.3.11.
    private mtd readCoeffAbsLevelRemaining(riceParam: u32)->u32
    {
        var prefix = 0'u32
        while prefix < 4 and .cabac.bypass() != 0 do
            prefix += 1

        if prefix < 4 do
            return (prefix << riceParam) + .cabac.bypassBits(riceParam)

        // Past the truncated Rice prefix the value continues as an Exp-Golomb code of order one
        // above the Rice parameter, equation 9-13.
        var extension = 0'u32
        while extension < 24 and .cabac.bypass() != 0 do
            extension += 1

        let order  = riceParam + 1
        let escape = ((1'u32 << extension) - 1) << order
        return (4'u32 << riceParam) + escape + .cabac.bypassBits(order + extension)
    }

    // Returns the context of one `coded_sub_block_flag`, clause 9.3.4.2.4.
    private mtd const codedSubBlockContext(coded: const [*] bool, xS, yS, subBlockLog2, component: u32)->u32
    {
        let limit = (1'u32 << subBlockLog2) - 1
        var context = 0'u32
        if xS < limit and coded[yS * 8 + xS + 1] do
            context += 1
        if yS < limit and coded[(yS + 1) * 8 + xS] do
            context += 1
        context = Math.min(context, 1)
        return component == 0 ? context : 2 + context
    }

    // Returns the context of one `sig_coeff_flag`, clause 9.3.4.2.5.
    private mtd const significanceContext(coded: const [*] bool, xC, yC, xS, yS, scanIdx, log2TrafoSize, subBlockLog2, component: u32)->u32
    {
        var sigCtx: u32
        if log2TrafoSize == 2
        {
            sigCtx = cast(u32) SigCtxMap4x4[(yC << 2) + xC]
        }
        elif !xC and !yC
        {
            sigCtx = 0
        }
        else
        {
            let limit = (1'u32 << subBlockLog2) - 1
            var previous = 0'u32
            if xS < limit and coded[yS * 8 + xS + 1] do
                previous += 1
            if yS < limit and coded[(yS + 1) * 8 + xS] do
                previous += 2

            let xP = xC & 3
            let yP = yC & 3
            switch previous
            {
            case 0:
                sigCtx = xP + yP == 0 ? 2 : (xP + yP < 3 ? 1 : 0)
            case 1:
                sigCtx = !yP ? 2 : (yP == 1 ? 1 : 0)
            case 2:
                sigCtx = !xP ? 2 : (xP == 1 ? 1 : 0)
            default:
                sigCtx = 2
            }

            if !component
            {
                if xS + yS > 0 do
                    sigCtx += 3
                sigCtx += log2TrafoSize == 3 ? (scanIdx == ScanDiagonal ? 9'u32 : 15'u32) : 21'u32
            }
            else
            {
                sigCtx += log2TrafoSize == 3 ? 9'u32 : 12'u32
            }
        }

        return component == 0 ? sigCtx : 27 + sigCtx
    }
}
