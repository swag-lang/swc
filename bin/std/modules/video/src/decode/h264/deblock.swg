#global namespace H264
#global internal

//! Format: H.264/AVC decoder component.
//! Supported: Progressive 8-bit 4:2:0 Baseline, Main, and High-profile streams with CAVLC/CABAC, I/P/B slices, weighted prediction, cropping, reordering, and deblocking.
//! Not supported: Interlacing, non-4:2:0 chroma, bit depths above 8, slice groups, data partitioning, scalable/multiview extensions, and lossless transform bypass.
//! Role: This file owns normative in-loop edge filtering.
//

using Core

// The deblocking filter, section 8.7, for progressive frames: every macroblock filters its
// vertical edges left to right, then its horizontal edges top to bottom, in place, in raster
// macroblock order.

private const DeblockLanes = 8'u32

private struct DeblockContext
{
    decoder:     *Decoder
    rowProgress: [*] u32
    laneCount:   u32
}

// Filters the whole decoded picture.
func deblockPicture(dec: *Decoder)
{
    let sps       = dec.sps!
    let laneCount = Math.min(Math.min(Jobs.workerCount(), DeblockLanes), cast(u32) sps.mbHeight)
    if laneCount <= 1
    {
        for mbY in sps.mbHeight
        {
            for mbX in sps.mbWidth do
                deblockMb(dec, mbX, mbY)
        }

        return
    }

    // A macroblock touches samples owned by its left and top neighbors. Rows therefore form a
    // wavefront: row Y may filter X once row Y-1 has completed X+1. The extra macroblock of
    // lead matters because the previous row's next vertical boundary overlaps the horizontal
    // edge being filtered here. Rows with the same lane are far enough apart to run in one job.
    var rowProgress: Array'u32
    rowProgress.resize(cast(u64) sps.mbHeight)
    var context = DeblockContext{dec, rowProgress.buffer!, laneCount}
    Jobs.parallelFor(laneCount, &context)
    {
        let state  = cast(*DeblockContext) data!
        let width  = state.decoder.sps!.mbWidth
        let height = state.decoder.sps!.mbHeight
        var mbY    = cast(s32) index
        while mbY < height
        {
            for mbX in width
            {
                if mbY > 0
                {
                    // The row above is normally one macroblock ahead, so this waits a few
                    // hundred cycles and the spin is what it should be. A wait far longer than
                    // that means the lane holding the answer has no core of its own, and
                    // spinning is what keeps it from getting one, so hand this one over.
                    let required = cast(u32) Math.min(mbX + 2, width)
                    var spins    = 0'u32
                    while Atomic.get(state.rowProgress + cast(u64) mbY - 1) < required
                    {
                        spins += 1
                        if spins == 4096
                        {
                            Threading.Thread.yield()
                            spins = 0
                        }
                    }
                }

                deblockMb(state.decoder, mbX, mbY)
                Atomic.exchange(state.rowProgress + cast(u64) mbY, cast(u32) mbX + 1)
            }

            mbY += cast(s32) state.laneCount
        }
    }
}

// Boundary strengths of one macroblock edge, one per 4-sample segment.
struct EdgeStrength
{
    bs: [4] u32
}

// Reference and motion state needed to compare one 4x4 block edge.
private struct DeblockMotion
{
    refPoc: [2] s32
    mv:     [2, 2] s16
}

// Reads motion from the compact macroblock job when a P-skip never published a 4x4 grid.
private func deblockMotion(dec: *Decoder, blockIndex: u64)->DeblockMotion
{
    let blocksWide = dec.sps!.mbWidth * 4
    let x4         = cast(s32) (blockIndex % cast(u64) blocksWide)
    let y4         = cast(s32) (blockIndex / cast(u64) blocksWide)
    let mbIndex    = cast(u64) ((y4 >> 2) * dec.sps!.mbWidth + (x4 >> 2))
    let info       = &dec.mbInfo[mbIndex]

    var result: retval
    if info.skipped and !info.direct
    {
        let mb    = &dec.parsedMbs[mbIndex]
        let job   = &mb.firstJob
        let slice = &dec.pictureSlices[mb.sliceIndex]
        for list in 2'u32
        {
            let ref = job.refIdx[list]
            result.refPoc[list] = ref >= 0 ? slice.refs[list, cast(u64) ref].poc : NoRefPoc
            result.mv[list, 0]  = job.mv[list, 0]
            result.mv[list, 1]  = job.mv[list, 1]
        }

        return result
    }

    result.refPoc[0] = dec.refPocL0[blockIndex]
    result.refPoc[1] = dec.refPocL1[blockIndex]
    result.mv[0, 0]  = dec.mvL0[blockIndex * 2]
    result.mv[0, 1]  = dec.mvL0[blockIndex * 2 + 1]
    result.mv[1, 0]  = dec.mvL1[blockIndex * 2]
    result.mv[1, 1]  = dec.mvL1[blockIndex * 2 + 1]
    return result
}

