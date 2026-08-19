#global namespace H264
#global internal

using Core

// The deblocking filter, section 8.7, for progressive frames: every macroblock filters its
// vertical edges left to right, then its horizontal edges top to bottom, in place, in raster
// macroblock order.

private const DeblockLanes = 4'u32

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
                    let required = cast(u32) Math.min(mbX + 2, width)
                    while Atomic.get(state.rowProgress + cast(u64) mbY - 1) < required {}
                }

                deblockMb(state.decoder, mbX, mbY)
                Atomic.exchange(state.rowProgress + cast(u64) mbY, cast(u32) mbX + 1)
            }

            mbY += cast(s32) state.laneCount
        }
    }
}

// Boundary strengths of one macroblock edge, one per 4-sample segment.
private struct EdgeStrength
{
    bs: [4] u32
}

// Computes the strength of one 4x4 block edge between blocks `p` and `q`, section 8.7.2.1.
private func edgeStrength(dec: *Decoder, pIndex, qIndex: u64, mbEdge, pIntra, qIntra, pCoded, qCoded: bool)->u32
{
    if pIntra or qIntra do
        return mbEdge ? 4'u32 : 3'u32
    if pCoded or qCoded do
        return 2

    // Reference and motion comparison.
    let p0 = dec.refPocL0[pIndex]
    let p1 = dec.refPocL1[pIndex]
    let q0 = dec.refPocL0[qIndex]
    let q1 = dec.refPocL1[qIndex]

    let straight = p0 == q0 and p1 == q1
    let crossed  = p0 == q1 and p1 == q0
    if !straight and !crossed do
        return 1

    if straight and mvClose(dec, pIndex, qIndex, false) do
        return 0
    if crossed and mvClose(dec, pIndex, qIndex, true) do
        return 0
    return 1
}

// Reports whether every motion vector pair differs by less than one full sample.
private func mvClose(dec: *Decoder, pIndex, qIndex: u64, crossed: bool)->bool
{
    let pL0x = cast(s32) dec.mvL0[pIndex * 2]
    let pL0y = cast(s32) dec.mvL0[pIndex * 2 + 1]
    let pL1x = cast(s32) dec.mvL1[pIndex * 2]
    let pL1y = cast(s32) dec.mvL1[pIndex * 2 + 1]
    var qL0x, qL0y, qL1x, qL1y: s32
    if crossed
    {
        qL0x = cast(s32) dec.mvL1[qIndex * 2]
        qL0y = cast(s32) dec.mvL1[qIndex * 2 + 1]
        qL1x = cast(s32) dec.mvL0[qIndex * 2]
        qL1y = cast(s32) dec.mvL0[qIndex * 2 + 1]
    }
    else
    {
        qL0x = cast(s32) dec.mvL0[qIndex * 2]
        qL0y = cast(s32) dec.mvL0[qIndex * 2 + 1]
        qL1x = cast(s32) dec.mvL1[qIndex * 2]
        qL1y = cast(s32) dec.mvL1[qIndex * 2 + 1]
    }

    // All four differences must stay below one full sample; OR-ing `3 - abs` keeps the test
    // branchless: any excursion sets the sign bit of the combined word.
    return ((3 - absS32(pL0x - qL0x)) | (3 - absS32(pL0y - qL0y)) | (3 - absS32(pL1x - qL1x)) | (3 - absS32(pL1y - qL1y))) >= 0
}

// Filters every edge of one macroblock.
private func deblockMb(dec: *Decoder, mbX, mbY: s32)
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
private func filterLuma(pix: [*] u8, step, lineStride: u64, bs: u32, indexA, alpha, beta: s32)
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
private func filterChroma(pix: [*] u8, step, lineStride: u64, bs: u32, indexA, alpha, beta: s32)
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
