//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns normative in-loop edge filtering.
//
#global namespace Hevc
#global internal

using Core

// The deblocking parameters of one slice, which the loop filter needs long after the slice that
// carried them was parsed.
struct SliceDeblock
{
    disabled:               bool
    loopFilterAcrossSlices: bool
    betaOffsetDiv2:         s8
    tcOffsetDiv2:           s8
}

// The bits of the per-block edge grid: which of a block's two leading edges start a transform or
// a prediction block, which is what decides whether the loop filter looks at them at all.
const EdgeTransformLeft  = 1'u8
const EdgeTransformTop   = 2'u8
const EdgePredictionLeft = 4'u8
const EdgePredictionTop  = 8'u8

private const DeblockLanes = 8'u32

private struct DeblockContext
{
    decoder:   *Decoder
    vertical:  bool
    stepX:     u32
    stepY:     u32
    bandCount: u32
    laneCount: u32
}

impl Decoder
{
    // Marks the leading edges of one block in the edge grid.
    mtd markEdges(x0, y0, width, height: s32, leftMask, topMask: u8)
    {
        let blocksX = cast(u32) width >> MinBlockLog2
        let blocksY = cast(u32) height >> MinBlockLog2
        let origin  = .blockIndex(x0, y0)

        for row in blocksY do
            .edgeFlags[origin + cast(u64) row * cast(u64) .gridWidth] |= leftMask
        for column in blocksX do
            .edgeFlags[origin + cast(u64) column] |= topMask
    }

    // Filters the block edges of the whole picture, clause 8.7.2.
    //
    // Every vertical edge is filtered before any horizontal one, because the horizontal pass reads
    // what the vertical pass produced.
    mtd deblockPicture()
    {
        .filterEdges(vertical: true)
        .filterEdges(vertical: false)
    }

    // Filters every edge of one direction, clause 8.7.2.3.
    private mtd filterEdges(vertical: bool)
    {
        let sps       = .activeSps!
        let stepX     = vertical ? 8'u32 : 4'u32
        let stepY     = vertical ? 4'u32 : 8'u32
        let bandCount = (sps.height + stepY - 1) / stepY
        let laneCount = Math.min(Math.min(Jobs.workerCount(), DeblockLanes), bandCount)

        if laneCount > 1
        {
            var context = DeblockContext{me, vertical, stepX, stepY, bandCount, laneCount}
            Jobs.parallelFor(laneCount, &context)
            {
                let state = cast(*DeblockContext) data!
                let width = state.decoder.activeSps!.width
                var band  = index
                while band < state.bandCount
                {
                    let y = band * state.stepY
                    var x = 0'u32
                    while x < width
                    {
                        state.decoder.filterBlockEdge(cast(s32) x, cast(s32) y, state.vertical)
                        x += state.stepX
                    }

                    band += state.laneCount
                }
            }

            return
        }

        var y = 0'u32
        while y < sps.height
        {
            var x = 0'u32
            while x < sps.width
            {
                .filterBlockEdge(cast(s32) x, cast(s32) y, vertical)
                x += stepX
            }

            y += stepY
        }
    }

    // Filters the leading edge of one four-sample block, when it carries one.
    private mtd filterBlockEdge(x, y: s32, vertical: bool)
    {
        let sps = .activeSps!
        if vertical and !x do
            return
        if !vertical and !y do
            return

        let index = .blockIndex(x, y)
        let flags = .edgeFlags[index]
        let mask  = vertical ? EdgeTransformLeft | EdgePredictionLeft : EdgeTransformTop | EdgePredictionTop
        if (flags & mask) == 0 do
            return

        let xP = vertical ? x - 1 : x
        let yP = vertical ? y : y - 1
        if !.filterAcrossAllowed(x, y, xP, yP) do
            return

        let strength = .boundaryStrength(x, y, xP, yP, vertical, flags)
        if !strength do
            return

        let qpP   = cast(s32) .qpY[.blockIndex(xP, yP)]
        let qpQ   = cast(s32) .qpY[index]
        let slice = &.sliceParams[cast(u64) .ctbSliceIndex[.ctbAddressRs(x, y)]]
        .filterLumaEdge(x, y, vertical, strength, qpP, qpQ, slice)

        // A chroma edge sits every sixteen luma samples, and is only filtered where an intra
        // block is on one side of it.
        if strength == 2 and sps.chromaArrayType != 0
        {
            let aligned = vertical ? (x & 15) == 0 : (y & 15) == 0
            if aligned
            {
                .filterChromaEdge(x, y, vertical, qpP, qpQ, 1, slice)
                .filterChromaEdge(x, y, vertical, qpP, qpQ, 2, slice)
            }
        }
    }

