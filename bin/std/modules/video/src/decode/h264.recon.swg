#global namespace H264
#global internal

using Core, Core.Errors

private const ReconstructionBands = 4'u32

private struct ReconstructionContext
{
    decoder:   *Decoder
    bandCount: u32
    failed:    u32
}

impl Decoder
{
    // Reconstructs inter macroblocks in a few long row bands. Entropy parsing has already
    // published every motion and residual context, and inter prediction reads reference
    // pictures only, so bands write disjoint parts of the current picture. Intra blocks stay
    // in raster order because their prediction reads neighboring samples of this picture.
    mtd reconstructPicture() fail
    {
        let sps       = .sps!
        let mbCount   = cast(u32) (sps.mbWidth * sps.mbHeight)
        let bandCount = Math.min(Math.min(Jobs.workerCount(), ReconstructionBands), cast(u32) sps.mbHeight)

        if bandCount <= 1
        {
            for index in mbCount
            {
                let mb = &.parsedMbs[index]
                if mb.class == MbClassInter do
                    .pictureSlices[mb.sliceIndex].reconstructMb(mb)
            }
        }
        else
        {
            var context = ReconstructionContext{me, bandCount}
            Jobs.parallelFor(bandCount, &context)
            {
                let state = cast(*ReconstructionContext) data!
                let firstRow = cast(u32) state.decoder.sps!.mbHeight * index / state.bandCount
                let endRow   = cast(u32) state.decoder.sps!.mbHeight * (index + 1) / state.bandCount
                let first    = firstRow * cast(u32) state.decoder.sps!.mbWidth
                let end      = endRow * cast(u32) state.decoder.sps!.mbWidth
                for mbIndex in first until end
                {
                    let mb = &state.decoder.parsedMbs[mbIndex]
                    if mb.class != MbClassInter do
                        continue
                    catch state.decoder.pictureSlices[mb.sliceIndex].reconstructMb(mb) as reconstructionError
                    if reconstructionError != null do
                        Atomic.exchange(&state.failed, 1)
                }
            }

            if Atomic.get(&context.failed) != 0 do
                fail InvalidFormatError{"H.264 inter block has no reference picture"}
        }

        for index in mbCount
        {
            let mb = &.parsedMbs[index]
            if mb.class != MbClassInter do
                .pictureSlices[mb.sliceIndex].reconstructMb(mb)
        }
    }
}

impl Slice
{
    // Reconstructs one parsed macroblock into the current picture.
    mtd reconstructMb(mb: *Mb) fail
    {
        if mb.class == MbClassIPcm do
            return

        let dec     = .dec!
        let pps     = .pps!
        let frame   = dec.current!
        let isIntra = mb.class != MbClassInter

        if mb.class == MbClassIntra16x16 or mb.class == MbClassIntra4x4 or mb.class == MbClassIntra8x8 do
            .predictIntraLuma(mb, frame)
        else do
            .compensate(mb, frame)

        if mb.class != MbClassIntra4x4 and mb.class != MbClassIntra8x8 do
            .addLumaResidual(mb, frame)

        // Chroma prediction and residual.
        let qpCb = cast(s32) ChromaQp[cast(u64) Math.clamp(mb.qp + pps.chromaQpOffset[0], 0, 51)]
        let qpCr = cast(s32) ChromaQp[cast(u64) Math.clamp(mb.qp + pps.chromaQpOffset[1], 0, 51)]
        if isIntra
        {
            let hasLeft = .intraMbAvailable(mb.mbX - 1, mb.mbY)
            let hasTop  = .intraMbAvailable(mb.mbX, mb.mbY - 1)
            for plane in 2'u32 do
                intraPredictChroma(mb.chromaMode, frame.pixChroma(plane, mb.mbX * 8, mb.mbY * 8), frame.strideChroma, hasLeft, hasTop)
        }

        for plane in 2'u32 do
            .addChromaResidual(mb, frame, plane, plane == 0 ? qpCb : qpCr)
    }

    // Reports whether a macroblock's samples can serve intra prediction.
    mtd const intraMbAvailable(mbX, mbY: s32)->bool
    {
        if !.mbAvailable(mbX, mbY) do
            return false
        if !.pps!.constrainedIntra do
            return true
        return .mbInfoAt(mbX, mbY).class != MbClassInter
    }

