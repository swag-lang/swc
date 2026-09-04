//! Format: H.264/AVC decoder component.
//! Supported: Progressive 8-bit 4:2:0 Baseline, Main, and High-profile streams with CAVLC/CABAC, I/P/B slices, weighted prediction, cropping, reordering, and deblocking.
//! Not supported: Interlacing, non-4:2:0 chroma, bit depths above 8, slice groups, data partitioning, scalable/multiview extensions, and lossless transform bypass.
//! Role: This file owns prediction/residual combination and macroblock reconstruction.
//
#global namespace H264
#global internal

using Core, Core.Errors

const ReconstructionBands = 32'u32

struct ReconstructionJob
{
    using base: Jobs.Job
    decoder:    *Decoder?
    first:      u32
    end:        u32
}

private struct ReconstructionContext
{
    decoder:   *Decoder
    bandCount: u32
    failed:    u32
}

impl Decoder
{
    // Advances the loop filter and the published row progress after one macroblock row of the
    // current picture has been reconstructed.
    //
    // Intra prediction reads unfiltered neighbors, so the filter has to stay one row behind
    // reconstruction. Filtering row `R` is the last pass that touches row `R - 1`, which is
    // therefore final and can be padded and published as soon as row `R` is filtered.
    mtd completeReconstructedRow(reconstructedRow: s32)
    {
        if reconstructedRow >= 1 do
            .filterRow(reconstructedRow - 1)
    }

    // Filters one macroblock row and publishes the row above it as final.
    private mtd filterRow(mbRow: s32)
    {
        deblockRow(me, mbRow)
        if mbRow == 0 do
            return

        let frame = .current!
        frame.extendRowEdges(mbRow - 1)
        frame.publishProgress(mbRow)
    }

    // Filters and publishes what the row-by-row pipeline still owes once the last macroblock
    // row of the picture has been reconstructed.
    mtd completeInlinePicture()
    {
        let last  = cast(s32) .sps!.mbHeight - 1
        let frame = .current!
        .filterRow(last)
        frame.extendRowEdges(last)
        frame.extendBottomEdge()
        frame.publishProgress(frame.progressComplete())
    }

    // Starts every fully parsed row band without making the entropy thread wait for it.
    mtd scheduleParsedRows(parsedRows: u32)
    {
        while .pipelineScheduled < .pipelineBandCount
        {
            let band   = .pipelineScheduled
            let endRow = cast(u32) .sps!.mbHeight * (band + 1) / .pipelineBandCount
            if parsedRows < endRow do
                break

            let firstRow = cast(u32) .sps!.mbHeight * band / .pipelineBandCount
            let job      = &.pipelineJobs[band]
            job.decoder = me
            job.first   = firstRow * cast(u32) .sps!.mbWidth
            job.end     = endRow * cast(u32) .sps!.mbWidth
            job.lambda  = &runReconstructionJob
            job.data    = job
            Jobs.schedule(job)
            .pipelineScheduled += 1
        }
    }

    // The parser can fail after earlier bands have already started. Always join borrowed jobs
    // before decodeAccessUnit unwinds and its decoder storage can be reused or released.
    mtd waitReconstructionJobs()
    {
        for index in .pipelineScheduled do
            Jobs.wait(&.pipelineJobs[index])
    }