    // Reports whether the loop filter may cross this edge, clause 8.7.2.
    private mtd const filterAcrossAllowed(x, y, xP, yP: s32)->bool
    {
        let sps    = .activeSps!
        let pps    = .activePps!
        let header = &.header

        discard header

        let currentCtb   = .ctbRsToTs[.ctbAddressRs(x, y)]
        let neighbourCtb = .ctbRsToTs[.ctbAddressRs(xP, yP)]
        if currentCtb == neighbourCtb do
            return true

        if !pps.loopFilterAcrossTiles and .tileId[currentCtb] != .tileId[neighbourCtb] do
            return false

        let slice = &.sliceParams[cast(u64) .ctbSliceIndex[.ctbAddressRs(x, y)]]
        if !slice.loopFilterAcrossSlices and .ctbSliceAddr[.ctbAddressRs(x, y)] != .ctbSliceAddr[.ctbAddressRs(xP, yP)] do
            return false
        discard sps
        return true
    }

    // Derives the boundary strength of one edge, clause 8.7.2.4.
    private mtd const boundaryStrength(x, y, xP, yP: s32, vertical: bool, flags: u8)->u32
    {
        let indexQ = .blockIndex(x, y)
        let indexP = .blockIndex(xP, yP)

        if .predMode[indexQ] == ModeIntra or .predMode[indexP] == ModeIntra do
            return 2

        let transformEdge = (flags & (vertical ? EdgeTransformLeft : EdgeTransformTop)) != 0
        if transformEdge and (.cbfLuma[indexQ] != 0 or .cbfLuma[indexP] != 0) do
            return 1

        return .motionDiffers(.motionAt(x, y), .motionAt(xP, yP)) ? 1'u32 : 0'u32
    }

