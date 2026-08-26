//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns coding tree and coding unit syntax, prediction units, and the residual quadtree.
//
#global namespace Hevc
#global internal

using Core, Core.Errors

// Table 8-2: the three directional modes a chroma block may take instead of the luma one, plus
// the diagonal it falls back to when the chosen one is already the luma mode.
const ChromaModeCandidates: [4] u8 = [IntraPlanar, 26, 10, IntraDc]
const IntraAngular34               = 34'u8

impl Decoder
{
    // Decodes one coding tree unit, clause 7.3.8.2.
    mtd codingTreeUnit() fail
    {
        let sps  = .activeSps!
        let xCtb = cast(s32) ((.ctbAddrRs % sps.widthInCtbs) << sps.ctbLog2Size)
        let yCtb = cast(s32) ((.ctbAddrRs / sps.widthInCtbs) << sps.ctbLog2Size)

        if .header.saoLuma or .header.saoChroma do
            try .readSaoParameters(xCtb >> sps.ctbLog2Size, yCtb >> sps.ctbLog2Size)

        try .codingQuadtree(xCtb, yCtb, sps.ctbLog2Size, 0)
    }

    // Walks the coding quadtree of one coding tree block, clause 7.3.8.4.
    mtd codingQuadtree(x0, y0: s32, log2CbSize, depth: u32) fail
    {
        let sps  = .activeSps!
        let pps  = .activePps!
        let size = 1's32 << log2CbSize

        var split = log2CbSize > sps.minCbLog2Size
        if x0 + size <= cast(s32) sps.width and y0 + size <= cast(s32) sps.height and log2CbSize > sps.minCbLog2Size
        {
            var context = 0'u32
            if .isAvailable(x0, y0, x0 - 1, y0) and cast(u32) .ctDepth[.blockIndex(x0 - 1, y0)] > depth do
                context += 1
            if .isAvailable(x0, y0, x0, y0 - 1) and cast(u32) .ctDepth[.blockIndex(x0, y0 - 1)] > depth do
                context += 1
            split = .cabac.decision(CtxSplitCuFlag + context) != 0
        }

        // A quantization group is the unit one delta may be sent for, clause 7.4.9.4.
        if pps.cuQpDeltaEnabled and log2CbSize >= sps.ctbLog2Size - pps.diffCuQpDeltaDepth
        {
            .isCuQpDeltaCoded = false
            .cuQpDeltaVal     = 0
            .beginQuantizationGroup(x0, y0)
        }

        if !split
        {
            try .codingUnit(x0, y0, log2CbSize, depth)
            return
        }

        let half = size >> 1
        try .codingQuadtree(x0, y0, log2CbSize - 1, depth + 1)
        if x0 + half < cast(s32) sps.width do
            try .codingQuadtree(x0 + half, y0, log2CbSize - 1, depth + 1)
        if y0 + half < cast(s32) sps.height do
            try .codingQuadtree(x0, y0 + half, log2CbSize - 1, depth + 1)
        if x0 + half < cast(s32) sps.width and y0 + half < cast(s32) sps.height do
            try .codingQuadtree(x0 + half, y0 + half, log2CbSize - 1, depth + 1)
    }