    // Runs the intra luma prediction, interleaved with the residual for the 4x4 and 8x8
    // classes whose later blocks predict from earlier reconstructed ones.
    mtd predictIntraLuma(mb: *Mb, frame: *Frame)
    {
        let dec           = .dec!
        let stride        = frame.strideLuma
        let hasLeftMb     = .intraMbAvailable(mb.mbX - 1, mb.mbY)
        let hasTopMb      = .intraMbAvailable(mb.mbX, mb.mbY - 1)
        let hasTopLeftMb  = .intraMbAvailable(mb.mbX - 1, mb.mbY - 1)
        let hasTopRightMb = .intraMbAvailable(mb.mbX + 1, mb.mbY - 1)

        if mb.class == MbClassIntra16x16
        {
            intraPredict16x16(mb.i16Mode, frame.pixLuma(mb.mbX * 16, mb.mbY * 16), stride, hasLeftMb, hasTopMb)
            return
        }

        if mb.class == MbClassIntra8x8
        {
            let list = 0'u64
            for quad in 4's32
            {
                let qx         = quad & 1
                let qy         = quad >> 1
                let dst        = frame.pixLuma(mb.mbX * 16 + qx * 8, mb.mbY * 16 + qy * 8)
                let hasLeft    = qx > 0 ? true : hasLeftMb
                let hasTop     = qy > 0 ? true : hasTopMb
                var hasTopLeft = true
                if qx == 0 and qy == 0 do
                    hasTopLeft = hasTopLeftMb
                elif qx == 0 do
                    hasTopLeft = hasLeftMb
                elif qy == 0 do
                    hasTopLeft = hasTopMb
                var hasTopRight = false
                if qy == 0 do
                    hasTopRight = qx == 0 ? hasTopMb : hasTopRightMb
                elif qx == 0 do
                    hasTopRight = true

                let mode = cast(u32) mb.intraModes[cast(u64) (qy * 2 * 4 + qx * 2)]
                intraPredict8x8(mode, dst, stride, hasLeft, hasTop, hasTopLeft, hasTopRight)

                if mb.codedBlocks[cast(u64) (qy * 2 * 4 + qx * 2)] != 0
                {
                    var block: [64] s16 = undefined
                    .dequant8x8(mb, quad, list, @dataof(block))
                    addIdct8x8(dst, stride, @dataof(block))
                }
            }

            return
        }

        // Intra 4x4, in coded block order.
        for coded in 16's32
        {
            let raster     = cast(s32) CodedToRaster4[coded]
            let bx         = raster & 3
            let by         = raster >> 2
            let dst        = frame.pixLuma(mb.mbX * 16 + bx * 4, mb.mbY * 16 + by * 4)
            let hasLeft    = bx > 0 ? true : hasLeftMb
            let hasTop     = by > 0 ? true : hasTopMb
            var hasTopLeft = true
            if bx == 0 and by == 0 do
                hasTopLeft = hasTopLeftMb
            elif bx == 0 do
                hasTopLeft = hasLeftMb
            elif by == 0 do
                hasTopLeft = hasTopMb
            var hasTopRight = false
            if by == 0 do
                hasTopRight = bx < 3 ? hasTopMb : hasTopRightMb
            elif bx < 3 do
                hasTopRight = ((mb.decodedMask >> cast(u32) ((by - 1) * 4 + bx + 1)) & 1) != 0

            let mode = cast(u32) mb.intraModes[cast(u64) raster]
            intraPredict4x4(mode, dst, stride, hasLeft, hasTop, hasTopLeft, hasTopRight)

            if mb.nzLuma[cast(u64) raster] != 0
            {
                var block: [16] s16 = undefined
                .dequant4x4(mb, raster, 0, false, @dataof(block))
                addIdct4x4(dst, stride, @dataof(block))
            }

            mb.decodedMask |= 1'u32 << cast(u32) raster
        }
    }