// Computes the strength of one 4x4 block edge between blocks `p` and `q`, section 8.7.2.1.
private func edgeStrength(dec: *Decoder, pIndex, qIndex: u64, mbEdge, pIntra, qIntra, pCoded, qCoded: bool)->u32
{
    if pIntra or qIntra do
        return mbEdge ? 4'u32 : 3'u32
    if pCoded or qCoded do
        return 2

    // Reference and motion comparison.
    let p = deblockMotion(dec, pIndex)
    let q = deblockMotion(dec, qIndex)

    let straight = p.refPoc[0] == q.refPoc[0] and p.refPoc[1] == q.refPoc[1]
    let crossed  = p.refPoc[0] == q.refPoc[1] and p.refPoc[1] == q.refPoc[0]
    if !straight and !crossed do
        return 1

    if straight and mvClose(&p, &q, false) do
        return 0
    if crossed and mvClose(&p, &q, true) do
        return 0
    return 1
}

// Reports whether every motion vector pair differs by less than one full sample.
private func mvClose(p, q: const *DeblockMotion, crossed: bool)->bool
{
    let pL0x = cast(s32) p.mv[0, 0]
    let pL0y = cast(s32) p.mv[0, 1]
    let pL1x = cast(s32) p.mv[1, 0]
    let pL1y = cast(s32) p.mv[1, 1]
    var qL0x, qL0y, qL1x, qL1y: s32
    if crossed
    {
        qL0x = cast(s32) q.mv[1, 0]
        qL0y = cast(s32) q.mv[1, 1]
        qL1x = cast(s32) q.mv[0, 0]
        qL1y = cast(s32) q.mv[0, 1]
    }
    else
    {
        qL0x = cast(s32) q.mv[0, 0]
        qL0y = cast(s32) q.mv[0, 1]
        qL1x = cast(s32) q.mv[1, 0]
        qL1y = cast(s32) q.mv[1, 1]
    }

    // All four differences must stay below one full sample; OR-ing `3 - abs` keeps the test
    // branchless: any excursion sets the sign bit of the combined word.
    return ((3 - absS32(pL0x - qL0x)) | (3 - absS32(pL0y - qL0y)) | (3 - absS32(pL1x - qL1x)) | (3 - absS32(pL1y - qL1y))) >= 0
}

// Filters every edge of one macroblock.
// Filters one complete macroblock row, in the raster order the specification defines.
func deblockRow(dec: *Decoder, mbY: s32)
{
    for mbX in dec.sps!.mbWidth do
        deblockMb(dec, mbX, mbY)
}