    // Decodes one coding unit, clause 7.3.8.5.
    mtd codingUnit(x0, y0: s32, log2CbSize, depth: u32) fail
    {
        let sps    = .activeSps!
        let pps    = .activePps!
        let header = &.header
        let nCbS   = 1's32 << log2CbSize

        var bypass = false
        if pps.transquantBypassEnabled do
            bypass = .cabac.decision(CtxCuTransquantBypassFlag) != 0

        var skip = false
        if header.sliceType != SliceTypeI
        {
            var context = 0'u32
            if .isAvailable(x0, y0, x0 - 1, y0) and .skipFlag[.blockIndex(x0 - 1, y0)] != 0 do
                context += 1
            if .isAvailable(x0, y0, x0, y0 - 1) and .skipFlag[.blockIndex(x0, y0 - 1)] != 0 do
                context += 1
            skip = .cabac.decision(CtxCuSkipFlag + context) != 0
        }

        .fillBlocks(.ctDepth.buffer!, x0, y0, nCbS, cast(u8) depth)
        .fillBlocks(.skipFlag.buffer!, x0, y0, nCbS, skip ? 1'u8 : 0'u8)

        // A coding block boundary is a transform block boundary and a prediction block boundary
        // whatever the unit turns out to hold, clauses 8.7.2.2 and 8.7.2.3. A unit that codes no
        // residual never reaches the transform tree, so the mark belongs here.
        .markEdges(x0, y0, nCbS, nCbS, EdgeTransformLeft | EdgePredictionLeft, EdgeTransformTop | EdgePredictionTop)

        if skip
        {
            .fillBlocks(.predMode.buffer!, x0, y0, nCbS, ModeSkip)
            .fillBlocks(.intraModeY.buffer!, x0, y0, nCbS, IntraDc)
            var mergeIdx = 0'u32
            if header.maxNumMergeCand > 1 do
                mergeIdx = .readMergeIdx()
            let motion = .deriveMergeMotion(x0, y0, nCbS, x0, y0, nCbS, nCbS, 0, Part2Nx2N, mergeIdx)
            .storeMotion(x0, y0, nCbS, nCbS, &motion)
            .interPredict(x0, y0, nCbS, nCbS, &motion)
            .finishCodingUnit(x0, y0, nCbS, hasResidual: false)
            return
        }

        var isIntra = header.sliceType == SliceTypeI
        if header.sliceType != SliceTypeI do
            isIntra = .cabac.decision(CtxPredModeFlag) != 0

        var partMode = Part2Nx2N
        if !isIntra or log2CbSize == sps.minCbLog2Size do
            partMode = .readPartMode(isIntra, log2CbSize, sps)

        .fillBlocks(.predMode.buffer!, x0, y0, nCbS, isIntra ? ModeIntra : ModeInter)

        if isIntra
        {
            if partMode == PartNxN and log2CbSize != sps.minCbLog2Size do
                fail InvalidFormatError{"HEVC intra coding unit splits a block that may not be split"}
            try .intraCodingUnit(x0, y0, log2CbSize, partMode, bypass)
            return
        }

        try .interCodingUnit(x0, y0, log2CbSize, partMode, bypass)
    }

    // Decodes the prediction and residual of an intra coding unit.
    private mtd intraCodingUnit(x0, y0: s32, log2CbSize, partMode: u32, bypass: bool) fail
    {
        let sps  = .activeSps!
        let nCbS = 1's32 << log2CbSize

        // The four blocks of a split unit each state their own mode; a whole unit states one.
        let split  = partMode == PartNxN
        let blocks = split ? 2'u32 : 1'u32
        let pbSize = split ? nCbS >> 1 : nCbS

        var previousFlag: [4] bool
        var candidate:    [4] u32
        for j in blocks
        {
            for i in blocks do
                previousFlag[j * 2 + i] = .cabac.decision(CtxPrevIntraLumaPredFlag) != 0
        }

        for j in blocks
        {
            for i in blocks
            {
                let slot = j * 2 + i
                if previousFlag[slot]
                {
                    // Truncated Rice with a maximum of two, whose bins after the first bypass.
                    var index = 0'u32
                    if .cabac.bypass() != 0
                    {
                        index = 1
                        if .cabac.bypass() != 0 do
                            index = 2
                    }

                    candidate[slot] = index
                }
                else
                {
                    candidate[slot] = 32 + .cabac.bypassBits(5)
                }
            }
        }

        var modes: [4] u8
        for j in blocks
        {
            for i in blocks
            {
                let slot = j * 2 + i
                let x    = x0 + cast(s32) i * pbSize
                let y    = y0 + cast(s32) j * pbSize
                modes[slot] = .deriveIntraLumaMode(x, y, candidate[slot])
                .fillBlocks(.intraModeY.buffer!, x, y, pbSize, modes[slot])
            }
        }

        // One chroma mode covers the whole unit in every layout this decoder reads.
        var chromaCode = 4'u32
        if .cabac.decision(CtxIntraChromaPredMode) != 0
        {
            chromaCode = .cabac.bypassBits(2)
        }

        var chromaMode = modes[0]
        if chromaCode != 4
        {
            chromaMode = ChromaModeCandidates[chromaCode]
            if chromaMode == modes[0] do
                chromaMode = IntraAngular34
        }

        let maxDepth = sps.maxTrafoDepthIntra + (split ? 1'u32 : 0'u32)
        try .transformTree(x0, y0, x0, y0, log2CbSize, 0, 0, parentCbfCb: false, parentCbfCr: false, maxTrafoDepth: maxDepth, isIntra: true, intraSplit: split, bypass: bypass, partMode: partMode, chromaMode: chromaMode)
        .finishCodingUnit(x0, y0, nCbS, hasResidual: true)
    }