    // Dequantizes one 4x4 luma block into raster order; `dcValue` replaces position zero for
    // the Intra_16x16 class.
    mtd dequant4x4(mb: *Mb, raster: s32, dcValue: s32, hasDc: bool, block: [*] s16)
    {
        let dec  = .dec!
        let pps  = .pps!
        let list = mb.class == MbClassInter ? 3'u64 : 0'u64
        for index in 16'u64 do
            block[index] = 0

        let base  = cast(u64) raster * 16
        let start = hasDc ? 1'u64 : 0'u64
        for scan in start until 16
        {
            let coeff = cast(s32) mb.lumaAc[base + scan]
            if coeff == 0 do
                continue
            let position = cast(u64) Zigzag4[scan]
            block[position] = cast(s16) clampS32((coeff * cast(s32) pps.dequant4[list, cast(u64) mb.qp, position] + 8) >> 4, -32768, 32767)
        }

        if hasDc do
            block[0] = cast(s16) clampS32(dcValue, -32768, 32767)
    }

    // Dequantizes one 8x8 luma block into raster order.
    mtd dequant8x8(mb: *Mb, quad: s32, list: u64, block: [*] s16)
    {
        let dec = .dec!
        let pps = .pps!
        for index in 64'u64 do
            block[index] = 0

        let base = cast(u64) quad * 64
        for scan in 64'u64
        {
            let coeff = cast(s32) mb.luma8[base + scan]
            if coeff == 0 do
                continue
            let position = cast(u64) Zigzag8[scan]
            block[position] = cast(s16) clampS32((coeff * cast(s32) pps.dequant8[list, cast(u64) mb.qp, position] + 32) >> 6, -32768, 32767)
        }
    }

