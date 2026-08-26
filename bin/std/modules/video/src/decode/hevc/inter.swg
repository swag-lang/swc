//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns motion vector prediction, merge candidates, and inter prediction.
//
#global namespace Hevc
#global internal

using Core

// Table 8-8: the eight-tap luma interpolation filters, for the three quarter-sample positions.
const LumaFilter: [4, 8] s8 = [[0, 0, 0, 64, 0, 0, 0, 0], [-1, 4, -10, 58, 17, -5, 1, 0], [-1, 4, -11, 40, 40, -11, 4, -1], [0, 1, -5, 17, 58, -10, 4, -1]]

// Table 8-9: the four-tap chroma interpolation filters, for the seven eighth-sample positions.
const ChromaFilter: [8, 4] s8 = [[0, 64, 0, 0], [-2, 58, 10, -2], [-4, 54, 16, -2], [-6, 46, 28, -4], [-4, 36, 36, -4], [-4, 28, 46, -6], [-2, 16, 54, -4], [-2, 10, 58, -2]]

// Table 8-7: the candidate pairs a combined bi-predictive merge candidate is built from.
const CombinedCandL0: [12] u8 = [0, 1, 0, 2, 1, 2, 0, 3, 1, 3, 2, 3]
const CombinedCandL1: [12] u8 = [1, 0, 2, 0, 2, 1, 3, 0, 3, 1, 3, 2]

// The largest prediction block, plus the samples the eight-tap filter reads around it.
const MaxPredSide = 64'u32
const MaxRefSide  = MaxPredSide + 8

// One temporal motion vector candidate, clause 8.5.3.2.8.
struct TemporalMotion
{
    mv:        [2] s16
    available: bool
}

impl Decoder
{
    // Returns the motion of the four-sample block covering `(x, y)` in the current picture.
    #[Swag.Inline]
    mtd const motionAt(x, y: s32)->const *PuMotion => &.motion[.blockIndex(x, y)]

    // Reports whether no reference picture of either list follows the current one.
    //
    // A collocated candidate is taken from the current list rather than from the one the slice
    // names when nothing is predicted forward, clause 8.5.3.2.9.
    mtd const noBackwardPrediction()->bool
    {
        for list in ListCount
        {
            for index in .refList.count[list] where .refList.poc[list, index] > .pocValue do
                return false
        }

        return true
    }

    // Scales a motion vector between two picture distances, equations 8-179 to 8-183.
    private mtd const scaleMotion(value: s32, currentDiff, referenceDiff: s32)->s32
    {
        let td = Math.clamp(referenceDiff, -128, 127)
        let tb = Math.clamp(currentDiff, -128, 127)
        if !td do
            return value

        let tx     = (16384 + (Math.abs(td) >> 1)) / td
        let factor = Math.clamp((tb * tx + 32) >> 6, -4096, 4095)
        let scaled = factor * value
        let sign   = scaled < 0 ? -1's32 : 1's32
        return Math.clamp(sign * ((Math.abs(scaled) + 127) >> 8), -32768, 32767)
    }

    // Derives the motion of one merge-coded prediction block, clause 8.5.3.2.2.
    mtd deriveMergeMotion(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH: s32, partIdx, partMode, mergeIdx: u32)->PuMotion
    {
        let header = &.header
        let pps    = .activePps!

        // Every prediction block of a small coding unit shares one candidate list, so a decoder
        // can build the four of them in parallel, clause 8-110.
        var xP, yP, wP, hP    = 0's32
        var effectivePartIdx  = partIdx
        var effectivePartMode = partMode
        if pps.log2ParallelMergeLevel > 2 and nCbS == 8
        {
            xP                = xCb
            yP                = yCb
            wP                = nCbS
            hP                = nCbS
            effectivePartIdx  = 0
            effectivePartMode = Part2Nx2N
        }
        else
        {
            xP = xPb
            yP = yPb
            wP = nPbW
            hP = nPbH
        }

        var candidates: [5 + 1 + 12 + 16] PuMotion
        var count = 0'u32
        .gatherSpatialMergeCandidates(&candidates[0], &count, xCb, yCb, nCbS, xP, yP, wP, hP, effectivePartIdx, effectivePartMode)

        if header.temporalMvpEnabled
        {
            var temporal: PuMotion
            var available = false
            let l0        = .temporalMotion(xP, yP, wP, hP, 0, 0)
            if l0.available
            {
                temporal.mv[0, 0]  = l0.mv[0]
                temporal.mv[0, 1]  = l0.mv[1]
                temporal.refIdx[0] = 0
                temporal.predFlags |= 1
                available          = true
            }

            if header.sliceType == SliceTypeB
            {
                let l1 = .temporalMotion(xP, yP, wP, hP, 1, 0)
                if l1.available
                {
                    temporal.mv[1, 0]  = l1.mv[0]
                    temporal.mv[1, 1]  = l1.mv[1]
                    temporal.refIdx[1] = 0
                    temporal.predFlags |= 2
                    available          = true
                }
            }

            if available and count < header.maxNumMergeCand
            {
                candidates[count] = temporal
                count             += 1
            }
        }

        let originalCount = count
        if header.sliceType == SliceTypeB and originalCount > 1 do
            .addCombinedMergeCandidates(&candidates[0], &count, originalCount)
        .addZeroMergeCandidates(&candidates[0], &count)

        var result = candidates[Math.min(mergeIdx, header.maxNumMergeCand - 1)]

        // A four-by-eight or eight-by-four block never predicts from both lists, clause 8-126.
        if result.predFlags == 3 and nPbW + nPbH == 12
        {
            result.predFlags = 1
            result.refIdx[1] = -1
        }

        return result
    }