    // Derives one luma intra prediction mode from its neighbours, clause 8.4.2.
    private mtd deriveIntraLumaMode(x, y: s32, code: u32)->u8
    {
        let sps = .activeSps!

        var candidateA = IntraDc
        if .isAvailable(x, y, x - 1, y) and .predMode[.blockIndex(x - 1, y)] == ModeIntra do
            candidateA = .intraModeY[.blockIndex(x - 1, y)]

        var candidateB = IntraDc
        if .isAvailable(x, y, x, y - 1) and .predMode[.blockIndex(x, y - 1)] == ModeIntra
        {
            // A block above the coding tree block row would have to be kept for a whole picture
            // row, so the standard refuses it rather than storing it.
            if (y - 1) >= ((y >> sps.ctbLog2Size) << sps.ctbLog2Size) do
                candidateB = .intraModeY[.blockIndex(x, y - 1)]
        }

        var most: [3] u8
        if candidateA == candidateB
        {
            if candidateA < 2
            {
                most[0] = IntraPlanar
                most[1] = IntraDc
                most[2] = IntraAngular26
            }
            else
            {
                most[0] = candidateA
                most[1] = cast(u8) (2 + ((cast(u32) candidateA + 29) % 32))
                most[2] = cast(u8) (2 + ((cast(u32) candidateA - 2 + 1) % 32))
            }
        }
        else
        {
            most[0] = candidateA
            most[1] = candidateB
            if candidateA != IntraPlanar and candidateB != IntraPlanar do
                most[2] = IntraPlanar
            elif candidateA != IntraDc and candidateB != IntraDc do
                most[2] = IntraDc
            else do
                most[2] = IntraAngular26
        }

        if code < 32 do
            return most[code]

        // The remaining mode is stated as an index into the modes the three candidates leave.
        var sorted = most
        for outer in 3'u32
        {
            for inner in outer + 1 until 3'u32
            {
                if sorted[inner] < sorted[outer]
                {
                    let swap = sorted[outer]
                    sorted[outer] = sorted[inner]
                    sorted[inner] = swap
                }
            }
        }

        var mode = cast(u8) (code - 32)
        for index in 3'u32
        {
            if mode >= sorted[index] do
                mode += 1
        }

        return mode
    }