    // Adds the luma residual of a macroblock whose prediction is already in place.
    mtd addLumaResidual(mb: *Mb, frame: *Frame)
    {
        let dec    = .dec!
        let pps    = .pps!
        let stride = frame.strideLuma

        if mb.class == MbClassIntra16x16
        {
            // The DC coefficients travel through their own transform before joining each
            // block's AC residual.
            var dcBlock: [16] s16
            for scan in 16'u64 do
                dcBlock[cast(u64) Zigzag4[scan]] = mb.lumaDc[scan]
            hadamard4x4(@dataof(dcBlock))

            for raster in 16's32
            {
                let bx              = raster & 3
                let by              = raster >> 2
                let dc              = (cast(s32) dcBlock[cast(u64) (by * 4 + bx)] * cast(s32) pps.dequant4[0, cast(u64) mb.qp, 0] + 32) >> 6
                var block: [16] s16 = undefined
                .dequant4x4(mb, raster, dc, true, @dataof(block))
                addIdct4x4(frame.pixLuma(mb.mbX * 16 + bx * 4, mb.mbY * 16 + by * 4), stride, @dataof(block))
            }

            return
        }

        if mb.transform8x8
        {
            for quad in 4's32
            {
                if (mb.cbpLuma & (1'u32 << cast(u32) quad)) == 0 do
                    continue
                var block: [64] s16 = undefined
                .dequant8x8(mb, quad, mb.class == MbClassInter ? 1'u64 : 0'u64, @dataof(block))
                addIdct8x8(frame.pixLuma(mb.mbX * 16 + (quad & 1) * 8, mb.mbY * 16 + (quad >> 1) * 8), stride, @dataof(block))
            }

            return
        }

        for raster in 16's32
        {
            if mb.nzLuma[cast(u64) raster] == 0 do
                continue
            let bx              = raster & 3
            let by              = raster >> 2
            var block: [16] s16 = undefined
            .dequant4x4(mb, raster, 0, false, @dataof(block))
            addIdct4x4(frame.pixLuma(mb.mbX * 16 + bx * 4, mb.mbY * 16 + by * 4), stride, @dataof(block))
        }
    }

    // Adds one chroma plane's residual: transformed DC plus per-block AC.
    mtd addChromaResidual(mb: *Mb, frame: *Frame, plane: u32, qpc: s32)
    {
        let dec    = .dec!
        let pps    = .pps!
        let stride = frame.strideChroma
        if mb.cbpChroma == 0 do
            return

        let isIntra = mb.class != MbClassInter
        var listDc  = isIntra ? 1'u64 : 4'u64
        if plane == 1 do
            listDc += 1

        var dc: [4] s16
        for index in 4'u64 do
            dc[index] = mb.chromaDc[cast(u64) plane * 4 + index]
        hadamard2x2(@dataof(dc))

        for block in 4's32
        {
            let bx      = block & 1
            let by      = block >> 1
            let dcValue = (cast(s32) dc[cast(u64) (by * 2 + bx)] * cast(s32) pps.dequant4[listDc, cast(u64) qpc, 0]) >> 5

            var coeffs: [16] s16
            coeffs[0] = cast(s16) clampS32(dcValue, -32768, 32767)
            var hasAny = dcValue != 0
            if mb.cbpChroma == 2
            {
                let base = cast(u64) plane * 64 + cast(u64) block * 16
                for scan in 1'u64 until 16
                {
                    let coeff = cast(s32) mb.chromaAc[base + scan]
                    if coeff == 0 do
                        continue
                    let position = cast(u64) Zigzag4[scan]
                    coeffs[position] = cast(s16) clampS32((coeff * cast(s32) pps.dequant4[listDc, cast(u64) qpc, position] + 8) >> 4, -32768, 32767)
                    hasAny           = true
                }
            }

            if hasAny do
                addIdct4x4(frame.pixChroma(plane, mb.mbX * 8 + bx * 4, mb.mbY * 8 + by * 4), stride, @dataof(coeffs))
        }
    }

    // Runs every motion-compensation job of an inter macroblock.
    mtd compensate(mb: *Mb, frame: *Frame) fail
    {
        var tempA: [16 * 16] u8 = undefined
        var tempB: [16 * 16] u8 = undefined

        // Skip and direct derivations partition uniformly: when every job carries the same
        // references and motion, one 16x16 job compensates the whole macroblock. The jobs of
        // a macroblock always tile it, so the merged job covers exactly the same samples.
        if mb.jobCount > 1
        {
            let first   = &mb.jobs[0]
            var uniform = true
            for jobIndex in 1'u32 until mb.jobCount
            {
                let job = &mb.jobs[jobIndex]
                if job.refIdx[0] != first.refIdx[0] or job.refIdx[1] != first.refIdx[1] or job.mv[0, 0] != first.mv[0, 0] or job.mv[0, 1] != first.mv[0, 1] or job.mv[1, 0] != first.mv[1, 0] or job.mv[1, 1] != first.mv[1, 1]
                {
                    uniform = false
                    break
                }
            }

            if uniform
            {
                first.x      = 0
                first.y      = 0
                first.width  = 16
                first.height = 16
                mb.jobCount  = 1
            }
        }

        for jobIndex in mb.jobCount
        {
            let job  = &mb.jobs[jobIndex]
            let ref0 = job.refIdx[0] >= 0 ? .refs[0, cast(u64) job.refIdx[0]].frame : null
            let ref1 = job.refIdx[1] >= 0 ? .refs[1, cast(u64) job.refIdx[1]].frame : null
            if !ref0 and !ref1 do
                fail InvalidFormatError{"H.264 inter block has no reference picture"}

            // Luma.
            let lumaX   = mb.mbX * 16 + job.x
            let lumaY   = mb.mbY * 16 + job.y
            let lumaDst = frame.pixLuma(lumaX, lumaY)
            if ref0 and ref1
            {
                .mcLumaList(mb, job, 0, ref0!, @dataof(tempA), 16)
                .mcLumaList(mb, job, 1, ref1!, @dataof(tempB), 16)
                .combineBi(mb, job, @dataof(tempA), @dataof(tempB), lumaDst, frame.strideLuma, job.width, job.height, luma: true, plane: 0)
            }
            else
            {
                let list      = ref0 ? 0'u32 : 1'u32
                let reference = ref0 ? ref0! : ref1!
                if .useWeights
                {
                    .mcLumaList(mb, job, list, reference, @dataof(tempA), 16)
                    let entry = &.refs[list, cast(u64) job.refIdx[list]]
                    weightUni(lumaDst, frame.strideLuma, @dataof(tempA), 16, job.width, job.height, cast(s32) .lumaLog2Denom, entry.lumaWeight, entry.lumaOffset)
                }
                else
                {
                    .mcLumaList(mb, job, list, reference, lumaDst, frame.strideLuma)
                }
            }

            // Chroma, both planes at half resolution.
            for plane in 2'u32
            {
                let chromaX   = mb.mbX * 8 + job.x / 2
                let chromaY   = mb.mbY * 8 + job.y / 2
                let chromaDst = frame.pixChroma(plane, chromaX, chromaY)
                if ref0 and ref1
                {
                    .mcChromaList(mb, job, 0, ref0!, plane, @dataof(tempA), 16)
                    .mcChromaList(mb, job, 1, ref1!, plane, @dataof(tempB), 16)
                    .combineBi(mb, job, @dataof(tempA), @dataof(tempB), chromaDst, frame.strideChroma, job.width / 2, job.height / 2, luma: false, plane: plane)
                }
                else
                {
                    let list      = ref0 ? 0'u32 : 1'u32
                    let reference = ref0 ? ref0! : ref1!
                    if .useWeights
                    {
                        .mcChromaList(mb, job, list, reference, plane, @dataof(tempA), 16)
                        let entry  = &.refs[list, cast(u64) job.refIdx[list]]
                        let weight = plane == 0 ? entry.cbWeight : entry.crWeight
                        let offset = plane == 0 ? entry.cbOffset : entry.crOffset
                        weightUni(chromaDst, frame.strideChroma, @dataof(tempA), 16, job.width / 2, job.height / 2, cast(s32) .chromaLog2Denom, weight, offset)
                    }
                    else
                    {
                        .mcChromaList(mb, job, list, reference, plane, chromaDst, frame.strideChroma)
                    }
                }
            }
        }
    }

    // Interpolates the luma of one job for one list.
    mtd mcLumaList(mb: *Mb, job: *McJob, list: u32, reference: *Frame, dst: [*] u8, dstStride: u64)
    {
        let mvX = cast(s32) job.mv[list, 0]
        let mvY = cast(s32) job.mv[list, 1]
        let x   = mb.mbX * 16 + job.x + (mvX >> 2)
        let y   = mb.mbY * 16 + job.y + (mvY >> 2)
        mcLuma(dst, dstStride, reference, x, y, mvX & 3, mvY & 3, job.width, job.height)
    }

    // Interpolates one chroma plane of one job for one list.
    mtd mcChromaList(mb: *Mb, job: *McJob, list: u32, reference: *Frame, plane: u32, dst: [*] u8, dstStride: u64)
    {
        let mvX = cast(s32) job.mv[list, 0]
        let mvY = cast(s32) job.mv[list, 1]
        let x   = mb.mbX * 8 + job.x / 2 + (mvX >> 3)
        let y   = mb.mbY * 8 + job.y / 2 + (mvY >> 3)
        mcChroma(dst, dstStride, reference, plane, x, y, mvX & 7, mvY & 7, job.width / 2, job.height / 2)
    }

    // Combines the two list predictions of one bidirectional job.
    mtd combineBi(mb: *Mb, job: *McJob, src0, src1: [*] u8, dst: [*] u8, dstStride: u64, width, height: s32, luma: bool, plane: u32)
    {
        if .useWeights
        {
            let entry0 = &.refs[0, cast(u64) job.refIdx[0]]
            let entry1 = &.refs[1, cast(u64) job.refIdx[1]]
            var denom, w0, w1, o0, o1: s32
            if luma
            {
                denom = cast(s32) .lumaLog2Denom
                w0    = entry0.lumaWeight
                w1    = entry1.lumaWeight
                o0    = entry0.lumaOffset
                o1    = entry1.lumaOffset
            }
            else
            {
                denom = cast(s32) .chromaLog2Denom
                w0    = plane == 0 ? entry0.cbWeight : entry0.crWeight
                w1    = plane == 0 ? entry1.cbWeight : entry1.crWeight
                o0    = plane == 0 ? entry0.cbOffset : entry0.crOffset
                o1    = plane == 0 ? entry1.cbOffset : entry1.crOffset
            }

            weightBi(dst, dstStride, src0, src1, 16, width, height, denom, w0, w1, o0, o1)
            return
        }

        if .useImplicit
        {
            let w1 = cast(s32) .implicitW1[cast(u64) job.refIdx[0], cast(u64) job.refIdx[1]]
            weightBi(dst, dstStride, src0, src1, 16, width, height, 5, 64 - w1, w1, 0, 0)
            return
        }

        averagePlanes(dst, dstStride, src0, 16, src1, 16, width, height)
    }
}