func deblockMb(dec: *Decoder, mbX, mbY: s32)
{
    let sps   = dec.sps!
    let frame = dec.current!
    let info  = &dec.mbInfo[cast(u64) (mbY * sps.mbWidth + mbX)]
    if info.deblockIdc == 1 do
        return

    let gw     = sps.mbWidth * 4
    let qIntra = info.class != MbClassInter

    // Vertical edges: luma columns 0, 4, 8, 12.
    for edge in 4's32
    {
        var leftUniform = false
        if edge == 0
        {
            if mbX == 0 do
                continue
            let leftInfo = &dec.mbInfo[cast(u64) (mbY * sps.mbWidth + mbX - 1)]
            if info.deblockIdc == 2 and leftInfo.sliceId != info.sliceId do
                continue
            leftUniform = leftInfo.uniform
        }
        elif info.transform8x8 and (edge & 1) != 0
        {
            continue
        }
        elif info.uniform
        {
            // Every inner edge of a uniform macroblock has strength zero.
            continue
        }

        var strengths: EdgeStrength
        var hasAny = false
        if edge == 0 and info.uniform and leftUniform
        {
            // One motion on each side: the whole edge carries one strength.
            let qIndex = cast(u64) (mbY * 4 * gw + mbX * 4)
            let bs     = edgeStrength(dec, qIndex - 1, qIndex, true, false, false, false, false)
            if bs == 0 do
                continue
            strengths.bs = [bs, bs, bs, bs]
            hasAny       = true
        }
        else
        {
            for segment in 4's32
            {
                let qx     = mbX * 4 + edge
                let qy     = mbY * 4 + segment
                let qIndex = cast(u64) (qy * gw + qx)
                let pIndex = cast(u64) (qy * gw + qx - 1)
                var pIntra = qIntra
                var pCoded = dec.codedLuma[pIndex] != 0
                if edge == 0 do
                    pIntra = dec.mbInfo[cast(u64) (mbY * sps.mbWidth + mbX - 1)].class != MbClassInter
                let bs = edgeStrength(dec, pIndex, qIndex, edge == 0, pIntra, qIntra, pCoded, dec.codedLuma[qIndex] != 0)
                strengths.bs[cast(u64) segment] = bs
                if bs != 0 do
                    hasAny = true
            }
        }

        if !hasAny do
            continue

        // Average QP of the two sides.
        var qpP = cast(s32) info.qp
        if edge == 0 do
            qpP = cast(s32) dec.mbInfo[cast(u64) (mbY * sps.mbWidth + mbX - 1)].qp
        let qpAvg  = (qpP + cast(s32) info.qp + 1) >> 1
        let indexA = Math.clamp(qpAvg + cast(s32) info.alphaOffset, 0, 51)
        let indexB = Math.clamp(qpAvg + cast(s32) info.betaOffset, 0, 51)
        let alpha  = cast(s32) DeblockAlpha[cast(u64) indexA]
        let beta   = cast(s32) DeblockBeta[cast(u64) indexB]
        if alpha == 0 or beta == 0 do
            continue

        var pix = frame.pixLuma(mbX * 16 + edge * 4, mbY * 16)
        if strengths.bs[0] < 4 and strengths.bs[1] < 4 and strengths.bs[2] < 4 and strengths.bs[3] < 4
        {
            filterLumaWeakVertical(pix, frame.strideLuma, &strengths, indexA, alpha, beta)
        }
        else
        {
            for segment in 4's32
            {
                let bs = strengths.bs[cast(u64) segment]
                if bs == 0
                {
                    pix += 4 * frame.strideLuma
                    continue
                }

                for 4
                {
                    filterLuma(pix, 1, frame.strideLuma, bs, indexA, alpha, beta)
                    pix += frame.strideLuma
                }
            }
        }

        // The matching chroma edges sit at chroma columns 0 and 4.
        if edge == 0 or edge == 2
        {
            let qpcP    = chromaQpAt(dec, edge == 0 ? mbX - 1 : mbX, mbY)
            let qpcQ    = chromaQpAt(dec, mbX, mbY)
            let qpcAvg  = (qpcP + qpcQ + 1) >> 1
            let cIndexA = Math.clamp(qpcAvg + cast(s32) info.alphaOffset, 0, 51)
            let cIndexB = Math.clamp(qpcAvg + cast(s32) info.betaOffset, 0, 51)
            let cAlpha  = cast(s32) DeblockAlpha[cast(u64) cIndexA]
            let cBeta   = cast(s32) DeblockBeta[cast(u64) cIndexB]
            if cAlpha != 0 and cBeta != 0
            {
                for plane in 2'u32
                {
                    var pix = frame.pixChroma(plane, mbX * 8 + edge * 2, mbY * 8)
                    if strengths.bs[0] < 4 and strengths.bs[1] < 4 and strengths.bs[2] < 4 and strengths.bs[3] < 4
                    {
                        filterChromaWeakVertical(pix, frame.strideChroma, &strengths, cIndexA, cAlpha, cBeta)
                        continue
                    }

                    for segment in 4's32
                    {
                        let bs = strengths.bs[cast(u64) segment]
                        if bs == 0
                        {
                            pix += 2 * frame.strideChroma
                            continue
                        }

                        for 2
                        {
                            filterChroma(pix, 1, frame.strideChroma, bs, cIndexA, cAlpha, cBeta)
                            pix += frame.strideChroma
                        }
                    }
                }
            }
        }
    }

    // Horizontal edges: luma rows 0, 4, 8, 12.
    for edge in 4's32
    {
        var topUniform = false
        if edge == 0
        {
            if mbY == 0 do
                continue
            let topInfo = &dec.mbInfo[cast(u64) ((mbY - 1) * sps.mbWidth + mbX)]
            if info.deblockIdc == 2 and topInfo.sliceId != info.sliceId do
                continue
            topUniform = topInfo.uniform
        }
        elif info.transform8x8 and (edge & 1) != 0
        {
            continue
        }
        elif info.uniform
        {
            continue
        }

        var strengths: EdgeStrength
        var hasAny = false
        if edge == 0 and info.uniform and topUniform
        {
            let qIndex = cast(u64) (mbY * 4 * gw + mbX * 4)
            let bs     = edgeStrength(dec, qIndex - cast(u64) gw, qIndex, true, false, false, false, false)
            if bs == 0 do
                continue
            strengths.bs = [bs, bs, bs, bs]
            hasAny       = true
        }
        else
        {
            for segment in 4's32
            {
                let qx     = mbX * 4 + segment
                let qy     = mbY * 4 + edge
                let qIndex = cast(u64) (qy * gw + qx)
                let pIndex = cast(u64) ((qy - 1) * gw + qx)
                var pIntra = qIntra
                if edge == 0 do
                    pIntra = dec.mbInfo[cast(u64) ((mbY - 1) * sps.mbWidth + mbX)].class != MbClassInter
                let bs = edgeStrength(dec, pIndex, qIndex, edge == 0, pIntra, qIntra, dec.codedLuma[pIndex] != 0, dec.codedLuma[qIndex] != 0)
                strengths.bs[cast(u64) segment] = bs
                if bs != 0 do
                    hasAny = true
            }
        }

        if !hasAny do
            continue

        var qpP = cast(s32) info.qp
        if edge == 0 do
            qpP = cast(s32) dec.mbInfo[cast(u64) ((mbY - 1) * sps.mbWidth + mbX)].qp
        let qpAvg  = (qpP + cast(s32) info.qp + 1) >> 1
        let indexA = Math.clamp(qpAvg + cast(s32) info.alphaOffset, 0, 51)
        let indexB = Math.clamp(qpAvg + cast(s32) info.betaOffset, 0, 51)
        let alpha  = cast(s32) DeblockAlpha[cast(u64) indexA]
        let beta   = cast(s32) DeblockBeta[cast(u64) indexB]
        if alpha == 0 or beta == 0 do
            continue

        var pix = frame.pixLuma(mbX * 16, mbY * 16 + edge * 4)
        if strengths.bs[0] < 4 and strengths.bs[1] < 4 and strengths.bs[2] < 4 and strengths.bs[3] < 4
        {
            filterLumaWeakHorizontal(pix, frame.strideLuma, &strengths, indexA, alpha, beta)
        }
        else
        {
            for segment in 4's32
            {
                let bs = strengths.bs[cast(u64) segment]
                if bs == 0
                {
                    pix += 4
                    continue
                }

                for 4
                {
                    filterLuma(pix, frame.strideLuma, 1, bs, indexA, alpha, beta)
                    pix += 1
                }
            }
        }

        if edge == 0 or edge == 2
        {
            let qpcP    = chromaQpAt(dec, mbX, edge == 0 ? mbY - 1 : mbY)
            let qpcQ    = chromaQpAt(dec, mbX, mbY)
            let qpcAvg  = (qpcP + qpcQ + 1) >> 1
            let cIndexA = Math.clamp(qpcAvg + cast(s32) info.alphaOffset, 0, 51)
            let cIndexB = Math.clamp(qpcAvg + cast(s32) info.betaOffset, 0, 51)
            let cAlpha  = cast(s32) DeblockAlpha[cast(u64) cIndexA]
            let cBeta   = cast(s32) DeblockBeta[cast(u64) cIndexB]
            if cAlpha != 0 and cBeta != 0
            {
                for plane in 2'u32
                {
                    var pix = frame.pixChroma(plane, mbX * 8, mbY * 8 + edge * 2)
                    if strengths.bs[0] < 4 and strengths.bs[1] < 4 and strengths.bs[2] < 4 and strengths.bs[3] < 4
                    {
                        filterChromaWeakHorizontal(pix, frame.strideChroma, &strengths, cIndexA, cAlpha, cBeta)
                    }
                    else
                    {
                        for segment in 4's32
                        {
                            let bs = strengths.bs[cast(u64) segment]
                            if bs == 0
                            {
                                pix += 2
                                continue
                            }

                            for 2
                            {
                                filterChroma(pix, frame.strideChroma, 1, bs, cIndexA, cAlpha, cBeta)
                                pix += 1
                            }
                        }
                    }
                }
            }
        }
    }
}

