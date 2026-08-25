//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns the luma and chroma sample interpolation filters.
//
#global namespace Hevc
#global internal

using Core

impl Decoder
{
    // Predicts one inter block into the current picture, clause 8.5.3.3.
    //
    // Each list is interpolated into its own buffer at the internal precision the standard keeps
    // between the two stages, and the two are combined once, so a bi-predicted block rounds once
    // rather than twice.
    mtd interPredict(xPb, yPb, nPbW, nPbH: s32, motion: const *PuMotion)
    {
        let sps = .activeSps!
        for component in 3'u32
        {
            let scale  = component == 0 ? 1's32 : 2's32
            let width  = cast(u32) (nPbW / scale)
            let height = cast(u32) (nPbH / scale)
            let x      = xPb / scale
            let y      = yPb / scale
            if !width or !height do
                continue

            for list in ListCount
            {
                if (cast(u32) motion.predFlags & (1'u32 << list)) == 0 do
                    continue

                let refIdx = cast(u32) motion.refIdx[list]
                let frame  = .refList.frames[list, refIdx]
                if !frame do
                    continue

                if !component do
                    .interpolateLuma(frame!, x, y, width, height, motion.mv[list, 0], motion.mv[list, 1], list)
                else do
                    .interpolateChroma(frame!, component, x, y, width, height, motion.mv[list, 0], motion.mv[list, 1], list)
            }

            .combinePrediction(component, x, y, width, height, motion, sps)
        }
    }

    // Copies the reference samples one interpolation reads, clamping to the picture edges.
    //
    // A motion vector may point arbitrarily far outside the picture, and the standard answers
    // every such sample with the nearest edge one; gathering first turns that into one bounded
    // copy instead of a clamp inside the filter loop.
    private mtd const gatherReference(frame: *Frame, component: u32, xInt, yInt: s32, width, height, before, taps: u32, destination: [*] u16, destinationStride: u64)
    {
        var plane: const [*] u16 = undefined
        var stride: u64
        var planeWidth, planeHeight: s32
        if !component
        {
            plane       = frame.luma.buffer!
            stride      = frame.strideLuma
            planeWidth  = cast(s32) frame.width
            planeHeight = cast(s32) frame.height
        }
        else
        {
            plane       = component == 1 ? frame.chromaB.buffer! : frame.chromaR.buffer!
            stride      = frame.strideChroma
            planeWidth  = cast(s32) frame.chromaWidth
            planeHeight = cast(s32) frame.chromaHeight
        }

        let rows    = height + taps - 1
        let columns = width + taps - 1
        for row in rows
        {
            let sourceY = Math.clamp(yInt - cast(s32) before + cast(s32) row, 0, planeHeight - 1)
            let line    = plane + cast(u64) (sourceY + cast(s32) FramePadding) * stride + cast(u64) FramePadding
            let out     = destination + cast(u64) row * destinationStride

            // The common case is a block entirely inside the picture, where the clamp is a copy.
            let firstX = xInt - cast(s32) before
            if firstX >= 0 and firstX + cast(s32) columns <= planeWidth
            {
                Memory.copy(out, line + cast(u64) firstX, cast(u64) columns * #sizeof(u16))
                continue
            }

            for column in columns do
                out[column] = line[cast(u64) Math.clamp(firstX + cast(s32) column, 0, planeWidth - 1)]
        }
    }

    // Interpolates one luma prediction block, clause 8.5.3.3.3.2.
    private mtd interpolateLuma(frame: *Frame, x, y: s32, width, height: u32, mvX, mvY: s16, list: u32)
    {
        let sps      = .activeSps!
        let bitDepth = sps.bitDepthLuma
        let shift1   = Math.min(4'u32, bitDepth - 8)
        let shift2   = 6'u32
        let shift3   = Math.max(2'u32, 14 - bitDepth)

        let xInt  = x + (cast(s32) mvX >> 2)
        let yInt  = y + (cast(s32) mvY >> 2)
        let xFrac = cast(u32) (cast(s32) mvX & 3)
        let yFrac = cast(u32) (cast(s32) mvY & 3)

        var reference: [MaxRefSide * MaxRefSide] u16 = undefined
        let referenceStride = cast(u64) MaxRefSide
        .gatherReference(frame, 0, xInt, yInt, width, height, 3, 8, &reference[0], referenceStride)

        if !xFrac and !yFrac
        {
            for row in height
            {
                let source = cast(u64) (row + 3) * referenceStride + 3
                for column in width do
                    .predBuffer[list, row * width + column] = cast(s16) (cast(s32) reference[source + cast(u64) column] << shift3)
            }

            return
        }

        if !yFrac
        {
            for row in height
            {
                let source = cast(u64) (row + 3) * referenceStride
                for column in width
                {
                    var sum = 0's32
                    for tap in 8'u32 do
                        sum += cast(s32) LumaFilter[xFrac, tap] * cast(s32) reference[source + cast(u64) (column + tap)]
                    .predBuffer[list, row * width + column] = cast(s16) (sum >> shift1)
                }
            }

            return
        }

        if !xFrac
        {
            for row in height
            {
                for column in width
                {
                    var sum = 0's32
                    for tap in 8'u32 do
                        sum += cast(s32) LumaFilter[yFrac, tap] * cast(s32) reference[cast(u64) (row + tap) * referenceStride + cast(u64) (column + 3)]
                    .predBuffer[list, row * width + column] = cast(s16) (sum >> shift1)
                }
            }

            return
        }

        // Both directions: the horizontal filter runs over every row the vertical one reads.
        var intermediate: [MaxRefSide * MaxPredSide] s16 = undefined
        for row in height + 7
        {
            let source = cast(u64) row * referenceStride
            for column in width
            {
                var sum = 0's32
                for tap in 8'u32 do
                    sum += cast(s32) LumaFilter[xFrac, tap] * cast(s32) reference[source + cast(u64) (column + tap)]
                intermediate[cast(u64) row * cast(u64) width + cast(u64) column] = cast(s16) (sum >> shift1)
            }
        }

        for row in height
        {
            for column in width
            {
                var sum = 0's32
                for tap in 8'u32 do
                    sum += cast(s32) LumaFilter[yFrac, tap] * cast(s32) intermediate[cast(u64) (row + tap) * cast(u64) width + cast(u64) column]
                .predBuffer[list, row * width + column] = cast(s16) (sum >> shift2)
            }
        }
    }

    // Interpolates one chroma prediction block, clause 8.5.3.3.3.3.
    private mtd interpolateChroma(frame: *Frame, component: u32, x, y: s32, width, height: u32, mvX, mvY: s16, list: u32)
    {
        let sps      = .activeSps!
        let bitDepth = sps.bitDepthChroma
        let shift1   = Math.min(4'u32, bitDepth - 8)
        let shift2   = 6'u32
        let shift3   = Math.max(2'u32, 14 - bitDepth)

        // In 4:2:0 the chroma vector is the luma one read in eighths of a chroma sample.
        let xInt  = x + (cast(s32) mvX >> 3)
        let yInt  = y + (cast(s32) mvY >> 3)
        let xFrac = cast(u32) (cast(s32) mvX & 7)
        let yFrac = cast(u32) (cast(s32) mvY & 7)

        var reference: [MaxRefSide * MaxRefSide] u16 = undefined
        let referenceStride = cast(u64) MaxRefSide
        .gatherReference(frame, component, xInt, yInt, width, height, 1, 4, &reference[0], referenceStride)

        if !xFrac and !yFrac
        {
            for row in height
            {
                let source = cast(u64) (row + 1) * referenceStride + 1
                for column in width do
                    .predBuffer[list, row * width + column] = cast(s16) (cast(s32) reference[source + cast(u64) column] << shift3)
            }

            return
        }

        if !yFrac
        {
            for row in height
            {
                let source = cast(u64) (row + 1) * referenceStride
                for column in width
                {
                    var sum = 0's32
                    for tap in 4'u32 do
                        sum += cast(s32) ChromaFilter[xFrac, tap] * cast(s32) reference[source + cast(u64) (column + tap)]
                    .predBuffer[list, row * width + column] = cast(s16) (sum >> shift1)
                }
            }

            return
        }

        if !xFrac
        {
            for row in height
            {
                for column in width
                {
                    var sum = 0's32
                    for tap in 4'u32 do
                        sum += cast(s32) ChromaFilter[yFrac, tap] * cast(s32) reference[cast(u64) (row + tap) * referenceStride + cast(u64) (column + 1)]
                    .predBuffer[list, row * width + column] = cast(s16) (sum >> shift1)
                }
            }

            return
        }

        var intermediate: [MaxRefSide * MaxPredSide] s16 = undefined
        for row in height + 3
        {
            let source = cast(u64) row * referenceStride
            for column in width
            {
                var sum = 0's32
                for tap in 4'u32 do
                    sum += cast(s32) ChromaFilter[xFrac, tap] * cast(s32) reference[source + cast(u64) (column + tap)]
                intermediate[cast(u64) row * cast(u64) width + cast(u64) column] = cast(s16) (sum >> shift1)
            }
        }

        for row in height
        {
            for column in width
            {
                var sum = 0's32
                for tap in 4'u32 do
                    sum += cast(s32) ChromaFilter[yFrac, tap] * cast(s32) intermediate[cast(u64) (row + tap) * cast(u64) width + cast(u64) column]
                .predBuffer[list, row * width + column] = cast(s16) (sum >> shift2)
            }
        }
    }

    // Combines the interpolated lists into the picture, clause 8.5.3.3.4.
    private mtd combinePrediction(component: u32, x, y: s32, width, height: u32, motion: const *PuMotion, sps: const *Sps)
    {
        let header   = &.header
        let frame    = .current!
        let bitDepth = component == 0 ? sps.bitDepthLuma : sps.bitDepthChroma
        let maximum  = cast(s32) ((1'u32 << bitDepth) - 1)

        var destination: [*] u16 = undefined
        var stride: u64
        if !component
        {
            destination = frame.lumaAtMutable(x, y)
            stride      = frame.strideLuma
        }
        else
        {
            destination = frame.chromaAtMutable(component - 1, x, y)
            stride      = frame.strideChroma
        }

        let usesL0 = (motion.predFlags & 1) != 0
        let usesL1 = (motion.predFlags & 2) != 0

        let weighted = header.hasWeights and ((header.sliceType == SliceTypeP and .activePps!.weightedPred) or (header.sliceType == SliceTypeB and .activePps!.weightedBipred))
        if weighted
        {
            .combineWeighted(destination, stride, component, width, height, motion, usesL0, usesL1, bitDepth, maximum)
            return
        }

        let shift1  = Math.max(2'u32, 14 - bitDepth)
        let shift2  = Math.max(3'u32, 15 - bitDepth)
        let offset1 = 1's32 << (shift1 - 1)
        let offset2 = 1's32 << (shift2 - 1)

        if usesL0 and usesL1
        {
            for row in height
            {
                let out = destination + cast(u64) row * stride
                for column in width
                {
                    let index = row * width + column
                    let sum   = cast(s32) .predBuffer[0, index] + cast(s32) .predBuffer[1, index] + offset2
                    out[column] = cast(u16) Math.clamp(sum >> shift2, 0, maximum)
                }
            }

            return
        }

        let list = usesL0 ? 0'u32 : 1'u32
        for row in height
        {
            let out = destination + cast(u64) row * stride
            for column in width
            {
                let value = cast(s32) .predBuffer[list, row * width + column] + offset1
                out[column] = cast(u16) Math.clamp(value >> shift1, 0, maximum)
            }
        }
    }

    // Combines the interpolated lists with the weights the slice header carries, clause 8.5.3.3.4.3.
    private mtd combineWeighted(destination: [*] u16, stride: u64, component, width, height: u32, motion: const *PuMotion, usesL0, usesL1: bool, bitDepth: u32, maximum: s32)
    {
        let header    = &.header
        let shift1    = Math.max(2'u32, 14 - bitDepth)
        let denom     = component == 0 ? header.lumaLog2WeightDenom : header.chromaLog2WeightDenom
        let log2Wd    = denom + shift1
        let offsetShift = bitDepth - 8

        var weight: [ListCount] s32
        var offset: [ListCount] s32
        for list in ListCount
        {
            if (cast(u32) motion.predFlags & (1'u32 << list)) == 0 do
                continue
            let entry = &header.weights[list, cast(u32) motion.refIdx[list]]
            if !component
            {
                weight[list] = entry.lumaWeight
                offset[list] = entry.lumaOffset << offsetShift
            }
            else
            {
                weight[list] = entry.chromaWeight[component - 1]
                offset[list] = entry.chromaOffset[component - 1] << offsetShift
            }
        }

        if usesL0 and usesL1
        {
            let rounding = (offset[0] + offset[1] + 1) << log2Wd
            for row in height
            {
                let out = destination + cast(u64) row * stride
                for column in width
                {
                    let index = row * width + column
                    let sum   = cast(s32) .predBuffer[0, index] * weight[0] + cast(s32) .predBuffer[1, index] * weight[1] + rounding
                    out[column] = cast(u16) Math.clamp(sum >> (log2Wd + 1), 0, maximum)
                }
            }

            return
        }

        let list     = usesL0 ? 0'u32 : 1'u32
        let rounding = 1's32 << (log2Wd - 1)
        for row in height
        {
            let out = destination + cast(u64) row * stride
            for column in width
            {
                let value = ((cast(s32) .predBuffer[list, row * width + column] * weight[list] + rounding) >> log2Wd) + offset[list]
                out[column] = cast(u16) Math.clamp(value, 0, maximum)
            }
        }
    }
}