    // Decodes the prediction and residual of an inter coding unit.
    private mtd interCodingUnit(x0, y0: s32, log2CbSize, partMode: u32, bypass: bool) fail
    {
        let sps     = .activeSps!
        let nCbS    = 1's32 << log2CbSize
        let half    = nCbS >> 1
        let quarter = nCbS >> 2

        .fillBlocks(.intraModeY.buffer!, x0, y0, nCbS, IntraDc)

        var merge2Nx2N = false
        switch partMode
        {
        case Part2Nx2N:
            merge2Nx2N = try .predictionUnit(x0, y0, nCbS, x0, y0, nCbS, nCbS, 0, partMode)

        case Part2NxN:
            discard try .predictionUnit(x0, y0, nCbS, x0, y0, nCbS, half, 0, partMode)
            discard try .predictionUnit(x0, y0, nCbS, x0, y0 + half, nCbS, half, 1, partMode)

        case PartNx2N:
            discard try .predictionUnit(x0, y0, nCbS, x0, y0, half, nCbS, 0, partMode)
            discard try .predictionUnit(x0, y0, nCbS, x0 + half, y0, half, nCbS, 1, partMode)

        case Part2NxnU:
            discard try .predictionUnit(x0, y0, nCbS, x0, y0, nCbS, quarter, 0, partMode)
            discard try .predictionUnit(x0, y0, nCbS, x0, y0 + quarter, nCbS, nCbS - quarter, 1, partMode)

        case Part2NxnD:
            discard try .predictionUnit(x0, y0, nCbS, x0, y0, nCbS, nCbS - quarter, 0, partMode)
            discard try .predictionUnit(x0, y0, nCbS, x0, y0 + nCbS - quarter, nCbS, quarter, 1, partMode)

        case PartnLx2N:
            discard try .predictionUnit(x0, y0, nCbS, x0, y0, quarter, nCbS, 0, partMode)
            discard try .predictionUnit(x0, y0, nCbS, x0 + quarter, y0, nCbS - quarter, nCbS, 1, partMode)

        case PartnRx2N:
            discard try .predictionUnit(x0, y0, nCbS, x0, y0, nCbS - quarter, nCbS, 0, partMode)
            discard try .predictionUnit(x0, y0, nCbS, x0 + nCbS - quarter, y0, quarter, nCbS, 1, partMode)

        default:
            discard try .predictionUnit(x0, y0, nCbS, x0, y0, half, half, 0, partMode)
            discard try .predictionUnit(x0, y0, nCbS, x0 + half, y0, half, half, 1, partMode)
            discard try .predictionUnit(x0, y0, nCbS, x0, y0 + half, half, half, 2, partMode)
            discard try .predictionUnit(x0, y0, nCbS, x0 + half, y0 + half, half, half, 3, partMode)
        }

        // A whole unit taken from a merge candidate carries its residual flag implicitly.
        var hasResidual = true
        if !(partMode == Part2Nx2N and merge2Nx2N) do
            hasResidual = .cabac.decision(CtxRqtRootCbf) != 0

        if hasResidual
        {
            // The depth an inter unit may reach is the one the sequence states, and nothing else:
            // the forced first split of clause 7.4.9.8 is an inferred flag, not an extra depth.
            // Granting it a depth here makes the tree read a `split_transform_flag` the encoder
            // never wrote, and every bin after it is then read against the wrong syntax.
            try .transformTree(x0, y0, x0, y0, log2CbSize, 0, 0, parentCbfCb: false, parentCbfCr: false, maxTrafoDepth: sps.maxTrafoDepthInter, isIntra: false, intraSplit: false, bypass: bypass, partMode: partMode, chromaMode: IntraDc)
        }

        .finishCodingUnit(x0, y0, nCbS, hasResidual)
    }