    // Reports whether two prediction blocks differ enough for the edge between them to be
    // filtered, clause 8.7.2.4.
    private mtd const motionDiffers(left, right: const *PuMotion)->bool
    {
        var leftPoc, rightPoc: [2] s32
        var leftCount, rightCount = 0'u32
        for list in ListCount
        {
            if (cast(u32) left.predFlags & (1'u32 << list)) != 0
            {
                leftPoc[leftCount] = .refList.poc[list, cast(u32) left.refIdx[list]]
                leftCount          += 1
            }

            if (cast(u32) right.predFlags & (1'u32 << list)) != 0
            {
                rightPoc[rightCount] = .refList.poc[list, cast(u32) right.refIdx[list]]
                rightCount           += 1
            }
        }

        if leftCount != rightCount do
            return true

        // The two sides have to name the same pictures, whichever list each used.
        if leftCount == 1
        {
            if leftPoc[0] != rightPoc[0] do
                return true
            let leftList  = (left.predFlags & 1) != 0 ? 0'u32 : 1'u32
            let rightList = (right.predFlags & 1) != 0 ? 0'u32 : 1'u32
            return .motionFar(left, leftList, right, rightList)
        }

        if !leftCount do
            return false

        let sameOrder    = leftPoc[0] == rightPoc[0] and leftPoc[1] == rightPoc[1]
        let crossedOrder = leftPoc[0] == rightPoc[1] and leftPoc[1] == rightPoc[0]
        if !sameOrder and !crossedOrder do
            return true

        if leftPoc[0] == leftPoc[1]
        {
            // Both vectors point at the same picture, so both pairings have to be close.
            let straight = .motionFar(left, 0, right, 0) or .motionFar(left, 1, right, 1)
            let crossed  = .motionFar(left, 0, right, 1) or .motionFar(left, 1, right, 0)
            return straight and crossed
        }

        if sameOrder do
            return .motionFar(left, 0, right, 0) or .motionFar(left, 1, right, 1)
        return .motionFar(left, 0, right, 1) or .motionFar(left, 1, right, 0)
    }

    // Reports whether two motion vectors differ by a whole sample or more.
    private mtd const motionFar(left: const *PuMotion, leftList: u32, right: const *PuMotion, rightList: u32)->bool
    {
        let dx = Math.abs(cast(s32) left.mv[leftList, 0] - cast(s32) right.mv[rightList, 0])
        let dy = Math.abs(cast(s32) left.mv[leftList, 1] - cast(s32) right.mv[rightList, 1])
        return dx >= 4 or dy >= 4
    }

    // Filters one four-line luma edge, clauses 8.7.2.5.3 and 8.7.2.5.7.
    //
    // The segment is addressed by two steps rather than by a coordinate pair: one that walks the
    // four lines of the edge and one that crosses it. Both directions then read and write through
    // the same offsets, and the whole filter costs no address arithmetic beyond an index.
    private mtd filterLumaEdge(x, y: s32, vertical: bool, strength: u32, qpP, qpQ: s32, slice: const *SliceDeblock)
    {
        if slice.disabled do
            return

        let sps      = .activeSps!
        let frame    = .current!
        let bitDepth = sps.bitDepthLuma
        let maximum  = cast(s32) ((1'u32 << bitDepth) - 1)

        let average = (qpP + qpQ + 1) >> 1
        let betaQ   = Math.clamp(average + (cast(s32) slice.betaOffsetDiv2 << 1), 0, 51)
        let beta    = cast(s32) DeblockBeta[betaQ] * (1 << (bitDepth - 8))
        let tcQ     = Math.clamp(average + 2 * (cast(s32) strength - 1) + (cast(s32) slice.tcOffsetDiv2 << 1), 0, 53)
        let tc      = cast(s32) DeblockTc[tcQ] * (1 << (bitDepth - 8))
        if !beta do
            return

        let stride = cast(s64) frame.strideLuma
        let origin = frame.luma.buffer! + cast(u64) (y + cast(s32) FramePadding) * frame.strideLuma + cast(u64) (x + cast(s32) FramePadding)
        let lineStep   = vertical ? stride : 1's64
        let crossStep  = vertical ? 1's64 : stride

        // The two outer lines of the segment decide for all four, clause 8.7.2.5.3.
        let a = origin
        let d = origin + 3 * lineStep

        let p0a = cast(s32) a[-crossStep]
        let p1a = cast(s32) a[-2 * crossStep]
        let p2a = cast(s32) a[-3 * crossStep]
        let p3a = cast(s32) a[-4 * crossStep]
        let q0a = cast(s32) a[0]
        let q1a = cast(s32) a[crossStep]
        let q2a = cast(s32) a[2 * crossStep]
        let q3a = cast(s32) a[3 * crossStep]

        let p0d = cast(s32) d[-crossStep]
        let p1d = cast(s32) d[-2 * crossStep]
        let p2d = cast(s32) d[-3 * crossStep]
        let p3d = cast(s32) d[-4 * crossStep]
        let q0d = cast(s32) d[0]
        let q1d = cast(s32) d[crossStep]
        let q2d = cast(s32) d[2 * crossStep]
        let q3d = cast(s32) d[3 * crossStep]

        let dp0  = Math.abs(p2a - 2 * p1a + p0a)
        let dp3  = Math.abs(p2d - 2 * p1d + p0d)
        let dq0  = Math.abs(q2a - 2 * q1a + q0a)
        let dq3  = Math.abs(q2d - 2 * q1d + q0d)
        let dpq0 = dp0 + dq0
        let dpq3 = dp3 + dq3
        let dp   = dp0 + dp3
        let dq   = dq0 + dq3
        let d0   = dpq0 + dpq3
        if d0 >= beta do
            return

        let strong0 = .strongFilterDecision(2 * dpq0, beta, tc, p3a, p0a, q0a, q3a)
        let strong3 = .strongFilterDecision(2 * dpq3, beta, tc, p3d, p0d, q0d, q3d)
        let strong  = strong0 and strong3
        let filterP = dp < ((beta + (beta >> 1)) >> 3)
        let filterQ = dq < ((beta + (beta >> 1)) >> 3)

        var line = origin
        for index in 4'u32
        {
            let p0 = cast(s32) line[-crossStep]
            let p1 = cast(s32) line[-2 * crossStep]
            let p2 = cast(s32) line[-3 * crossStep]
            let q0 = cast(s32) line[0]
            let q1 = cast(s32) line[crossStep]
            let q2 = cast(s32) line[2 * crossStep]

            if strong
            {
                let p3    = cast(s32) line[-4 * crossStep]
                let q3    = cast(s32) line[3 * crossStep]
                let limit = 2 * tc
                line[-crossStep]     = cast(u16) Math.clamp((p2 + 2 * p1 + 2 * p0 + 2 * q0 + q1 + 4) >> 3, p0 - limit, p0 + limit)
                line[-2 * crossStep] = cast(u16) Math.clamp((p2 + p1 + p0 + q0 + 2) >> 2, p1 - limit, p1 + limit)
                line[-3 * crossStep] = cast(u16) Math.clamp((2 * p3 + 3 * p2 + p1 + p0 + q0 + 4) >> 3, p2 - limit, p2 + limit)
                line[0]              = cast(u16) Math.clamp((p1 + 2 * p0 + 2 * q0 + 2 * q1 + q2 + 4) >> 3, q0 - limit, q0 + limit)
                line[crossStep]      = cast(u16) Math.clamp((p0 + q0 + q1 + q2 + 2) >> 2, q1 - limit, q1 + limit)
                line[2 * crossStep]  = cast(u16) Math.clamp((p0 + q0 + q1 + 3 * q2 + 2 * q3 + 4) >> 3, q2 - limit, q2 + limit)
                line += lineStep
                continue
            }

            var delta = (9 * (q0 - p0) - 3 * (q1 - p1) + 8) >> 4
            if Math.abs(delta) >= tc * 10
            {
                line += lineStep
                continue
            }

            delta = Math.clamp(delta, -tc, tc)
            line[-crossStep] = cast(u16) Math.clamp(p0 + delta, 0, maximum)
            line[0]          = cast(u16) Math.clamp(q0 - delta, 0, maximum)

            if filterP
            {
                let half  = tc >> 1
                let value = Math.clamp((((p2 + p0 + 1) >> 1) - p1 + delta) >> 1, -half, half)
                line[-2 * crossStep] = cast(u16) Math.clamp(p1 + value, 0, maximum)
            }

            if filterQ
            {
                let half  = tc >> 1
                let value = Math.clamp((((q2 + q0 + 1) >> 1) - q1 - delta) >> 1, -half, half)
                line[crossStep] = cast(u16) Math.clamp(q1 + value, 0, maximum)
            }

            line += lineStep
        }
    }

    // Decides whether one line of an edge takes the wide filter, clause 8.7.2.5.6.
    private mtd const strongFilterDecision(dpq, beta, tc, p3, p0, q0, q3: s32)->bool
    {
        if dpq >= (beta >> 2) do
            return false
        if Math.abs(p3 - p0) + Math.abs(q0 - q3) >= (beta >> 3) do
            return false
        return Math.abs(p0 - q0) < ((5 * tc + 1) >> 1)
    }

    // Filters one four-line chroma edge, clause 8.7.2.5.5.
    private mtd filterChromaEdge(x, y: s32, vertical: bool, qpP, qpQ: s32, component: u32, slice: const *SliceDeblock)
    {
        if slice.disabled do
            return

        let sps      = .activeSps!
        let pps      = .activePps!
        let frame    = .current!
        let bitDepth = sps.bitDepthChroma
        let maximum  = cast(s32) ((1'u32 << bitDepth) - 1)

        let offset  = component == 1 ? pps.cbQpOffset : pps.crQpOffset
        let average = ((qpP + qpQ + 1) >> 1) + offset

        var chromaQp = average
        if sps.chromaArrayType == 1
        {
            if average >= 30 and average <= 43 do
                chromaQp = cast(s32) ChromaQpMapping[average - 30]
            elif average > 43 do
                chromaQp = average - 6
        }
        else
        {
            chromaQp = Math.min(average, 51)
        }

        let tcQ = Math.clamp(chromaQp + 2 + (cast(s32) slice.tcOffsetDiv2 << 1), 0, 53)
        let tc  = cast(s32) DeblockTc[tcQ] * (1 << (bitDepth - 8))
        if !tc do
            return

        let plane  = component == 1 ? frame.chromaB.buffer! : frame.chromaR.buffer!
        let stride = cast(s64) frame.strideChroma
        let cx     = x / cast(s32) sps.subWidthC
        let cy     = y / cast(s32) sps.subHeightC

        let origin    = plane + cast(u64) (cy + cast(s32) FramePadding) * frame.strideChroma + cast(u64) (cx + cast(s32) FramePadding)
        let lineStep  = vertical ? stride : 1's64
        let crossStep = vertical ? 1's64 : stride

        // One luma segment of four lines covers two chroma lines.
        var line = origin
        for index in 2'u32
        {
            let p0 = cast(s32) line[-crossStep]
            let p1 = cast(s32) line[-2 * crossStep]
            let q0 = cast(s32) line[0]
            let q1 = cast(s32) line[crossStep]

            let delta = Math.clamp((((q0 - p0) << 2) + p1 - q1 + 4) >> 3, -tc, tc)
            line[-crossStep] = cast(u16) Math.clamp(p0 + delta, 0, maximum)
            line[0]          = cast(u16) Math.clamp(q0 - delta, 0, maximum)
            line += lineStep
        }
    }
}