    // Collects the five spatial merge candidates, clause 8.5.3.2.3.
    private mtd gatherSpatialMergeCandidates(candidates: [*] PuMotion, count: *u32, xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH: s32, partIdx, partMode: u32)
    {
        let header = &.header
        let level  = .activePps!.log2ParallelMergeLevel

        var found:  [5] bool
        var motion: [5] PuMotion

        // A1, to the left of the bottom of the block.
        let xA1         = xPb - 1
        let yA1         = yPb + nPbH - 1
        var availableA1 = .isAvailablePrediction(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH, partIdx, xA1, yA1)
        if .sameMergeRegion(xPb, yPb, xA1, yA1, level) do
            availableA1 = false
        if partIdx == 1 and (partMode == PartNx2N or partMode == PartnLx2N or partMode == PartnRx2N) do
            availableA1 = false
        if availableA1
        {
            found[0]  = true
            motion[0] = .motionAt(xA1, yA1)[]
        }

        // B1, above the right of the block.
        let xB1         = xPb + nPbW - 1
        let yB1         = yPb - 1
        var availableB1 = .isAvailablePrediction(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH, partIdx, xB1, yB1)
        if .sameMergeRegion(xPb, yPb, xB1, yB1, level) do
            availableB1 = false
        if partIdx == 1 and (partMode == Part2NxN or partMode == Part2NxnU or partMode == Part2NxnD) do
            availableB1 = false
        if availableB1 and !(found[0] and .sameMotion(&motion[0], .motionAt(xB1, yB1)))
        {
            found[1]  = true
            motion[1] = .motionAt(xB1, yB1)[]
        }

        // B0, above and to the right of the block.
        let xB0         = xPb + nPbW
        let yB0         = yPb - 1
        var availableB0 = .isAvailablePrediction(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH, partIdx, xB0, yB0)
        if .sameMergeRegion(xPb, yPb, xB0, yB0, level) do
            availableB0 = false
        if availableB0 and !(availableB1 and .sameMotion(.motionAt(xB1, yB1), .motionAt(xB0, yB0)))
        {
            found[2]  = true
            motion[2] = .motionAt(xB0, yB0)[]
        }

        // A0, below and to the left of the block.
        let xA0         = xPb - 1
        let yA0         = yPb + nPbH
        var availableA0 = .isAvailablePrediction(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH, partIdx, xA0, yA0)
        if .sameMergeRegion(xPb, yPb, xA0, yA0, level) do
            availableA0 = false
        if availableA0 and !(availableA1 and .sameMotion(.motionAt(xA1, yA1), .motionAt(xA0, yA0)))
        {
            found[3]  = true
            motion[3] = .motionAt(xA0, yA0)[]
        }

        // B2, diagonally above and to the left, which only fills a list the others left short.
        let xB2         = xPb - 1
        let yB2         = yPb - 1
        var availableB2 = .isAvailablePrediction(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH, partIdx, xB2, yB2)
        if .sameMergeRegion(xPb, yPb, xB2, yB2, level) do
            availableB2 = false
        if found[0] and found[1] and found[2] and found[3] do
            availableB2 = false
        if availableB2 and availableA1 and .sameMotion(.motionAt(xA1, yA1), .motionAt(xB2, yB2)) do
            availableB2 = false
        if availableB2 and availableB1 and .sameMotion(.motionAt(xB1, yB1), .motionAt(xB2, yB2)) do
            availableB2 = false
        if availableB2
        {
            found[4]  = true
            motion[4] = .motionAt(xB2, yB2)[]
        }

        // The list order of equation 8-119.
        for slot in 5'u32
        {
            if !found[slot] or count[] >= header.maxNumMergeCand do
                continue
            candidates[count[]] = motion[slot]
            count[]             += 1
        }
    }

