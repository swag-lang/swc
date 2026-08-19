#global namespace H264
#global internal

using Core

// The deblocking filter, section 8.7, for progressive frames: every macroblock filters its
// vertical edges left to right, then its horizontal edges top to bottom, in place, in raster
// macroblock order.

// Filters the whole decoded picture.
func deblockPicture(dec: *Decoder)
{
    let sps = dec.sps!
    for mbY in sps.mbHeight
    {
        for mbX in sps.mbWidth do
            deblockMb(dec, mbX, mbY)
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

    if Math.abs(pL0x - qL0x) >= 4 or Math.abs(pL0y - qL0y) >= 4 do
        return false
    if Math.abs(pL1x - qL1x) >= 4 or Math.abs(pL1y - qL1y) >= 4 do
        return false
    return true
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
        if edge == 0
        {
            if mbX == 0 do
                continue
            let leftInfo = &dec.mbInfo[cast(u64) (mbY * sps.mbWidth + mbX - 1)]
            if info.deblockIdc == 2 and leftInfo.sliceId != info.sliceId do
                continue
        }
        elif info.transform8x8 and (edge & 1) != 0
        {
            continue
        }

        var strengths: EdgeStrength
        var hasAny = false
        for segment in 4's32
        {
            let qx = mbX * 4 + edge
            let qy = mbY * 4 + segment
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

        for row in 16's32
        {
            let bs = strengths.bs[cast(u64) (row >> 2)]
            if bs == 0 do
                continue
            filterLuma(frame.pixLuma(mbX * 16 + edge * 4, mbY * 16 + row), 1, frame.strideLuma, bs, indexA, alpha, beta)
        }

        // The matching chroma edges sit at chroma columns 0 and 4.
        if edge == 0 or edge == 2
        {
            let qpcP = chromaQpAt(dec, edge == 0 ? mbX - 1 : mbX, mbY)
            let qpcQ = chromaQpAt(dec, mbX, mbY)
            let qpcAvg  = (qpcP + qpcQ + 1) >> 1
            let cIndexA = Math.clamp(qpcAvg + cast(s32) info.alphaOffset, 0, 51)
            let cIndexB = Math.clamp(qpcAvg + cast(s32) info.betaOffset, 0, 51)
            let cAlpha  = cast(s32) DeblockAlpha[cast(u64) cIndexA]
            let cBeta   = cast(s32) DeblockBeta[cast(u64) cIndexB]
            if cAlpha != 0 and cBeta != 0
            {
                for plane in 2'u32
                {
                    for row in 8's32
                    {
                        let bs = strengths.bs[cast(u64) (row >> 1)]
                        if bs == 0 do
                            continue
                        filterChroma(frame.pixChroma(plane, mbX * 8 + edge * 2, mbY * 8 + row), 1, frame.strideChroma, bs, cIndexA, cAlpha, cBeta)
                    }
                }
            }
        }
    }

    // Horizontal edges: luma rows 0, 4, 8, 12.
    for edge in 4's32
    {
        if edge == 0
        {
            if mbY == 0 do
                continue
            let topInfo = &dec.mbInfo[cast(u64) ((mbY - 1) * sps.mbWidth + mbX)]
            if info.deblockIdc == 2 and topInfo.sliceId != info.sliceId do
                continue
        }
        elif info.transform8x8 and (edge & 1) != 0
        {
            continue
        }

        var strengths: EdgeStrength
        var hasAny = false
        for segment in 4's32
        {
            let qx = mbX * 4 + segment
            let qy = mbY * 4 + edge
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

        for column in 16's32
        {
            let bs = strengths.bs[cast(u64) (column >> 2)]
            if bs == 0 do
                continue
            filterLuma(frame.pixLuma(mbX * 16 + column, mbY * 16 + edge * 4), frame.strideLuma, 1, bs, indexA, alpha, beta)
        }

        if edge == 0 or edge == 2
        {
            let qpcP = chromaQpAt(dec, mbX, edge == 0 ? mbY - 1 : mbY)
            let qpcQ = chromaQpAt(dec, mbX, mbY)
            let qpcAvg  = (qpcP + qpcQ + 1) >> 1
            let cIndexA = Math.clamp(qpcAvg + cast(s32) info.alphaOffset, 0, 51)
            let cIndexB = Math.clamp(qpcAvg + cast(s32) info.betaOffset, 0, 51)
            let cAlpha  = cast(s32) DeblockAlpha[cast(u64) cIndexA]
            let cBeta   = cast(s32) DeblockBeta[cast(u64) cIndexB]
            if cAlpha != 0 and cBeta != 0
            {
                for plane in 2'u32
                {
                    for column in 8's32
                    {
                        let bs = strengths.bs[cast(u64) (column >> 1)]
                        if bs == 0 do
                            continue
                        filterChroma(frame.pixChroma(plane, mbX * 8 + column, mbY * 8 + edge * 2), frame.strideChroma, 1, bs, cIndexA, cAlpha, cBeta)
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
private func filterLuma(pix: [*] u8, step, lineStride: u64, bs: u32, indexA, alpha, beta: s32)
{
    discard lineStride
    let p0 = cast(s32) (pix - step)[0]
    let q0 = cast(s32) pix[0]
    let p1 = cast(s32) (pix - 2 * step)[0]
    let q1 = cast(s32) (pix + step)[0]
    if Math.abs(p0 - q0) >= alpha or Math.abs(p1 - p0) >= beta or Math.abs(q1 - q0) >= beta do
        return

    let p2 = cast(s32) (pix - 3 * step)[0]
    let q2 = cast(s32) (pix + 2 * step)[0]
    let ap = Math.abs(p2 - p0) < beta
    let aq = Math.abs(q2 - q0) < beta

    if bs < 4
    {
        let tc0 = cast(s32) DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs - 1)]
        var tc  = tc0
        if ap do
            tc += 1
        if aq do
            tc += 1

        let delta = Math.clamp((((q0 - p0) << 2) + (p1 - q1) + 4) >> 3, -tc, tc)
        (pix - step)[0] = clampPixel(p0 + delta)
        pix[0]          = clampPixel(q0 - delta)

        if ap
        {
            let adjust = Math.clamp((p2 + ((p0 + q0 + 1) >> 1) - 2 * p1) >> 1, -tc0, tc0)
            (pix - 2 * step)[0] = cast(u8) (p1 + adjust)
        }

        if aq
        {
            let adjust = Math.clamp((q2 + ((p0 + q0 + 1) >> 1) - 2 * q1) >> 1, -tc0, tc0)
            (pix + step)[0] = cast(u8) (q1 + adjust)
        }

        return
    }

    // Strong filtering.
    let shortGap = Math.abs(p0 - q0) < (alpha >> 2) + 2
    if shortGap and ap
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

    if shortGap and aq
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
private func filterChroma(pix: [*] u8, step, lineStride: u64, bs: u32, indexA, alpha, beta: s32)
{
    discard lineStride
    let p0 = cast(s32) (pix - step)[0]
    let q0 = cast(s32) pix[0]
    let p1 = cast(s32) (pix - 2 * step)[0]
    let q1 = cast(s32) (pix + step)[0]
    if Math.abs(p0 - q0) >= alpha or Math.abs(p1 - p0) >= beta or Math.abs(q1 - q0) >= beta do
        return

    if bs < 4
    {
        let tc = cast(s32) DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs - 1)] + 1
        let delta = Math.clamp((((q0 - p0) << 2) + (p1 - q1) + 4) >> 3, -tc, tc)
        (pix - step)[0] = clampPixel(p0 + delta)
        pix[0]          = clampPixel(q0 - delta)
        return
    }

    (pix - step)[0] = cast(u8) ((2 * p1 + p0 + q1 + 2) >> 2)
    pix[0]          = cast(u8) ((2 * q1 + q0 + p1 + 2) >> 2)
}
