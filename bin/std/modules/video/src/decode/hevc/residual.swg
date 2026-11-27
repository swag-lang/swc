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

// Clause 9.3.4.2.5: what the position inside a sub-block adds to a `sig_coeff_flag` context,
// one row per pattern of coded neighbouring sub-blocks.
const SigCtxPattern: [4, 16] u8 = [[2, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0], [2, 2, 2, 2, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0], [2, 1, 0, 0, 2, 1, 0, 0, 2, 1, 0, 0, 2, 1, 0, 0], [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]]

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
    mtd residualCoding(_, _: s32, log2TrafoSize, component: u32, predModeIntra: u32, isIntra, bypass: bool)->ResidualResult fail
    {
        let pps  = unwrap .activePps
        let size = 1_u32 << log2TrafoSize

        var result: #returntype
        Memory.set(&.coefficients, 0, cast(u64, (size * size)) * #sizeof(s16))
        Memory.set(&.coefficientRows, 0, #sizeof(.coefficientRows))
        .coefficientColumns = 0

        if pps.transformSkipEnabled and not bypass and log2TrafoSize <= pps.log2MaxTransformSkipSize
        {
            let context = component == 0 ? CtxTransformSkipFlagLuma : CtxTransformSkipFlagChroma
            result.transformSkip = .cabac.decision(context) != 0
        }

        // The scan follows the intra direction in the small blocks where it pays for itself,
        // clause 7.4.9.11.
        var scanIdx     = ScanDiagonal
        let directional = isIntra and (log2TrafoSize == 2 or (log2TrafoSize == 3 and component == 0))
        if directional
        {
            if predModeIntra >= 6 and predModeIntra <= 14
            {
                scanIdx = ScanVertical
            }
            else if predModeIntra >= 22 and predModeIntra <= 30
            {
                scanIdx = ScanHorizontal
            }
        }

        // Both prefixes are stated before either suffix, clause 7.3.8.11.
        let prefixX = .readLastPrefix(component, log2TrafoSize, CtxLastSigCoeffXPrefix)
        let prefixY = .readLastPrefix(component, log2TrafoSize, CtxLastSigCoeffYPrefix)
        var lastX   = prefixX
        var lastY   = prefixY
        if prefixX > 3
        {
            lastX = .readLastSuffix(prefixX)
        }

        if prefixY > 3
        {
            lastY = .readLastSuffix(prefixY)
        }

        if scanIdx == ScanVertical
        {
            let swap = lastX
            lastX = lastY
            lastY = swap
        }

        if lastX >= size or lastY >= size
        {
            fail InvalidFormatError{"HEVC last significant coefficient is outside its transform block"}
        }

        // Where the last coefficient sits in the scan, which is where the walk below starts.
        // The scan is a permutation of the block, so its inverse says that outright.
        let subBlockLog2 = log2TrafoSize - 2
        let subSide      = 1_u32 << subBlockLog2
        let lastSubBlock = cast(u32, ScanIndex[subBlockLog2, scanIdx, (lastY >> 2) * subSide + (lastX >> 2)])
        let lastScanPos  = cast(u32, ScanIndex[2, scanIdx, (lastY & 3) * 4 + (lastX & 3)])

        var codedSubBlock: [64] bool
        var maxX, maxY = 0_u32

        // The greater-than-one context set carries over between the sub-blocks of one block,
        // clause 9.3.4.2.6.
        var anySubBlockCoded     = false
        var previousGreater1Ctx  = 0_u32
        var previousGreater1Flag = false

        var subBlock = cast(s32, lastSubBlock)
        while subBlock >= 0
        {
            let index = cast(u32, subBlock)
            let xS    = cast(u32, ScanX[subBlockLog2, scanIdx, index])
            let yS    = cast(u32, ScanY[subBlockLog2, scanIdx, index])

            var inferDcSignificant = false
            var coded = true
            if index < lastSubBlock and index > 0
            {
                coded = .cabac.decision(CtxCodedSubBlockFlag + .codedSubBlockContext(&codedSubBlock[0], xS, yS, subBlockLog2, component)) != 0
                inferDcSignificant = true
            }

            codedSubBlock[yS * 8 + xS] = coded
            if not coded
            {
                subBlock -= 1
                continue
            }

            // A bit at the scan position marks each coefficient that needs a level.
            let isLast      = index == lastSubBlock
            var significant = isLast ? 1_u32 << lastScanPos : 0_u32
            let first       = isLast ? cast(s32, lastScanPos) - 1 : 15_s32

            // The whole sub-block shares its context but for the position inside it, and the
            // first coefficient of the block is the one exception the clause carves out.
            var pattern = 0_u32
            var base    = 0_u32
            let mapped  = log2TrafoSize == 2
            let dcBlock = not xS and not yS and not mapped
            if not mapped
            {
                base = .significanceContextBase(&codedSubBlock[0], xS, yS, scanIdx, log2TrafoSize, subBlockLog2, component, &pattern)
            }

            let dcContext = component == 0 ? 0_u32 : 27_u32

            var position = first
            while position > 0
            {
                let scanPos = cast(u32, position)
                let inner   = (cast(u32, ScanY[2, scanIdx, scanPos]) << 2) + cast(u32, ScanX[2, scanIdx, scanPos])
                let context = mapped ? cast(u32, SigCtxMap4x4[inner]) + dcContext : cast(u32, SigCtxPattern[pattern, inner]) + base
                significant |= .cabac.decision(CtxSigCoeffFlag + context) << scanPos
                position    -= 1
            }

            if first >= 0
            {
                let context = mapped ? cast(u32, SigCtxMap4x4[0]) + dcContext :
                              dcBlock ? dcContext : cast(u32, SigCtxPattern[pattern, 0]) + base
                if inferDcSignificant and not significant
                {
                    significant = 1
                }
                else
                {
                    significant |= .cabac.decision(CtxSigCoeffFlag + context)
                }
            }

            if not significant
            {
                subBlock -= 1
                continue
            }

            // Only the first eight significant coefficients have greater-than-one flags.
            let significantCount = Swag.countOnes(significant)
            let firstSigScanPos  = Swag.trailingZeros(significant)
            let lastSigScanPos   = 31 - Swag.leadingZeros(significant)
            var ctxSet           = (index == 0 or component > 0) ? 0_u32 : 2_u32
            var lastCtx          = 1_u32
            if anySubBlockCoded
            {
                lastCtx = previousGreater1Ctx
                if lastCtx > 0
                {
                    lastCtx = previousGreater1Flag ? 0 : lastCtx + 1
                }
            }

            if not lastCtx
            {
                ctxSet += 1
            }

            let contextBase   = CtxCoeffAbsLevelGreater1Flag + ctxSet * 4 + (component > 0 ? 16_u32 : 0_u32)
            var greater1Ctx   = 1_u32
            var greater1Flag  = false
            var greater1      = 0_u32
            var firstGreater1 = 0_u32
            var pending       = significant
            for order in Math.min(significantCount, 8_u32)
            {
                let scanPos = 31 - Swag.leadingZeros(pending)
                let bit     = 1_u32 << scanPos
                pending ^= bit
                if order and greater1Ctx > 0
                {
                    greater1Ctx = greater1Flag ? 0 : greater1Ctx + 1
                }

                greater1Flag = .cabac.decision(contextBase + Math.min(3_u32, greater1Ctx)) != 0
                if greater1Flag
                {
                    if not greater1
                    {
                        firstGreater1 = bit
                    }

                    greater1 |= bit
                }
            }

            previousGreater1Ctx  = greater1Ctx
            previousGreater1Flag = greater1Flag
            anySubBlockCoded     = true

            var greater2 = false
            if firstGreater1
            {
                let context = ctxSet + (component > 0 ? 4_u32 : 0_u32)
                greater2 = .cabac.decision(CtxCoeffAbsLevelGreater2Flag + context) != 0
            }

            // A hidden sign belongs to the lowest scan position, so it removes the final bin.
            let signHidden = pps.signDataHiding and not bypass and lastSigScanPos - firstSigScanPos > 3
            var signIndex  = significantCount - (signHidden ? 1_u32 : 0_u32)
            let signs      = .cabac.bypassBits(signIndex)

            // Decode the remaining magnitudes and write only the significant positions.
            var numSigCoeff    = 0_u32
            var sumAbsLevel    = 0_u32
            var riceParam      = 0_u32
            var lastAbsLevel   = 0_u32
            var firstRemaining = true

            pending = significant
            while pending
            {
                let scanPos = 31 - Swag.leadingZeros(pending)
                let bit     = 1_u32 << scanPos
                pending ^= bit

                let isFirstGreater1 = bit == firstGreater1
                var baseLevel       = 1_u32
                if greater1 & bit
                {
                    baseLevel += 1
                }

                if isFirstGreater1 and greater2
                {
                    baseLevel += 1
                }

                var threshold = 1_u32
                if numSigCoeff < 8
                {
                    threshold = 2
                    if isFirstGreater1
                    {
                        threshold = 3
                    }
                }

                var level = baseLevel
                if baseLevel == threshold
                {
                    if not firstRemaining
                    {
                        riceParam = Math.min(riceParam + (lastAbsLevel > 3 * (1_u32 << riceParam) ? 1_u32 : 0_u32), 4)
                    }

                    let remaining = .readCoeffAbsLevelRemaining(riceParam)
                    level          = baseLevel + remaining
                    lastAbsLevel   = level
                    firstRemaining = false
                }

                if signHidden
                {
                    sumAbsLevel += level
                }

                var sign = false
                if signHidden and not pending
                {
                    sign = (sumAbsLevel & 1) != 0
                }
                else
                {
                    signIndex -= 1
                    sign      = ((signs >> signIndex) & 1) != 0
                }

                let xC    = (xS << 2) + cast(u32, ScanX[2, scanIdx, scanPos])
                let yC    = (yS << 2) + cast(u32, ScanY[2, scanIdx, scanPos])
                let value = cast(s32, Math.min(level, 32767_u32))
                .coefficients[yC * size + xC] = cast(s16, (sign ? -value : value))
                .coefficientRows[xC] |= 1_u32 << yC
                .coefficientColumns  |= 1_u32 << xC
                maxX                 = Math.max(maxX, xC)
                maxY                 = Math.max(maxY, yC)
                numSigCoeff          += 1
            }

            subBlock -= 1
        }

        if .cabac.hasOverrun()
        {
            fail InvalidFormatError{"HEVC residual data runs past the end of its slice segment"}
        }

        result.lastX = maxX
        result.lastY = maxY
        return result
    }

    // Reads the prefix of one last-significant-coefficient position, clause 9.3.4.2.3.
    private mtd readLastPrefix(component, log2TrafoSize, contextBase: u32)->u32
    {
        var offset, shift: u32
        if not component
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
        var prefix  = 0_u32
        while prefix < maximum
        {
            if .cabac.decision(contextBase + (prefix >> shift) + offset) == 0
            {
                break
            }

            prefix += 1
        }

        return prefix
    }

    // Turns one last-significant-coefficient prefix into a position, equations 7-75 and 7-77.
    private mtd readLastSuffix(prefix: u32)->u32
    {
        let bits = (prefix >> 1) - 1
        return (1_u32 << bits) * (2 + (prefix & 1)) + .cabac.bypassBits(bits)
    }

    // Reads one `coeff_abs_level_remaining`, clause 9.3.3.11.
    private mtd readCoeffAbsLevelRemaining(riceParam: u32)->u32
    {
        var prefix = 0_u32
        while prefix < 4 and .cabac.bypass() != 0
        {
            prefix += 1
        }

        if prefix < 4
        {
            return (prefix << riceParam) + .cabac.bypassBits(riceParam)
        }

        // Past the truncated Rice prefix the value continues as an Exp-Golomb code of order one
        // above the Rice parameter, equation 9-13.
        var extension = 0_u32
        while extension < 24 and .cabac.bypass() != 0
        {
            extension += 1
        }

        let order  = riceParam + 1
        let escape = ((1_u32 << extension) - 1) << order
        return (4_u32 << riceParam) + escape + .cabac.bypassBits(order + extension)
    }

    // Returns the context of one `coded_sub_block_flag`, clause 9.3.4.2.4.
    private mtd const codedSubBlockContext(coded: const [*] bool, xS, yS, subBlockLog2, component: u32)->u32
    {
        let limit   = (1_u32 << subBlockLog2) - 1
        var context = 0_u32
        if xS < limit and coded[yS * 8 + xS + 1]
        {
            context += 1
        }

        if yS < limit and coded[(yS + 1) * 8 + xS]
        {
            context += 1
        }

        context = Math.min(context, 1)
        return component == 0 ? context : 2 + context
    }

    // Returns what every `sig_coeff_flag` of one sub-block shares, clause 9.3.4.2.5.
    //
    // Only the position inside the sub-block varies from one coefficient to the next: which
    // neighbouring sub-blocks are coded selects one of four patterns, and everything else adds a
    // constant. Both are answered once here, and a coefficient then reads one byte and adds it.
    private mtd const significanceContextBase(coded: const [*] bool, xS, yS, scanIdx, log2TrafoSize, subBlockLog2, component: u32, pattern: *u32)->u32
    {
        let limit    = (1_u32 << subBlockLog2) - 1
        var previous = 0_u32
        if xS < limit and coded[yS * 8 + xS + 1]
        {
            previous += 1
        }

        if yS < limit and coded[(yS + 1) * 8 + xS]
        {
            previous += 2
        }

        pattern[] = previous

        var base = component == 0 ? 0_u32 : 27_u32
        if not component
        {
            if xS + yS > 0
            {
                base += 3
            }

            if log2TrafoSize == 3
            {
                if scanIdx == ScanDiagonal
                {
                    base += 9
                }
                else
                {
                    base += 15
                }
            }
            else
            {
                base += 21
            }
        }
        else
        {
            base += log2TrafoSize == 3 ? 9_u32 : 12_u32
        }

        return base
    }
}