    // Reports whether two positions sit in the same parallel merge region, clause 8.5.3.2.3.
    private mtd const sameMergeRegion(x0, y0, x1, y1: s32, level: u32)->bool
    {
        return (x0 >> level) == (x1 >> level) and (y0 >> level) == (y1 >> level)
    }

    // Reports whether two prediction blocks carry identical motion.
    private mtd const sameMotion(left, right: const *PuMotion)->bool
    {
        if left.predFlags != right.predFlags do
            return false
        for list in ListCount
        {
            if (cast(u32) left.predFlags & (1'u32 << list)) == 0 do
                continue
            if left.refIdx[list] != right.refIdx[list] do
                return false
            if left.mv[list, 0] != right.mv[list, 0] or left.mv[list, 1] != right.mv[list, 1] do
                return false
        }

        return true
    }

    // Adds the combined bi-predictive merge candidates, clause 8.5.3.2.4.
    private mtd addCombinedMergeCandidates(candidates: [*] PuMotion, count: *u32, originalCount: u32)
    {
        let header = &.header
        if originalCount >= header.maxNumMergeCand do
            return

        let limit   = originalCount * (originalCount - 1)
        var combIdx = 0'u32
        while combIdx < limit and count[] < header.maxNumMergeCand and combIdx < 12
        {
            let first  = &candidates[CombinedCandL0[combIdx]]
            let second = &candidates[CombinedCandL1[combIdx]]
            combIdx += 1

            if (first.predFlags & 1) == 0 or (second.predFlags & 2) == 0 do
                continue

            let firstPoc  = .refList.poc[0, cast(u32) first.refIdx[0]]
            let secondPoc = .refList.poc[1, cast(u32) second.refIdx[1]]
            if firstPoc == secondPoc and first.mv[0, 0] == second.mv[1, 0] and first.mv[0, 1] == second.mv[1, 1] do
                continue

            var combined: PuMotion
            combined.mv[0, 0]   = first.mv[0, 0]
            combined.mv[0, 1]   = first.mv[0, 1]
            combined.mv[1, 0]   = second.mv[1, 0]
            combined.mv[1, 1]   = second.mv[1, 1]
            combined.refIdx[0]  = first.refIdx[0]
            combined.refIdx[1]  = second.refIdx[1]
            combined.predFlags  = 3
            candidates[count[]] = combined
            count[]             += 1
        }
    }

    // Fills the merge list with zero-motion candidates, clause 8.5.3.2.5.
    private mtd addZeroMergeCandidates(candidates: [*] PuMotion, count: *u32)
    {
        let header = &.header
        let bi     = header.sliceType == SliceTypeB
        let usable = bi ? Math.min(.refList.count[0], .refList.count[1]) : .refList.count[0]

        var zeroIdx = 0'u32
        while count[] < header.maxNumMergeCand
        {
            var candidate: PuMotion
            let index = zeroIdx < usable ? cast(s8) zeroIdx : 0's8
            candidate.refIdx[0] = index
            candidate.predFlags = 1
            if bi
            {
                candidate.refIdx[1] = index
                candidate.predFlags = 3
            }

            candidates[count[]] = candidate
            count[]             += 1
            zeroIdx             += 1
        }
    }

    // Derives the temporal motion vector predictor, clause 8.5.3.2.8.
    mtd temporalMotion(xPb, yPb, nPbW, nPbH: s32, list: u32, refIdx: s32)->TemporalMotion
    {
        var result: retval
        let header = &.header
        if !header.temporalMvpEnabled do
            return result

        let sps     = .activeSps!
        let colList = header.collocatedFromL0 ? 0'u32 : 1'u32
        if header.collocatedRefIdx >= .refList.count[colList] do
            return result
        let collocated = .refList.frames[colList, header.collocatedRefIdx]
        if !collocated do
            return result

        // The block below and to the right of the prediction block, when it exists and stays in
        // the same coding tree block row.
        let xColBr = xPb + nPbW
        let yColBr = yPb + nPbH
        if (yPb >> sps.ctbLog2Size) == (yColBr >> sps.ctbLog2Size) and yColBr < cast(s32) sps.height and xColBr < cast(s32) sps.width
        {
            result = .collocatedMotion(collocated!, (xColBr >> 4) << 4, (yColBr >> 4) << 4, list, refIdx)
            if result.available do
                return result
        }

        // Otherwise the centre of the prediction block.
        return .collocatedMotion(collocated!, ((xPb + (nPbW >> 1)) >> 4) << 4, ((yPb + (nPbH >> 1)) >> 4) << 4, list, refIdx)
    }

    // Reads and scales the motion of one region of the collocated picture, clause 8.5.3.2.9.
    private mtd collocatedMotion(collocated: *Frame, x, y: s32, list: u32, refIdx: s32)->TemporalMotion
    {
        var result: retval
        let column = collocated.colMotionAt(x, y)
        if !column.predFlags do
            return result

        // Which of the collocated block's two vectors is used, clause 8.5.3.2.9.
        var source = 0'u32
        if (column.predFlags & 1) == 0
        {
            source = 1
        }
        elif (column.predFlags & 2) != 0
        {
            source = .noBackwardPrediction() ? list : (.header.collocatedFromL0 ? 1'u32 : 0'u32)
            if (cast(u32) column.predFlags & (1'u32 << source)) == 0 do
                source = source ^ 1
        }

        let currentLongTerm = .refList.longTerm[list, cast(u32) refIdx]
        let sourceLongTerm  = (cast(u32) column.longTermRef & (1'u32 << source)) != 0
        if currentLongTerm != sourceLongTerm do
            return result

        let colPocDiff  = collocated.poc - column.refPoc[source]
        let currPocDiff = .pocValue - .refList.poc[list, cast(u32) refIdx]

        result.available = true
        if currentLongTerm or colPocDiff == currPocDiff
        {
            result.mv[0] = column.mv[source, 0]
            result.mv[1] = column.mv[source, 1]
            return result
        }

        result.mv[0] = cast(s16) .scaleMotion(cast(s32) column.mv[source, 0], currPocDiff, colPocDiff)
        result.mv[1] = cast(s16) .scaleMotion(cast(s32) column.mv[source, 1], currPocDiff, colPocDiff)
        return result
    }

    // Derives the motion vector predictor of one list, clauses 8.5.3.2.6 and 8.5.3.2.7.
    mtd derivePredictor(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH: s32, partIdx, list: u32, refIdx: s32, mvpFlag: u32)->[2] s16
    {
        var candidates: [3, 2] s16
        var count = 0'u32

        let xA0         = xPb - 1
        let yA0         = yPb + nPbH
        let xA1         = xPb - 1
        let yA1         = yPb + nPbH - 1
        let availableA0 = .isAvailablePrediction(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH, partIdx, xA0, yA0)
        let availableA1 = .isAvailablePrediction(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH, partIdx, xA1, yA1)
        let isScaled    = availableA0 or availableA1

        var mvA: [2] s16
        var foundA = .neighbourPredictor(&mvA[0], xA0, yA0, availableA0, xA1, yA1, availableA1, list, refIdx, allowScaling: false)
        if !foundA do
            foundA = .neighbourPredictor(&mvA[0], xA0, yA0, availableA0, xA1, yA1, availableA1, list, refIdx, allowScaling: true)

        let xB0         = xPb + nPbW
        let yB0         = yPb - 1
        let xB1         = xPb + nPbW - 1
        let yB1         = yPb - 1
        let xB2         = xPb - 1
        let yB2         = yPb - 1
        let availableB0 = .isAvailablePrediction(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH, partIdx, xB0, yB0)
        let availableB1 = .isAvailablePrediction(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH, partIdx, xB1, yB1)
        let availableB2 = .isAvailablePrediction(xCb, yCb, nCbS, xPb, yPb, nPbW, nPbH, partIdx, xB2, yB2)

        var mvB: [2] s16
        var foundB = .neighbourPredictorB(&mvB[0], xB0, yB0, availableB0, xB1, yB1, availableB1, xB2, yB2, availableB2, list, refIdx, allowScaling: false)

        // With nothing to the left, the above candidate takes the left slot and the above one is
        // derived again, this time allowed to scale, clause 8-186.
        if !isScaled
        {
            if foundB
            {
                foundA = true
                mvA    = mvB
            }

            foundB = .neighbourPredictorB(&mvB[0], xB0, yB0, availableB0, xB1, yB1, availableB1, xB2, yB2, availableB2, list, refIdx, allowScaling: true)
        }

        if foundA
        {
            candidates[count, 0] = mvA[0]
            candidates[count, 1] = mvA[1]
            count                += 1
        }

        if foundB and !(foundA and mvA[0] == mvB[0] and mvA[1] == mvB[1])
        {
            candidates[count, 0] = mvB[0]
            candidates[count, 1] = mvB[1]
            count                += 1
        }

        if count < 2 and .header.temporalMvpEnabled
        {
            let temporal = .temporalMotion(xPb, yPb, nPbW, nPbH, list, refIdx)
            if temporal.available
            {
                candidates[count, 0] = temporal.mv[0]
                candidates[count, 1] = temporal.mv[1]
                count                += 1
            }
        }

        while count < 2
        {
            candidates[count, 0] = 0
            candidates[count, 1] = 0
            count                += 1
        }

        let selected = Math.min(mvpFlag, 1'u32)
        return [candidates[selected, 0], candidates[selected, 1]]
    }

    // Takes the first usable predictor among the two left neighbours, clause 8.5.3.2.7.
    private mtd neighbourPredictor(target: [*] s16, x0, y0: s32, available0: bool, x1, y1: s32, available1: bool, list: u32, refIdx: s32, allowScaling: bool)->bool
    {
        if available0 and .takePredictor(target, x0, y0, list, refIdx, allowScaling) do
            return true
        if available1 and .takePredictor(target, x1, y1, list, refIdx, allowScaling) do
            return true
        return false
    }

    // Takes the first usable predictor among the three above neighbours, clause 8.5.3.2.7.
    private mtd neighbourPredictorB(target: [*] s16, x0, y0: s32, available0: bool, x1, y1: s32, available1: bool, x2, y2: s32, available2: bool, list: u32, refIdx: s32, allowScaling: bool)->bool
    {
        if available0 and .takePredictor(target, x0, y0, list, refIdx, allowScaling) do
            return true
        if available1 and .takePredictor(target, x1, y1, list, refIdx, allowScaling) do
            return true
        if available2 and .takePredictor(target, x2, y2, list, refIdx, allowScaling) do
            return true
        return false
    }

    // Takes the motion of one neighbour as a predictor when it refers to a usable picture.
    //
    // Without `allowScaling` only a neighbour pointing at the very picture the current block
    // predicts from qualifies; with it, any short-term picture does and the vector is scaled by
    // the ratio of the two distances.
    private mtd takePredictor(target: [*] s16, x, y: s32, list: u32, refIdx: s32, allowScaling: bool)->bool
    {
        let neighbour  = .motionAt(x, y)
        let wantedPoc  = .refList.poc[list, cast(u32) refIdx]
        let wantedLong = .refList.longTerm[list, cast(u32) refIdx]

        for offset in ListCount
        {
            // The neighbour's own list is preferred, and the other one is the fallback.
            let candidateList = (list + offset) & 1
            if (cast(u32) neighbour.predFlags & (1'u32 << candidateList)) == 0 do
                continue
            if neighbour.refIdx[candidateList] < 0 do
                continue

            let index = cast(u32) neighbour.refIdx[candidateList]
            if index >= .refList.count[candidateList] do
                continue

            let neighbourPoc  = .refList.poc[candidateList, index]
            let neighbourLong = .refList.longTerm[candidateList, index]

            if !allowScaling
            {
                if neighbourPoc != wantedPoc do
                    continue
                target[0] = neighbour.mv[candidateList, 0]
                target[1] = neighbour.mv[candidateList, 1]
                return true
            }

            if neighbourLong != wantedLong do
                continue

            if neighbourLong or neighbourPoc == wantedPoc
            {
                target[0] = neighbour.mv[candidateList, 0]
                target[1] = neighbour.mv[candidateList, 1]
                return true
            }

            let currentDiff   = .pocValue - wantedPoc
            let referenceDiff = .pocValue - neighbourPoc
            target[0] = cast(s16) .scaleMotion(cast(s32) neighbour.mv[candidateList, 0], currentDiff, referenceDiff)
            target[1] = cast(s16) .scaleMotion(cast(s32) neighbour.mv[candidateList, 1], currentDiff, referenceDiff)
            return true
        }

        return false
    }

    // Records the motion of one prediction block over the blocks it covers.
    mtd storeMotion(xPb, yPb, nPbW, nPbH: s32, motion: const *PuMotion)
    {
        let blocksX = cast(u32) nPbW >> MinBlockLog2
        let blocksY = cast(u32) nPbH >> MinBlockLog2
        let origin  = .blockIndex(xPb, yPb)
        for row in blocksY
        {
            let line = origin + cast(u64) row * cast(u64) .gridWidth
            for column in blocksX do
                .motion[line + cast(u64) column] = motion[]
        }
    }
}