    // Decodes one prediction unit and predicts its samples, clause 7.3.8.6.
    //
    // Returns whether the unit took its motion from a merge candidate, which is what decides
    // whether the coding unit still states a residual flag.
    private mtd predictionUnit(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH: s32, partIdx, partMode: u32)->bool fail
    {
        let header = &.header

        let merge = .cabac.decision(CtxMergeFlag) != 0
        if merge
        {
            var mergeIdx = 0'u32
            if header.maxNumMergeCand > 1 do
                mergeIdx = .readMergeIdx()
            let motion = .deriveMergeMotion(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH, partIdx, partMode, mergeIdx)
            .storeMotion(xPb, yPb, nPbW, nPbH, &motion)
            .markEdges(xPb, yPb, nPbW, nPbH, EdgePredictionLeft, EdgePredictionTop)
            .interPredict(xPb, yPb, nPbW, nPbH, &motion)
            return true
        }

        var motion: PuMotion

        // Which lists the block predicts from, Table 9-47.
        var predFlags = 1'u8
        if header.sliceType == SliceTypeB
        {
            if nPbW + nPbH != 12
            {
                let depth = cast(u32) .ctDepth[.blockIndex(xPb, yPb)]
                if .cabac.decision(CtxInterPredIdc + depth) != 0
                {
                    predFlags = 3
                }
                else
                {
                    predFlags = .cabac.decision(CtxInterPredIdc + 4) != 0 ? 2'u8 : 1'u8
                }
            }
            else
            {
                predFlags = .cabac.decision(CtxInterPredIdc + 4) != 0 ? 2'u8 : 1'u8
            }
        }

        motion.predFlags = predFlags
        for list in ListCount
        {
            if (cast(u32) predFlags & (1'u32 << list)) == 0
            {
                motion.refIdx[list] = -1
                continue
            }

            var refIdx = 0'u32
            if header.numRefIdx[list] > 1 do
                refIdx = .readRefIdx(header.numRefIdx[list])
            if refIdx >= header.numRefIdx[list] do
                fail InvalidFormatError{"HEVC prediction unit selects a reference past the end of its list"}
            motion.refIdx[list] = cast(s8) refIdx

            var difference: [2] s32
            if list == 1 and header.mvdL1Zero and predFlags == 3
            {
                difference[0] = 0
                difference[1] = 0
            }
            else
            {
                difference = .readMotionDifference()
            }

            let mvpFlag   = .cabac.decision(CtxMvpFlag)
            let predictor = .derivePredictor(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH, partIdx, list, cast(s32) refIdx, mvpFlag)

            // The sum wraps in sixteen bits, clause 8-133.
            for component in 2'u32
            {
                let sum = (cast(s32) predictor[component] + difference[component] + 65536) & 0xFFFF
                motion.mv[list, component] = cast(s16) (sum >= 32768 ? sum - 65536 : sum)
            }
        }

        .storeMotion(xPb, yPb, nPbW, nPbH, &motion)
        .markEdges(xPb, yPb, nPbW, nPbH, EdgePredictionLeft, EdgePredictionTop)
        .interPredict(xPb, yPb, nPbW, nPbH, &motion)
        return false
    }

    // Reads one merge index, clause 9.3.3.2 with a truncated Rice binarization.
    private mtd readMergeIdx()->u32
    {
        if .cabac.decision(CtxMergeIdx) == 0 do
            return 0
        var index = 1'u32
        while index + 1 < .header.maxNumMergeCand and .cabac.bypass() != 0 do
            index += 1
        return index
    }

    // Reads one reference index, whose first two bins carry a context.
    private mtd readRefIdx(count: u32)->u32
    {
        if .cabac.decision(CtxRefIdx) == 0 do
            return 0
        if count == 2 do
            return 1
        if .cabac.decision(CtxRefIdx + 1) == 0 do
            return 1

        var index = 2'u32
        while index + 1 < count and .cabac.bypass() != 0 do
            index += 1
        return index
    }

    // Reads one motion vector difference, clause 7.3.8.9.
    private mtd readMotionDifference()->[2] s32
    {
        var greater0, greater1: [2] bool
        for component in 2'u32 do
            greater0[component] = .cabac.decision(CtxAbsMvdGreater0Flag) != 0
        for component in 2'u32
        {
            if greater0[component] do
                greater1[component] = .cabac.decision(CtxAbsMvdGreater1Flag) != 0
        }

        var result: retval
        for component in 2'u32
        {
            if !greater0[component] do
                continue

            var magnitude = 1'u32
            if greater1[component] do
                magnitude = 2 + .readExpGolomb(1)
            let negative = .cabac.bypass() != 0
            result[component] = negative ? -cast(s32) magnitude : cast(s32) magnitude
        }

        return result
    }

    // Reads one bypass-coded Exp-Golomb value of order `order`, clause 9.3.3.3.
    private mtd readExpGolomb(order: u32)->u32
    {
        var length = 0'u32
        while length < 24 and .cabac.bypass() != 0 do
            length += 1
        let escape = ((1'u32 << length) - 1) << order
        return escape + .cabac.bypassBits(order + length)
    }

    // Reads one partition mode, clause 9.3.3.7.
    private mtd readPartMode(isIntra: bool, log2CbSize: u32, sps: const *Sps)->u32
    {
        if .cabac.decision(CtxPartMode) != 0 do
            return Part2Nx2N
        if isIntra do
            return PartNxN

        let smallest   = log2CbSize == sps.minCbLog2Size
        let horizontal = .cabac.decision(CtxPartMode + 1) != 0

        if !smallest
        {
            if !sps.ampEnabled do
                return horizontal ? Part2NxN : PartNx2N
            if .cabac.decision(CtxPartMode + 3) != 0 do
                return horizontal ? Part2NxN : PartNx2N
            let second = .cabac.bypass() != 0
            if horizontal do
                return second ? Part2NxnD : Part2NxnU
            return second ? PartnRx2N : PartnLx2N
        }

        if horizontal do
            return Part2NxN
        if log2CbSize == 3 do
            return PartNx2N
        return .cabac.decision(CtxPartMode + 2) != 0 ? PartNx2N : PartNxN
    }

    // Records the quantization parameter of a finished coding unit over the blocks it covers.
    private mtd finishCodingUnit(x0, y0, nCbS: s32, hasResidual: bool)
    {
        discard hasResidual

        let blocks = cast(u32) nCbS >> MinBlockLog2
        let origin = .blockIndex(x0, y0)
        for row in blocks
        {
            let line = origin + cast(u64) row * cast(u64) .gridWidth
            for column in blocks do
                .qpY[line + cast(u64) column] = cast(s8) .currentQp
        }

        .qpYPrev = .currentQp
    }

    // Walks the residual quadtree of one coding unit, clause 7.3.8.8.
    mtd transformTree(x0, y0, xBase, yBase: s32, log2TrafoSize, trafoDepth, blkIdx: u32, parentCbfCb, parentCbfCr: bool, maxTrafoDepth: u32, isIntra, intraSplit, bypass: bool, partMode: u32, chromaMode: u8) fail
    {
        let sps = .activeSps!

        var split = false
        if log2TrafoSize <= sps.maxTbLog2Size and log2TrafoSize > sps.minTbLog2Size and trafoDepth < maxTrafoDepth and !(intraSplit and !trafoDepth)
        {
            split = .cabac.decision(CtxSplitTransformFlag + 5 - log2TrafoSize) != 0
        }
        else
        {
            // Clause 7.4.9.8: a block larger than the largest transform, or the first depth of a
            // split intra unit, splits without saying so.
            let interSplit = !isIntra and sps.maxTrafoDepthInter == 0 and partMode != Part2Nx2N and !trafoDepth
            split = log2TrafoSize > sps.maxTbLog2Size or (intraSplit and !trafoDepth) or interSplit
        }

        // The chroma coded-block flags of a block that still covers a chroma block of its own.
        var cbfCb = parentCbfCb
        var cbfCr = parentCbfCr
        if log2TrafoSize > 2
        {
            cbfCb = false
            cbfCr = false
            if !trafoDepth or parentCbfCb do
                cbfCb = .cabac.decision(CtxCbfChroma + trafoDepth) != 0
            if !trafoDepth or parentCbfCr do
                cbfCr = .cabac.decision(CtxCbfChroma + trafoDepth) != 0
        }

        if split
        {
            let half = 1's32 << (log2TrafoSize - 1)
            try .transformTree(x0, y0, x0, y0, log2TrafoSize - 1, trafoDepth + 1, 0, cbfCb, cbfCr, maxTrafoDepth, isIntra, intraSplit, bypass, partMode, chromaMode)
            try .transformTree(x0 + half, y0, x0, y0, log2TrafoSize - 1, trafoDepth + 1, 1, cbfCb, cbfCr, maxTrafoDepth, isIntra, intraSplit, bypass, partMode, chromaMode)
            try .transformTree(x0, y0 + half, x0, y0, log2TrafoSize - 1, trafoDepth + 1, 2, cbfCb, cbfCr, maxTrafoDepth, isIntra, intraSplit, bypass, partMode, chromaMode)
            try .transformTree(x0 + half, y0 + half, x0, y0, log2TrafoSize - 1, trafoDepth + 1, 3, cbfCb, cbfCr, maxTrafoDepth, isIntra, intraSplit, bypass, partMode, chromaMode)
            return
        }

        var cbfLuma = true
        if isIntra or trafoDepth != 0 or cbfCb or cbfCr do
            cbfLuma = .cabac.decision(CtxCbfLuma + (trafoDepth == 0 ? 1'u32 : 0'u32)) != 0

        try .transformUnit(x0, y0, xBase, yBase, log2TrafoSize, trafoDepth, blkIdx, cbfLuma, cbfCb, cbfCr, isIntra, bypass, chromaMode)
    }

    // Decodes one transform unit and reconstructs its samples, clause 7.3.8.10.
    mtd transformUnit(x0, y0, xBase, yBase: s32, log2TrafoSize, trafoDepth, blkIdx: u32, cbfLuma, cbfCb, cbfCr, isIntra, bypass: bool, chromaMode: u8) fail
    {
        let sps  = .activeSps!
        let pps  = .activePps!
        let size = 1's32 << log2TrafoSize

        // A 4x4 luma block shares one chroma block with its three siblings, so the chroma of the
        // group is decoded once, with the last of them.
        let smallest       = log2TrafoSize == 2
        let log2ChromaSize = smallest ? 2'u32 : log2TrafoSize - 1
        let xChroma        = smallest ? xBase : x0
        let yChroma        = smallest ? yBase : y0
        let hasChroma      = !smallest or blkIdx == 3

        if cbfLuma or cbfCb or cbfCr
        {
            if pps.cuQpDeltaEnabled and !.isCuQpDeltaCoded do
                .readQuantizationDelta()
        }

        .cbfLumaAt(x0, y0, size, cbfLuma)
        .markEdges(x0, y0, size, size, EdgeTransformLeft, EdgeTransformTop)

        // Luma.
        var block: TransformBlock
        block.x         = x0
        block.y         = y0
        block.size      = cast(u32) size
        block.log2Size  = log2TrafoSize
        block.component = 0
        block.isIntra   = isIntra
        block.bypass    = bypass
        block.qp        = .currentQp + sps.qpBdOffsetY

        let lumaMode = cast(u32) .intraModeY[.blockIndex(x0, y0)]
        if isIntra do
            .intraPredict(x0, y0, x0, y0, log2TrafoSize, 0, lumaMode)

        if cbfLuma
        {
            let read = try .residualCoding(x0, y0, log2TrafoSize, 0, lumaMode, isIntra, bypass)
            block.transformSkip = read.transformSkip
            block.lastX         = read.lastX
            block.lastY         = read.lastY
            .reconstructResidual(&block)
        }

        if isIntra do
            .addResidual(&block, cbfLuma)
        elif cbfLuma do
            .addResidualInPlace(&block)

        if !hasChroma do
            return

        // Chroma, in its own sample grid.
        let chromaSize = 1's32 << log2ChromaSize
        for component in 1 to 2'u32
        {
            let coded = component == 1 ? cbfCb : cbfCr
            var chroma: TransformBlock
            chroma.x         = xChroma
            chroma.y         = yChroma
            chroma.size      = cast(u32) chromaSize
            chroma.log2Size  = log2ChromaSize
            chroma.component = component
            chroma.isIntra   = isIntra
            chroma.bypass    = bypass
            chroma.qp        = .chromaQp(component) + sps.qpBdOffsetC

            if isIntra do
                .intraPredict(xChroma / 2, yChroma / 2, xChroma, yChroma, log2ChromaSize, component, cast(u32) chromaMode)

            if coded
            {
                let read = try .residualCoding(xChroma, yChroma, log2ChromaSize, component, cast(u32) chromaMode, isIntra, bypass)
                chroma.transformSkip = read.transformSkip
                chroma.lastX         = read.lastX
                chroma.lastY         = read.lastY
                .reconstructResidual(&chroma)
            }

            if isIntra do
                .addResidual(&chroma, coded)
            elif coded do
                .addResidualInPlace(&chroma)
        }
    }

    // Reads one quantization parameter delta, clause 7.3.8.12.
    private mtd readQuantizationDelta()
    {
        .isCuQpDeltaCoded = true

        var prefix = 0'u32
        while prefix < 5 and .cabac.decision(CtxCuQpDeltaAbs + (prefix ? 1'u32 : 0'u32)) != 0 do
            prefix += 1

        var magnitude = prefix
        if prefix > 4 do
            magnitude = 5 + .readExpGolomb(0)
        if magnitude != 0 and .cabac.bypass() != 0 do
            .cuQpDeltaVal = -cast(s32) magnitude
        else do
            .cuQpDeltaVal = cast(s32) magnitude

        .refreshQp()
    }

    // Records whether one transform block held luma coefficients, which the loop filter reads.
    private mtd cbfLumaAt(x0, y0, size: s32, coded: bool)
    {
        .fillBlocks(.cbfLuma.buffer!, x0, y0, size, coded ? 1'u8 : 0'u8)
    }

    // Writes one value over every four-sample block a square region covers.
    private mtd fillBlocks(grid: [*] u8, x0, y0, size: s32, value: u8)
    {
        let blocks = cast(u32) size >> MinBlockLog2
        let origin = .blockIndex(x0, y0)
        for row in blocks
        {
            let line = origin + cast(u64) row * cast(u64) .gridWidth
            for column in blocks do
                grid[line + cast(u64) column] = value
        }
    }
}