// Filters one complete horizontal weak luma edge. The four strengths apply to four lanes
// each; zero-strength lanes remain unchanged, while strong edges keep the scalar path.
func filterLumaWeakHorizontal(pix: [*] u8, stride: u64, strengths: const *EdgeStrength, indexA, alpha, beta: s32)
{
    let p0Bytes = Simd.load(pix - stride)
    let q0Bytes = Simd.load(pix)
    let p1Bytes = Simd.load(pix - 2 * stride)
    let q1Bytes = Simd.load(pix + stride)
    let p2Bytes = Simd.load(pix - 3 * stride)
    let q2Bytes = Simd.load(pix + 2 * stride)

    let bs0    = cast(s16) strengths.bs[0]
    let bs1    = cast(s16) strengths.bs[1]
    let bs2    = cast(s16) strengths.bs[2]
    let bs3    = cast(s16) strengths.bs[3]
    let tc0    = bs0 == 0 ? 0's16 : cast(s16) DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs0 - 1)]
    let tc1    = bs1 == 0 ? 0's16 : cast(s16) DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs1 - 1)]
    let tc2    = bs2 == 0 ? 0's16 : cast(s16) DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs2 - 1)]
    let tc3    = bs3 == 0 ? 0's16 : cast(s16) DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs3 - 1)]
    let bsLow  = cast(Simd.S16x8) [bs0, bs0, bs0, bs0, bs1, bs1, bs1, bs1]
    let bsHigh = cast(Simd.S16x8) [bs2, bs2, bs2, bs2, bs3, bs3, bs3, bs3]
    let tcLow  = cast(Simd.S16x8) [tc0, tc0, tc0, tc0, tc1, tc1, tc1, tc1]
    let tcHigh = cast(Simd.S16x8) [tc2, tc2, tc2, tc2, tc3, tc3, tc3, tc3]
    let zeros  = Simd.splat(0's16)
    let alphas = Simd.splat(cast(s16) alpha)
    let betas  = Simd.splat(cast(s16) beta)

    let p0Low     = cast #bit(Simd.S16x8) Simd.widenLow(p0Bytes)
    let q0Low     = cast #bit(Simd.S16x8) Simd.widenLow(q0Bytes)
    let p1Low     = cast #bit(Simd.S16x8) Simd.widenLow(p1Bytes)
    let q1Low     = cast #bit(Simd.S16x8) Simd.widenLow(q1Bytes)
    let p2Low     = cast #bit(Simd.S16x8) Simd.widenLow(p2Bytes)
    let q2Low     = cast #bit(Simd.S16x8) Simd.widenLow(q2Bytes)
    let activeLow = (bsLow > zeros) & (Math.abs(p0Low - q0Low) < alphas) & (Math.abs(p1Low - p0Low) < betas) & (Math.abs(q1Low - q0Low) < betas)
    let apLow     = Math.abs(p2Low - p0Low) < betas
    let aqLow     = Math.abs(q2Low - q0Low) < betas
    let limitLow  = tcLow - cast #bit(Simd.S16x8) apLow - cast #bit(Simd.S16x8) aqLow
    var deltaLow  = (((q0Low - p0Low) << 2) + (p1Low - q1Low) + 4) >> 3
    deltaLow = Math.max(Math.min(deltaLow, limitLow), -limitLow)
    let averageLow = (p0Low + q0Low + 1) >> 1
    var pAdjustLow = (p2Low + averageLow - 2 * p1Low) >> 1
    var qAdjustLow = (q2Low + averageLow - 2 * q1Low) >> 1
    pAdjustLow = Math.max(Math.min(pAdjustLow, tcLow), -tcLow)
    qAdjustLow = Math.max(Math.min(qAdjustLow, tcLow), -tcLow)
    let newP0Low = Simd.select(activeLow, p0Low + deltaLow, p0Low)
    let newQ0Low = Simd.select(activeLow, q0Low - deltaLow, q0Low)
    let newP1Low = Simd.select(activeLow & apLow, p1Low + pAdjustLow, p1Low)
    let newQ1Low = Simd.select(activeLow & aqLow, q1Low + qAdjustLow, q1Low)

    let p0High     = cast #bit(Simd.S16x8) Simd.widenHigh(p0Bytes)
    let q0High     = cast #bit(Simd.S16x8) Simd.widenHigh(q0Bytes)
    let p1High     = cast #bit(Simd.S16x8) Simd.widenHigh(p1Bytes)
    let q1High     = cast #bit(Simd.S16x8) Simd.widenHigh(q1Bytes)
    let p2High     = cast #bit(Simd.S16x8) Simd.widenHigh(p2Bytes)
    let q2High     = cast #bit(Simd.S16x8) Simd.widenHigh(q2Bytes)
    let activeHigh = (bsHigh > zeros) & (Math.abs(p0High - q0High) < alphas) & (Math.abs(p1High - p0High) < betas) & (Math.abs(q1High - q0High) < betas)
    let apHigh     = Math.abs(p2High - p0High) < betas
    let aqHigh     = Math.abs(q2High - q0High) < betas
    let limitHigh  = tcHigh - cast #bit(Simd.S16x8) apHigh - cast #bit(Simd.S16x8) aqHigh
    var deltaHigh  = (((q0High - p0High) << 2) + (p1High - q1High) + 4) >> 3
    deltaHigh = Math.max(Math.min(deltaHigh, limitHigh), -limitHigh)
    let averageHigh = (p0High + q0High + 1) >> 1
    var pAdjustHigh = (p2High + averageHigh - 2 * p1High) >> 1
    var qAdjustHigh = (q2High + averageHigh - 2 * q1High) >> 1
    pAdjustHigh = Math.max(Math.min(pAdjustHigh, tcHigh), -tcHigh)
    qAdjustHigh = Math.max(Math.min(qAdjustHigh, tcHigh), -tcHigh)
    let newP0High = Simd.select(activeHigh, p0High + deltaHigh, p0High)
    let newQ0High = Simd.select(activeHigh, q0High - deltaHigh, q0High)
    let newP1High = Simd.select(activeHigh & apHigh, p1High + pAdjustHigh, p1High)
    let newQ1High = Simd.select(activeHigh & aqHigh, q1High + qAdjustHigh, q1High)

    Simd.store(pix - stride, Simd.packUnsigned(newP0Low, newP0High))
    Simd.store(pix, Simd.packUnsigned(newQ0Low, newQ0High))
    Simd.store(pix - 2 * stride, Simd.packUnsigned(newP1Low, newP1High))
    Simd.store(pix + stride, Simd.packUnsigned(newQ1Low, newQ1High))
}

// Filters the eight samples of one horizontal weak chroma edge. Each luma strength maps
// to two chroma lanes; strong edges retain their separate scalar formula.
func filterChromaWeakHorizontal(pix: [*] u8, stride: u64, strengths: const *EdgeStrength, indexA, alpha, beta: s32)
{
    let p0         = cast #bit(Simd.S16x8) Simd.widenLow(Simd.load(pix - stride))
    let q0         = cast #bit(Simd.S16x8) Simd.widenLow(Simd.load(pix))
    let p1         = cast #bit(Simd.S16x8) Simd.widenLow(Simd.load(pix - 2 * stride))
    let q1         = cast #bit(Simd.S16x8) Simd.widenLow(Simd.load(pix + stride))
    let bs0        = cast(s16) strengths.bs[0]
    let bs1        = cast(s16) strengths.bs[1]
    let bs2        = cast(s16) strengths.bs[2]
    let bs3        = cast(s16) strengths.bs[3]
    let tc0        = bs0 == 0 ? 0's16 : cast(s16) DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs0 - 1)] + 1
    let tc1        = bs1 == 0 ? 0's16 : cast(s16) DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs1 - 1)] + 1
    let tc2        = bs2 == 0 ? 0's16 : cast(s16) DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs2 - 1)] + 1
    let tc3        = bs3 == 0 ? 0's16 : cast(s16) DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs3 - 1)] + 1
    let strengths8 = cast(Simd.S16x8) [bs0, bs0, bs1, bs1, bs2, bs2, bs3, bs3]
    let limits     = cast(Simd.S16x8) [tc0, tc0, tc1, tc1, tc2, tc2, tc3, tc3]
    let zeros      = Simd.splat(0's16)
    let active     = (strengths8 > zeros) & (Math.abs(p0 - q0) < Simd.splat(cast(s16) alpha)) & (Math.abs(p1 - p0) < Simd.splat(cast(s16) beta)) & (Math.abs(q1 - q0) < Simd.splat(cast(s16) beta))
    var delta      = (((q0 - p0) << 2) + (p1 - q1) + 4) >> 3
    delta = Math.max(Math.min(delta, limits), -limits)
    Simd.storeLow8(pix - stride, Simd.packUnsigned(Simd.select(active, p0 + delta, p0), zeros))
    Simd.storeLow8(pix, Simd.packUnsigned(Simd.select(active, q0 - delta, q0), zeros))
}

// Stores the four 32-bit lanes of `columns` to four consecutive lines: lane `i` lands at
// `dst + i * stride`. This is the write-back of a transposed edge, four lines per vector.
#[Swag.Inline]
private func storeLines4(dst: [*] u8, stride: u64, columns: Simd.U32x4)
{
    (cast([*] u32) dst)[0]                = columns[0]
    (cast([*] u32) (dst + stride))[0]     = columns[1]
    (cast([*] u32) (dst + 2 * stride))[0] = columns[2]
    (cast([*] u32) (dst + 3 * stride))[0] = columns[3]
}

// Filters one complete vertical weak luma edge: the sixteen lines crossing the edge are
// transposed through a tile so that every sample position p3..q3 becomes one sixteen-lane
// row, the horizontal kernel filters that tile in place, and the four rows it changed are
// transposed back into the lines. `pix` sits on the first q sample of the first line.
func filterLumaWeakVertical(pix: [*] u8, stride: u64, strengths: const *EdgeStrength, indexA, alpha, beta: s32)
{
    const TileStride = 16'u64
    var tile: [8 * TileStride] u8 = undefined

    // Line k holds p3 p2 p1 p0 q0 q1 q2 q3 in its low eight bytes; the loads read eight more
    // bytes of the same line, which the padding of every plane keeps inside the row.
    let r0  = Simd.load(pix - 4)
    let r1  = Simd.load(pix - 4 + stride)
    let r2  = Simd.load(pix - 4 + 2 * stride)
    let r3  = Simd.load(pix - 4 + 3 * stride)
    let r4  = Simd.load(pix - 4 + 4 * stride)
    let r5  = Simd.load(pix - 4 + 5 * stride)
    let r6  = Simd.load(pix - 4 + 6 * stride)
    let r7  = Simd.load(pix - 4 + 7 * stride)
    let r8  = Simd.load(pix - 4 + 8 * stride)
    let r9  = Simd.load(pix - 4 + 9 * stride)
    let r10 = Simd.load(pix - 4 + 10 * stride)
    let r11 = Simd.load(pix - 4 + 11 * stride)
    let r12 = Simd.load(pix - 4 + 12 * stride)
    let r13 = Simd.load(pix - 4 + 13 * stride)
    let r14 = Simd.load(pix - 4 + 14 * stride)
    let r15 = Simd.load(pix - 4 + 15 * stride)

    // Bytes pair the lines, words group four, dwords eight, qwords all sixteen; each level
    // keeps p3..p0 in the low half of the interleave and q0..q3 in the high half.
    let a0 = cast #bit(Simd.U16x8) Simd.interleaveLow(r0, r1)
    let a1 = cast #bit(Simd.U16x8) Simd.interleaveLow(r2, r3)
    let a2 = cast #bit(Simd.U16x8) Simd.interleaveLow(r4, r5)
    let a3 = cast #bit(Simd.U16x8) Simd.interleaveLow(r6, r7)
    let a4 = cast #bit(Simd.U16x8) Simd.interleaveLow(r8, r9)
    let a5 = cast #bit(Simd.U16x8) Simd.interleaveLow(r10, r11)
    let a6 = cast #bit(Simd.U16x8) Simd.interleaveLow(r12, r13)
    let a7 = cast #bit(Simd.U16x8) Simd.interleaveLow(r14, r15)

    let b0 = cast #bit(Simd.U32x4) Simd.interleaveLow(a0, a1)
    let b1 = cast #bit(Simd.U32x4) Simd.interleaveHigh(a0, a1)
    let b2 = cast #bit(Simd.U32x4) Simd.interleaveLow(a2, a3)
    let b3 = cast #bit(Simd.U32x4) Simd.interleaveHigh(a2, a3)
    let b4 = cast #bit(Simd.U32x4) Simd.interleaveLow(a4, a5)
    let b5 = cast #bit(Simd.U32x4) Simd.interleaveHigh(a4, a5)
    let b6 = cast #bit(Simd.U32x4) Simd.interleaveLow(a6, a7)
    let b7 = cast #bit(Simd.U32x4) Simd.interleaveHigh(a6, a7)

    let c0 = cast #bit(Simd.U64x2) Simd.interleaveLow(b0, b2)
    let c1 = cast #bit(Simd.U64x2) Simd.interleaveHigh(b0, b2)
    let c2 = cast #bit(Simd.U64x2) Simd.interleaveLow(b4, b6)
    let c3 = cast #bit(Simd.U64x2) Simd.interleaveHigh(b4, b6)
    let c4 = cast #bit(Simd.U64x2) Simd.interleaveLow(b1, b3)
    let c5 = cast #bit(Simd.U64x2) Simd.interleaveHigh(b1, b3)
    let c6 = cast #bit(Simd.U64x2) Simd.interleaveLow(b5, b7)
    let c7 = cast #bit(Simd.U64x2) Simd.interleaveHigh(b5, b7)

    let rows = @dataof(tile)
    Simd.store(rows, cast #bit(Simd.U8x16) Simd.interleaveLow(c0, c2))
    Simd.store(rows + TileStride, cast #bit(Simd.U8x16) Simd.interleaveHigh(c0, c2))
    Simd.store(rows + 2 * TileStride, cast #bit(Simd.U8x16) Simd.interleaveLow(c1, c3))
    Simd.store(rows + 3 * TileStride, cast #bit(Simd.U8x16) Simd.interleaveHigh(c1, c3))
    Simd.store(rows + 4 * TileStride, cast #bit(Simd.U8x16) Simd.interleaveLow(c4, c6))
    Simd.store(rows + 5 * TileStride, cast #bit(Simd.U8x16) Simd.interleaveHigh(c4, c6))
    Simd.store(rows + 6 * TileStride, cast #bit(Simd.U8x16) Simd.interleaveLow(c5, c7))
    Simd.store(rows + 7 * TileStride, cast #bit(Simd.U8x16) Simd.interleaveHigh(c5, c7))

    filterLumaWeakHorizontal(rows + 4 * TileStride, TileStride, strengths, indexA, alpha, beta)

    // Only p1 p0 q0 q1 change: interleave those four rows back into one dword per line.
    let p1 = Simd.load(rows + 2 * TileStride)
    let p0 = Simd.load(rows + 3 * TileStride)
    let q0 = Simd.load(rows + 4 * TileStride)
    let q1 = Simd.load(rows + 5 * TileStride)
    let x0 = cast #bit(Simd.U16x8) Simd.interleaveLow(p1, p0)
    let x1 = cast #bit(Simd.U16x8) Simd.interleaveHigh(p1, p0)
    let y0 = cast #bit(Simd.U16x8) Simd.interleaveLow(q0, q1)
    let y1 = cast #bit(Simd.U16x8) Simd.interleaveHigh(q0, q1)
    storeLines4(pix - 2, stride, cast #bit(Simd.U32x4) Simd.interleaveLow(x0, y0))
    storeLines4(pix - 2 + 4 * stride, stride, cast #bit(Simd.U32x4) Simd.interleaveHigh(x0, y0))
    storeLines4(pix - 2 + 8 * stride, stride, cast #bit(Simd.U32x4) Simd.interleaveLow(x1, y1))
    storeLines4(pix - 2 + 12 * stride, stride, cast #bit(Simd.U32x4) Simd.interleaveHigh(x1, y1))
}

// Filters one complete vertical weak chroma edge the same way: eight lines of p1 p0 q0 q1
// become the four rows of a tile, the horizontal chroma kernel filters it, and the two
// rows it changed come back as one word per line.
func filterChromaWeakVertical(pix: [*] u8, stride: u64, strengths: const *EdgeStrength, indexA, alpha, beta: s32)
{
    const TileStride = 16'u64
    var tile:  [4 * TileStride] u8 = undefined
    var pairs: [8] u16             = undefined

    let r0 = Simd.load(pix - 2)
    let r1 = Simd.load(pix - 2 + stride)
    let r2 = Simd.load(pix - 2 + 2 * stride)
    let r3 = Simd.load(pix - 2 + 3 * stride)
    let r4 = Simd.load(pix - 2 + 4 * stride)
    let r5 = Simd.load(pix - 2 + 5 * stride)
    let r6 = Simd.load(pix - 2 + 6 * stride)
    let r7 = Simd.load(pix - 2 + 7 * stride)

    let a0 = cast #bit(Simd.U16x8) Simd.interleaveLow(r0, r1)
    let a1 = cast #bit(Simd.U16x8) Simd.interleaveLow(r2, r3)
    let a2 = cast #bit(Simd.U16x8) Simd.interleaveLow(r4, r5)
    let a3 = cast #bit(Simd.U16x8) Simd.interleaveLow(r6, r7)
    let b0 = cast #bit(Simd.U32x4) Simd.interleaveLow(a0, a1)
    let b1 = cast #bit(Simd.U32x4) Simd.interleaveLow(a2, a3)

    // c0 carries p1 then p0 in its two halves, c1 carries q0 then q1; the kernel reads eight
    // lanes from the low half of each tile row, so each half lands in a row of its own.
    let c0 = cast #bit(Simd.U64x2) Simd.interleaveLow(b0, b1)
    let c1 = cast #bit(Simd.U64x2) Simd.interleaveHigh(b0, b1)

    let rows = @dataof(tile)
    Simd.store(rows, cast #bit(Simd.U8x16) c0)
    Simd.store(rows + TileStride, cast #bit(Simd.U8x16) Simd.interleaveHigh(c0, c0))
    Simd.store(rows + 2 * TileStride, cast #bit(Simd.U8x16) c1)
    Simd.store(rows + 3 * TileStride, cast #bit(Simd.U8x16) Simd.interleaveHigh(c1, c1))

    filterChromaWeakHorizontal(rows + 2 * TileStride, TileStride, strengths, indexA, alpha, beta)

    // Only p0 q0 change: one word per line.
    let p0 = Simd.load(rows + TileStride)
    let q0 = Simd.load(rows + 2 * TileStride)
    Simd.store(cast([*] u8) @dataof(pairs), Simd.interleaveLow(p0, q0))
    for line in 8'u64 do
        (cast([*] u16) (pix - 1 + line * stride))[0] = pairs[line]
}

// Returns the chroma QP of one macroblock, with the blue-difference offset; the two chroma
// planes filter with the same strength, so one offset serves both.
private func chromaQpAt(dec: *Decoder, mbX, mbY: s32)->s32
{
    let qp = cast(s32) dec.mbInfo[cast(u64) (mbY * dec.sps!.mbWidth + mbX)].qp
    return cast(s32) ChromaQp[cast(u64) Math.clamp(qp + dec.pps!.chromaQpOffset[0], 0, 51)]
}

// Filters one luma line across an edge; `pix` sits on the first q sample, `step` walks
// across the edge and `lineStride` along it.
#[Swag.Inline]
func filterLuma(pix: [*] u8, step, lineStride: u64, bs: u32, indexA, alpha, beta: s32)
{
    discard lineStride
    let p0 = cast(s32) (pix - step)[0]
    let q0 = cast(s32) pix[0]
    let p1 = cast(s32) (pix - 2 * step)[0]
    let q1 = cast(s32) (pix + step)[0]

    // The three sample conditions of 8.7.2.2 fold into one sign test.
    if ((alpha - 1 - absS32(p0 - q0)) | (beta - 1 - absS32(p1 - p0)) | (beta - 1 - absS32(q1 - q0))) < 0 do
        return

    // `-1` when the side condition holds, `0` otherwise, so the count rides on a subtraction.
    let p2     = cast(s32) (pix - 3 * step)[0]
    let q2     = cast(s32) (pix + 2 * step)[0]
    let apMask = (absS32(p2 - p0) - beta) >> 31
    let aqMask = (absS32(q2 - q0) - beta) >> 31

    if bs < 4
    {
        let tc0 = cast(s32) DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs - 1)]
        let tc  = tc0 - apMask - aqMask

        let delta = clampS32((((q0 - p0) << 2) + (p1 - q1) + 4) >> 3, -tc, tc)
        (pix - step)[0] = clampPixel(p0 + delta)
        pix[0]          = clampPixel(q0 - delta)

        if apMask != 0
        {
            let adjust = clampS32((p2 + ((p0 + q0 + 1) >> 1) - 2 * p1) >> 1, -tc0, tc0)
            (pix - 2 * step)[0] = cast(u8) (p1 + adjust)
        }

        if aqMask != 0
        {
            let adjust = clampS32((q2 + ((p0 + q0 + 1) >> 1) - 2 * q1) >> 1, -tc0, tc0)
            (pix + step)[0] = cast(u8) (q1 + adjust)
        }

        return
    }

    // Strong filtering.
    let shortGap = absS32(p0 - q0) < (alpha >> 2) + 2
    if shortGap and apMask != 0
    {
        let p3 = cast(s32) (pix - 4 * step)[0]
        (pix - step)[0]     = cast(u8) ((p2 + 2 * p1 + 2 * p0 + 2 * q0 + q1 + 4) >> 3)
        (pix - 2 * step)[0] = cast(u8) ((p2 + p1 + p0 + q0 + 2) >> 2)
        (pix - 3 * step)[0] = cast(u8) ((2 * p3 + 3 * p2 + p1 + p0 + q0 + 4) >> 3)
    }
    else
    {
        (pix - step)[0] = cast(u8) ((2 * p1 + p0 + q1 + 2) >> 2)
    }

    if shortGap and aqMask != 0
    {
        let q3 = cast(s32) (pix + 3 * step)[0]
        pix[0]              = cast(u8) ((q2 + 2 * q1 + 2 * q0 + 2 * p0 + p1 + 4) >> 3)
        (pix + step)[0]     = cast(u8) ((q2 + q1 + q0 + p0 + 2) >> 2)
        (pix + 2 * step)[0] = cast(u8) ((2 * q3 + 3 * q2 + q1 + q0 + p0 + 4) >> 3)
    }
    else
    {
        pix[0] = cast(u8) ((2 * q1 + q0 + p1 + 2) >> 2)
    }
}

// Filters one chroma line across an edge.
#[Swag.Inline]
func filterChroma(pix: [*] u8, step, lineStride: u64, bs: u32, indexA, alpha, beta: s32)
{
    discard lineStride
    let p0 = cast(s32) (pix - step)[0]
    let q0 = cast(s32) pix[0]
    let p1 = cast(s32) (pix - 2 * step)[0]
    let q1 = cast(s32) (pix + step)[0]
    if ((alpha - 1 - absS32(p0 - q0)) | (beta - 1 - absS32(p1 - p0)) | (beta - 1 - absS32(q1 - q0))) < 0 do
        return

    if bs < 4
    {
        let tc    = cast(s32) DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs - 1)] + 1
        let delta = clampS32((((q0 - p0) << 2) + (p1 - q1) + 4) >> 3, -tc, tc)
        (pix - step)[0] = clampPixel(p0 + delta)
        pix[0]          = clampPixel(q0 - delta)
        return
    }

    (pix - step)[0] = cast(u8) ((2 * p1 + p0 + q1 + 2) >> 2)
    pix[0]          = cast(u8) ((2 * q1 + q0 + p1 + 2) >> 2)
}