    // Reconstructs inter macroblocks in a few long row bands. Entropy parsing has already
    // published every motion and residual context, and inter prediction reads reference
    // pictures only, so bands write disjoint parts of the current picture. Intra blocks stay
    // in raster order because their prediction reads neighboring samples of this picture.
    mtd reconstructPicture() fail
    {
        let sps       = .sps!
        let mbCount   = cast(u32) (sps.mbWidth * sps.mbHeight)
        let bandCount = Math.min(Math.min(Jobs.workerCount(), ReconstructionBands), cast(u32) sps.mbHeight)

        if .pipelineBandCount > 0
        {
            .waitReconstructionJobs()
            if Atomic.get(&.pipelineFailed) != 0 do
                fail InvalidFormatError{"H.264 inter block has no reference picture"}
        }
        elif bandCount <= 1
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
                let state    = cast(*ReconstructionContext) data!
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
        else
        {
            .compensate(mb, frame)
            if mb.skipped do
                return
        }

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
                    var block: [64] s16
                    .dequant8x8(mb, quad, list, block.buffer)
                    addIdct8x8(dst, stride, block.buffer)
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

            if mb.nzLuma[cast(u64) raster] != 0 do
                .addLuma4x4Residual(mb, raster, dst, stride)

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
            let coeff = cast(s32) mb.residual!.lumaAc[base + scan]
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
            let coeff = cast(s32) mb.residual!.luma8[base + scan]
            if coeff == 0 do
                continue
            let position = cast(u64) Zigzag8[scan]
            block[position] = cast(s16) clampS32((coeff * cast(s32) pps.dequant8[list, cast(u64) mb.qp, position] + 32) >> 6, -32768, 32767)
        }
    }

    // Adds one dequantized 4x4 luma block to its prediction.
    #[Swag.Inline]
    mtd addLuma4x4Residual(mb: *Mb, raster: s32, destination: [*] u8, stride: u64)
    {
        let base = cast(u64) raster * 16
        if mb.nzLuma[cast(u64) raster] == 1 and mb.residual!.lumaAc[base] != 0
        {
            let list  = mb.class == MbClassInter ? 3'u64 : 0'u64
            let coeff = cast(s32) mb.residual!.lumaAc[base]
            let dc    = clampS32((coeff * cast(s32) .pps!.dequant4[list, cast(u64) mb.qp, 0] + 8) >> 4, -32768, 32767)
            addDc4x4(destination, stride, dc)
            return
        }

        var block: [16] s16
        .dequant4x4(mb, raster, 0, false, block.buffer)
        addIdct4x4(destination, stride, block.buffer)
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
                dcBlock[cast(u64) Zigzag4[scan]] = mb.residual!.lumaDc[scan]
            hadamard4x4(dcBlock.buffer)

            for raster in 16's32
            {
                let bx = raster & 3
                let by = raster >> 2
                let dc = (cast(s32) dcBlock[cast(u64) (by * 4 + bx)] * cast(s32) pps.dequant4[0, cast(u64) mb.qp, 0] + 32) >> 6
                var block: [16] s16
                .dequant4x4(mb, raster, dc, true, block.buffer)
                addIdct4x4(frame.pixLuma(mb.mbX * 16 + bx * 4, mb.mbY * 16 + by * 4), stride, block.buffer)
            }

            return
        }

        if mb.transform8x8
        {
            for quad in 4's32
            {
                if (mb.cbpLuma & (1'u32 << cast(u32) quad)) == 0 do
                    continue
                var block: [64] s16
                .dequant8x8(mb, quad, mb.class == MbClassInter ? 1'u64 : 0'u64, block.buffer)
                addIdct8x8(frame.pixLuma(mb.mbX * 16 + (quad & 1) * 8, mb.mbY * 16 + (quad >> 1) * 8), stride, block.buffer)
            }

            return
        }

        for raster in 16's32
        {
            if mb.nzLuma[cast(u64) raster] == 0 do
                continue
            let bx = raster & 3
            let by = raster >> 2
            .addLuma4x4Residual(mb, raster, frame.pixLuma(mb.mbX * 16 + bx * 4, mb.mbY * 16 + by * 4), stride)
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
            dc[index] = mb.residual!.chromaDc[cast(u64) plane * 4 + index]
        hadamard2x2(dc.buffer)

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
                    let coeff = cast(s32) mb.residual!.chromaAc[base + scan]
                    if coeff == 0 do
                        continue
                    let position = cast(u64) Zigzag4[scan]
                    coeffs[position] = cast(s16) clampS32((coeff * cast(s32) pps.dequant4[listDc, cast(u64) qpc, position] + 8) >> 4, -32768, 32767)
                    hasAny           = true
                }
            }

            if hasAny do
                addIdct4x4(frame.pixChroma(plane, mb.mbX * 8 + bx * 4, mb.mbY * 8 + by * 4), stride, coeffs.buffer)
        }
    }

    // Runs every motion-compensation job of an inter macroblock.
    mtd compensate(mb: *Mb, frame: *Frame) fail
    {
        var tempA: [16 * 16] u8
        var tempB: [16 * 16] u8

        // Skip and direct derivations partition uniformly: when every job carries the same
        // references and motion, one 16x16 job compensates the whole macroblock. The jobs of
        // a macroblock always tile it, so the merged job covers exactly the same samples.
        if mb.jobCount > 1
        {
            let first   = &mb.firstJob
            var uniform = true
            for jobIndex in 1'u32 until mb.jobCount
            {
                let job = .jobAt(mb, jobIndex)
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
            let job  = .jobAt(mb, jobIndex)
            let ref0 = job.refIdx[0] >= 0 ? .refs[0, cast(u64) job.refIdx[0]].frame : null
            let ref1 = job.refIdx[1] >= 0 ? .refs[1, cast(u64) job.refIdx[1]].frame : null
            if !ref0 and !ref1 do
                fail InvalidFormatError{"H.264 inter block has no reference picture"}
            if ref0 do
                .awaitJobReference(mb, job, 0, ref0!)
            if ref1 do
                .awaitJobReference(mb, job, 1, ref1!)

            // Luma.
            let lumaX   = mb.mbX * 16 + job.x
            let lumaY   = mb.mbY * 16 + job.y
            let lumaDst = frame.pixLuma(lumaX, lumaY)
            if ref0 and ref1
            {
                .mcLumaList(mb, job, 0, ref0!, tempA.buffer, 16)
                .mcLumaList(mb, job, 1, ref1!, tempB.buffer, 16)
                .combineBi(mb, job, tempA.buffer, tempB.buffer, lumaDst, frame.strideLuma, job.width, job.height, luma: true, plane: 0)
            }
            else
            {
                let list      = ref0 ? 0'u32 : 1'u32
                let reference = ref0 ? ref0! : ref1!
                if .useWeights
                {
                    .mcLumaList(mb, job, list, reference, tempA.buffer, 16)
                    let entry = &.refs[list, cast(u64) job.refIdx[list]]
                    weightUni(lumaDst, frame.strideLuma, tempA.buffer, 16, job.width, job.height, cast(s32) .lumaLog2Denom, entry.lumaWeight, entry.lumaOffset)
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
                    .mcChromaList(mb, job, 0, ref0!, plane, tempA.buffer, 16)
                    .mcChromaList(mb, job, 1, ref1!, plane, tempB.buffer, 16)
                    .combineBi(mb, job, tempA.buffer, tempB.buffer, chromaDst, frame.strideChroma, job.width / 2, job.height / 2, luma: false, plane: plane)
                }
                else
                {
                    let list      = ref0 ? 0'u32 : 1'u32
                    let reference = ref0 ? ref0! : ref1!
                    if .useWeights
                    {
                        .mcChromaList(mb, job, list, reference, plane, tempA.buffer, 16)
                        let entry  = &.refs[list, cast(u64) job.refIdx[list]]
                        let weight = plane == 0 ? entry.cbWeight : entry.crWeight
                        let offset = plane == 0 ? entry.cbOffset : entry.crOffset
                        weightUni(chromaDst, frame.strideChroma, tempA.buffer, 16, job.width / 2, job.height / 2, cast(s32) .chromaLog2Denom, weight, offset)
                    }
                    else
                    {
                        .mcChromaList(mb, job, list, reference, plane, chromaDst, frame.strideChroma)
                    }
                }
            }
        }
    }

    // Waits until a reference picture holds every row one job reads from it.
    //
    // The luma interpolator reads three rows past the block and the chroma one reads one row
    // past its half-resolution block; a window reaching past the picture is clamped onto the
    // last row, and the padding that carries it only exists once the picture is complete.
    mtd awaitJobReference(mb: *Mb, job: *McJob, list: u32, reference: *Frame) fail
    {
        let mvY        = cast(s32) job.mv[list, 1]
        let lumaLast   = mb.mbY * 16 + job.y + (mvY >> 2) + job.height + 3
        let chromaLast = 2 * (mb.mbY * 8 + job.y / 2 + (mvY >> 3) + job.height / 2) + 1
        let last       = Math.max(lumaLast, chromaLast)
        let rows       = last >= reference.mbHeight * 16 ? reference.progressComplete() : (Math.max(last, 0) >> 4) + 1

        let entry = &.refs[list, cast(u64) job.refIdx[list]]
        if rows <= entry.readyRows do
            return

        let observed = reference.awaitProgress(rows)
        if observed == FrameProgressFailed do
            fail InvalidFormatError{"H.264 reference picture did not decode"}
        entry.readyRows = observed
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

private func runReconstructionJob(data: *void?)
{
    let job = cast(*ReconstructionJob) data!
    for index in job.first until job.end
    {
        let mb = &job.decoder!.parsedMbs[index]
        if mb.class != MbClassInter do
            continue
        catch job.decoder!.pictureSlices[mb.sliceIndex].reconstructMb(mb) as reconstructionError
        if reconstructionError != null do
            Atomic.exchange(&job.decoder!.pipelineFailed, 1)
    }
}
