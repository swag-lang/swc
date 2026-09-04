//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns the luma and chroma sample interpolation filters.
//
#global namespace Hevc
#global internal

using Core, Core.Math

const LumaPairWeights: [4, 4] Simd.S16x8 = [[cast(Simd.S16x8) [0's16, 0, 0, 0, 0, 0, 0, 0], cast(Simd.S16x8) [0's16, 64, 0, 64, 0, 64, 0, 64], cast(Simd.S16x8) [0's16, 0, 0, 0, 0, 0, 0, 0], cast(Simd.S16x8) [0's16, 0, 0, 0, 0, 0, 0, 0]], [cast(Simd.S16x8) [-1's16, 4, -1, 4, -1, 4, -1, 4], cast(Simd.S16x8) [-10's16, 58, -10, 58, -10, 58, -10, 58], cast(Simd.S16x8) [17's16, -5, 17, -5, 17, -5, 17, -5], cast(Simd.S16x8) [1's16, 0, 1, 0, 1, 0, 1, 0]], [cast(Simd.S16x8) [-1's16, 4, -1, 4, -1, 4, -1, 4], cast(Simd.S16x8) [-11's16, 40, -11, 40, -11, 40, -11, 40], cast(Simd.S16x8) [40's16, -11, 40, -11, 40, -11, 40, -11], cast(Simd.S16x8) [4's16, -1, 4, -1, 4, -1, 4, -1]], [cast(Simd.S16x8) [0's16, 1, 0, 1, 0, 1, 0, 1], cast(Simd.S16x8) [-5's16, 17, -5, 17, -5, 17, -5, 17], cast(Simd.S16x8) [58's16, -10, 58, -10, 58, -10, 58, -10], cast(Simd.S16x8) [4's16, -1, 4, -1, 4, -1, 4, -1]]]

const ChromaPairWeights: [8, 2] Simd.S16x8 = [[cast(Simd.S16x8) [0's16, 64, 0, 64, 0, 64, 0, 64], cast(Simd.S16x8) [0's16, 0, 0, 0, 0, 0, 0, 0]], [cast(Simd.S16x8) [-2's16, 58, -2, 58, -2, 58, -2, 58], cast(Simd.S16x8) [10's16, -2, 10, -2, 10, -2, 10, -2]], [cast(Simd.S16x8) [-4's16, 54, -4, 54, -4, 54, -4, 54], cast(Simd.S16x8) [16's16, -2, 16, -2, 16, -2, 16, -2]], [cast(Simd.S16x8) [-6's16, 46, -6, 46, -6, 46, -6, 46], cast(Simd.S16x8) [28's16, -4, 28, -4, 28, -4, 28, -4]], [cast(Simd.S16x8) [-4's16, 36, -4, 36, -4, 36, -4, 36], cast(Simd.S16x8) [36's16, -4, 36, -4, 36, -4, 36, -4]], [cast(Simd.S16x8) [-4's16, 28, -4, 28, -4, 28, -4, 28], cast(Simd.S16x8) [46's16, -6, 46, -6, 46, -6, 46, -6]], [cast(Simd.S16x8) [-2's16, 16, -2, 16, -2, 16, -2, 16], cast(Simd.S16x8) [54's16, -4, 54, -4, 54, -4, 54, -4]], [cast(Simd.S16x8) [-2's16, 10, -2, 10, -2, 10, -2, 10], cast(Simd.S16x8) [58's16, -2, 58, -2, 58, -2, 58, -2]]]

// The taps of one filter, in the pair layout `pmaddwd` sums, read once for a whole block.
//
// The fraction a block is filtered at does not change inside it, and reading the table in the
// loop costs an address computation per pair per group of samples plus the register that holds
// it - which is a register the accumulators then spill to the frame to make room for.
struct LumaTaps
{
    pair0, pair1, pair2, pair3: Simd.S16x8
}

struct ChromaTaps
{
    pair0, pair1: Simd.S16x8
}

#[Swag.Inline]
private func lumaTaps(fraction: u32)->LumaTaps
{
    return {LumaPairWeights[fraction, 0], LumaPairWeights[fraction, 1], LumaPairWeights[fraction, 2], LumaPairWeights[fraction, 3]}
}

#[Swag.Inline]
private func chromaTaps(fraction: u32)->ChromaTaps
{
    return {ChromaPairWeights[fraction, 0], ChromaPairWeights[fraction, 1]}
}

#[Swag.Inline]
private func storeLow4(destination: [*] s16, value: Simd.S16x8)
{
    (cast([*] u64) destination)[0] = (cast #bit(Simd.U64x2) value)[0]
}

#[Swag.Inline]
private func storeLow4(destination: [*] u16, value: Simd.U16x8)
{
    (cast([*] u64) destination)[0] = (cast #bit(Simd.U64x2) value)[0]
}

#[Swag.Inline]
private func filterLumaUnsigned4(source: const [*] u16, stride: u64, taps: LumaTaps, shift: u32)->Simd.S16x8
{
    var sum = Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(Simd.load(source), Simd.load(source + stride)), taps.pair0)
    sum += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(Simd.load(source + 2 * stride), Simd.load(source + 3 * stride)), taps.pair1)
    sum += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(Simd.load(source + 4 * stride), Simd.load(source + 5 * stride)), taps.pair2)
    sum += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(Simd.load(source + 6 * stride), Simd.load(source + 7 * stride)), taps.pair3)
    return Simd.packSigned(sum >> shift, sum >> shift)
}

#[Swag.Inline]
private func filterLumaSigned4(source: const [*] s16, stride: u64, taps: LumaTaps, shift: u32)->Simd.S16x8
{
    var sum = Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U16x8) Simd.load(source), cast #bit(Simd.U16x8) Simd.load(source + stride)), taps.pair0)
    sum += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U16x8) Simd.load(source + 2 * stride), cast #bit(Simd.U16x8) Simd.load(source + 3 * stride)), taps.pair1)
    sum += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U16x8) Simd.load(source + 4 * stride), cast #bit(Simd.U16x8) Simd.load(source + 5 * stride)), taps.pair2)
    sum += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U16x8) Simd.load(source + 6 * stride), cast #bit(Simd.U16x8) Simd.load(source + 7 * stride)), taps.pair3)
    return Simd.packSigned(sum >> shift, sum >> shift)
}

#[Swag.Inline]
private func filterChromaUnsigned4(source: const [*] u16, stride: u64, taps: ChromaTaps, shift: u32)->Simd.S16x8
{
    var sum = Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(Simd.load(source), Simd.load(source + stride)), taps.pair0)
    sum += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(Simd.load(source + 2 * stride), Simd.load(source + 3 * stride)), taps.pair1)
    return Simd.packSigned(sum >> shift, sum >> shift)
}

#[Swag.Inline]
private func filterChromaSigned4(source: const [*] s16, stride: u64, taps: ChromaTaps, shift: u32)->Simd.S16x8
{
    var sum = Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U16x8) Simd.load(source), cast #bit(Simd.U16x8) Simd.load(source + stride)), taps.pair0)
    sum += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U16x8) Simd.load(source + 2 * stride), cast #bit(Simd.U16x8) Simd.load(source + 3 * stride)), taps.pair1)
    return Simd.packSigned(sum >> shift, sum >> shift)
}

#[Swag.Inline]
private func filterLumaUnsigned8(source: const [*] u16, stride: u64, taps: LumaTaps, shift: u32)->Simd.S16x8
{
    var first0  = Simd.load(source)
    var second0 = Simd.load(source + stride)
    var low     = Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(first0, second0), taps.pair0)
    var high    = Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(first0, second0), taps.pair0)
    var first1  = Simd.load(source + 2 * stride)
    var second1 = Simd.load(source + 3 * stride)
    low  += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(first1, second1), taps.pair1)
    high += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(first1, second1), taps.pair1)
    var first2  = Simd.load(source + 4 * stride)
    var second2 = Simd.load(source + 5 * stride)
    low  += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(first2, second2), taps.pair2)
    high += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(first2, second2), taps.pair2)
    var first3  = Simd.load(source + 6 * stride)
    var second3 = Simd.load(source + 7 * stride)
    low  += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(first3, second3), taps.pair3)
    high += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(first3, second3), taps.pair3)
    return Simd.packSigned(low >> shift, high >> shift)
}

#[Swag.Inline]
private func filterLumaSigned8(source: const [*] s16, stride: u64, taps: LumaTaps, shift: u32)->Simd.S16x8
{
    var first0  = cast #bit(Simd.U16x8) Simd.load(source)
    var second0 = cast #bit(Simd.U16x8) Simd.load(source + stride)
    var low     = Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(first0, second0), taps.pair0)
    var high    = Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(first0, second0), taps.pair0)
    var first1  = cast #bit(Simd.U16x8) Simd.load(source + 2 * stride)
    var second1 = cast #bit(Simd.U16x8) Simd.load(source + 3 * stride)
    low  += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(first1, second1), taps.pair1)
    high += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(first1, second1), taps.pair1)
    var first2  = cast #bit(Simd.U16x8) Simd.load(source + 4 * stride)
    var second2 = cast #bit(Simd.U16x8) Simd.load(source + 5 * stride)
    low  += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(first2, second2), taps.pair2)
    high += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(first2, second2), taps.pair2)
    var first3  = cast #bit(Simd.U16x8) Simd.load(source + 6 * stride)
    var second3 = cast #bit(Simd.U16x8) Simd.load(source + 7 * stride)
    low  += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(first3, second3), taps.pair3)
    high += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(first3, second3), taps.pair3)
    return Simd.packSigned(low >> shift, high >> shift)
}

#[Swag.Inline]
private func filterChromaUnsigned8(source: const [*] u16, stride: u64, taps: ChromaTaps, shift: u32)->Simd.S16x8
{
    var first0  = Simd.load(source)
    var second0 = Simd.load(source + stride)
    var low     = Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(first0, second0), taps.pair0)
    var high    = Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(first0, second0), taps.pair0)
    var first1  = Simd.load(source + 2 * stride)
    var second1 = Simd.load(source + 3 * stride)
    low  += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(first1, second1), taps.pair1)
    high += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(first1, second1), taps.pair1)
    return Simd.packSigned(low >> shift, high >> shift)
}

#[Swag.Inline]
private func filterChromaSigned8(source: const [*] s16, stride: u64, taps: ChromaTaps, shift: u32)->Simd.S16x8
{
    var first0  = cast #bit(Simd.U16x8) Simd.load(source)
    var second0 = cast #bit(Simd.U16x8) Simd.load(source + stride)
    var low     = Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(first0, second0), taps.pair0)
    var high    = Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(first0, second0), taps.pair0)
    var first1  = cast #bit(Simd.U16x8) Simd.load(source + 2 * stride)
    var second1 = cast #bit(Simd.U16x8) Simd.load(source + 3 * stride)
    low  += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(first1, second1), taps.pair1)
    high += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(first1, second1), taps.pair1)
    return Simd.packSigned(low >> shift, high >> shift)
}

impl Decoder
{
    // Predicts one inter block into the current picture, clause 8.5.3.3.
    //
    // Each list is interpolated into its own buffer at the internal precision the standard keeps
    // between the two stages, and the two are combined once, so a bi-predicted block rounds once
    // rather than twice.
    mtd interPredict(xPb, yPb, nPbW, nPbH: s32, motion: const *PuMotion)
    {
        let sps      = .activeSps!
        let usesL0   = (motion.predFlags & 1) != 0
        let usesL1   = (motion.predFlags & 2) != 0
        let weighted = .header.hasWeights and ((.header.sliceType == SliceTypeP and .activePps!.weightedPred) or (.header.sliceType == SliceTypeB and .activePps!.weightedBipred))
        for component in 3'u32
        {
            let scale  = component == 0 ? 1's32 : 2's32
            let width  = cast(u32) (nPbW / scale)
            let height = cast(u32) (nPbH / scale)
            let x      = xPb / scale
            let y      = yPb / scale
            if !width or !height do
                continue

            // A signaled weight table often carries the identity weights. Those samples follow
            // the same direct paths as an unweighted prediction.
            var identityWeights = !weighted
            if weighted
            {
                identityWeights = true
                let denominator = component == 0 ? .header.lumaLog2WeightDenom : .header.chromaLog2WeightDenom
                for list in ListCount where (cast(u32) motion.predFlags & (1'u32 << list)) != 0
                {
                    let entry = &.header.weights[list, cast(u32) motion.refIdx[list]]
                    if (!component and (entry.lumaWeight != 1 << denominator or entry.lumaOffset != 0)) or (component and (entry.chromaWeight[component - 1] != 1 << denominator or entry.chromaOffset[component - 1] != 0))
                    {
                        identityWeights = false
                        break
                    }
                }
            }

            if identityWeights and usesL0 and usesL1
            {
                let unit = component == 0 ? 4's32 : 8's32
                let mv0X = cast(s32) motion.mv[0, 0]
                let mv0Y = cast(s32) motion.mv[0, 1]
                let mv1X = cast(s32) motion.mv[1, 0]
                let mv1Y = cast(s32) motion.mv[1, 1]
                if (mv0X & (unit - 1)) == 0 and (mv0Y & (unit - 1)) == 0 and (mv1X & (unit - 1)) == 0 and (mv1Y & (unit - 1)) == 0
                {
                    let reference0 = .refList.frames[0, cast(u32) motion.refIdx[0]]
                    let reference1 = .refList.frames[1, cast(u32) motion.refIdx[1]]
                    if reference0 and reference1
                    {
                        .averageIntegerPrediction(reference0!, reference1!, component, x + mv0X / unit, y + mv0Y / unit, x + mv1X / unit, y + mv1Y / unit, x, y, width, height)
                        continue
                    }
                }
            }

            // An unweighted prediction from one list at an integer sample position is already
            // the final block. Routing it through the interpolation and combination buffers
            // would copy every sample three times and shift it out and back for no change.
            if identityWeights and usesL0 != usesL1
            {
                let list = usesL0 ? 0'u32 : 1'u32
                let unit = component == 0 ? 4's32 : 8's32
                let mvX  = cast(s32) motion.mv[list, 0]
                let mvY  = cast(s32) motion.mv[list, 1]
                if (mvX & (unit - 1)) == 0 and (mvY & (unit - 1)) == 0
                {
                    let reference = .refList.frames[list, cast(u32) motion.refIdx[list]]
                    if reference
                    {
                        .copyIntegerPrediction(reference!, component, x + mvX / unit, y + mvY / unit, x, y, width, height)
                        continue
                    }
                }
            }

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

            .combinePrediction(component, x, y, width, height, motion, sps, identityWeights)
        }
    }

    // Averages two integer-position predictions directly into the reconstructed picture.
    private mtd averageIntegerPrediction(reference0, reference1: *Frame, component: u32, source0X, source0Y, source1X, source1Y, destinationX, destinationY: s32, width, height: u32)
    {
        var source0, source1:             const [*] u16
        var source0Stride, source1Stride: u64
        var source0Width, source0Height:  s32
        var source1Width, source1Height:  s32
        var destination:                  [*] u16
        var destinationStride:            u64
        if !component
        {
            source0           = reference0.luma.buffer!
            source1           = reference1.luma.buffer!
            source0Stride     = reference0.strideLuma
            source1Stride     = reference1.strideLuma
            source0Width      = cast(s32) reference0.width
            source0Height     = cast(s32) reference0.height
            source1Width      = cast(s32) reference1.width
            source1Height     = cast(s32) reference1.height
            destination       = .current!.lumaAtMutable(destinationX, destinationY)
            destinationStride = .current!.strideLuma
        }
        else
        {
            source0           = component == 1 ? reference0.chromaB.buffer! : reference0.chromaR.buffer!
            source1           = component == 1 ? reference1.chromaB.buffer! : reference1.chromaR.buffer!
            source0Stride     = reference0.strideChroma
            source1Stride     = reference1.strideChroma
            source0Width      = cast(s32) reference0.chromaWidth
            source0Height     = cast(s32) reference0.chromaHeight
            source1Width      = cast(s32) reference1.chromaWidth
            source1Height     = cast(s32) reference1.chromaHeight
            destination       = .current!.chromaAtMutable(component - 1, destinationX, destinationY)
            destinationStride = .current!.strideChroma
        }

        // The padding of a completed reference already holds the clamped edge samples, so a
        // block that reaches past an edge but stays inside it is still read where it lies.
        let pad = cast(s32) FramePadding
        if source0X >= -pad and source0Y >= -pad and source1X >= -pad and source1Y >= -pad and source0X + cast(s32) width <= source0Width + pad and source1X + cast(s32) width <= source1Width + pad and source0Y + cast(s32) height <= source0Height + pad and source1Y + cast(s32) height <= source1Height + pad
        {
            let first0 = source0 + cast(u64) (source0Y + cast(s32) FramePadding) * source0Stride + cast(u64) (source0X + cast(s32) FramePadding)
            let first1 = source1 + cast(u64) (source1Y + cast(s32) FramePadding) * source1Stride + cast(u64) (source1X + cast(s32) FramePadding)
            for row in height
            {
                let line0  = first0 + cast(u64) row * source0Stride
                let line1  = first1 + cast(u64) row * source1Stride
                let out    = destination + cast(u64) row * destinationStride
                var column = 0'u32
                while column + 8 <= width
                {
                    Simd.store(out + column, Simd.average(Simd.load(line0 + column), Simd.load(line1 + column)))
                    column += 8
                }

                if column + 4 <= width
                {
                    storeLow4(out + column, Simd.average(Simd.load(line0 + column), Simd.load(line1 + column)))
                    column += 4
                }

                while column < width
                {
                    out[column] = cast(u16) ((cast(u32) line0[column] + cast(u32) line1[column] + 1) >> 1)
                    column      += 1
                }
            }

            return
        }

        for row in height
        {
            let y0    = Math.clamp(source0Y + cast(s32) row, 0, source0Height - 1)
            let y1    = Math.clamp(source1Y + cast(s32) row, 0, source1Height - 1)
            let line0 = source0 + cast(u64) (y0 + cast(s32) FramePadding) * source0Stride + cast(u64) FramePadding
            let line1 = source1 + cast(u64) (y1 + cast(s32) FramePadding) * source1Stride + cast(u64) FramePadding
            let out   = destination + cast(u64) row * destinationStride
            for column in width
            {
                let x0 = Math.clamp(source0X + cast(s32) column, 0, source0Width - 1)
                let x1 = Math.clamp(source1X + cast(s32) column, 0, source1Width - 1)
                out[column] = cast(u16) ((cast(u32) line0[cast(u64) x0] + cast(u32) line1[cast(u64) x1] + 1) >> 1)
            }
        }
    }

    // Copies one integer-position prediction directly into the reconstructed picture.
    private mtd copyIntegerPrediction(reference: *Frame, component: u32, sourceX, sourceY, destinationX, destinationY: s32, width, height: u32)
    {
        var source:                    const [*] u16
        var sourceStride:              u64
        var sourceWidth, sourceHeight: s32
        var destination:               [*] u16
        var destinationStride:         u64
        if !component
        {
            source            = reference.luma.buffer!
            sourceStride      = reference.strideLuma
            sourceWidth       = cast(s32) reference.width
            sourceHeight      = cast(s32) reference.height
            destination       = .current!.lumaAtMutable(destinationX, destinationY)
            destinationStride = .current!.strideLuma
        }
        else
        {
            source            = component == 1 ? reference.chromaB.buffer! : reference.chromaR.buffer!
            sourceStride      = reference.strideChroma
            sourceWidth       = cast(s32) reference.chromaWidth
            sourceHeight      = cast(s32) reference.chromaHeight
            destination       = .current!.chromaAtMutable(component - 1, destinationX, destinationY)
            destinationStride = .current!.strideChroma
        }

        // Motion vectors normally keep the whole block inside the picture or inside the padding
        // that repeats its edges. Copying complete rows is the common path; only a vector past that
        // padding needs per-sample clamping.
        let pad = cast(s32) FramePadding
        if sourceX >= -pad and sourceY >= -pad and sourceX + cast(s32) width <= sourceWidth + pad and sourceY + cast(s32) height <= sourceHeight + pad
        {
            let first = source + cast(u64) (sourceY + cast(s32) FramePadding) * sourceStride + cast(u64) (sourceX + cast(s32) FramePadding)
            for row in height do
                Memory.copy(destination + cast(u64) row * destinationStride, first + cast(u64) row * sourceStride, cast(u64) width * #sizeof(u16))
            return
        }

        for row in height
        {
            let sy   = Math.clamp(sourceY + cast(s32) row, 0, sourceHeight - 1)
            let line = source + cast(u64) (sy + cast(s32) FramePadding) * sourceStride + cast(u64) FramePadding
            let out  = destination + cast(u64) row * destinationStride
            for column in width do
                out[column] = line[cast(u64) Math.clamp(sourceX + cast(s32) column, 0, sourceWidth - 1)]
        }
    }

    // Copies the reference samples one interpolation reads, clamping to the picture edges.
    //
    // A motion vector may point arbitrarily far outside the picture, and the standard answers
    // every such sample with the nearest edge one; gathering first turns that into one bounded
    // copy instead of a clamp inside the filter loop.
    private mtd const gatherReference(frame: *Frame, component: u32, xInt, yInt: s32, width, height, before, taps: u32, destination: [*] u16, destinationStride: u64)
    {
        var plane:  const [*] u16
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

        let xInt      = x + (cast(s32) mvX >> 2)
        let yInt      = y + (cast(s32) mvY >> 2)
        let xFrac     = cast(u32) (cast(s32) mvX & 3)
        let yFrac     = cast(u32) (cast(s32) mvY & 3)
        let lumaTapsX = lumaTaps(xFrac)
        let lumaTapsY = lumaTaps(yFrac)

        var gathered:        [MaxRefSide * MaxRefSide] u16
        var reference:       const [*] u16
        var referenceStride: u64
        let firstX                                         = xInt - 3
        let firstY                                         = yInt - 3

        // A reference picture is complete before any block predicts from it, and completing it
        // replicates its edges through the whole padding. A window that stays inside that padding
        // therefore already holds what the clamp of clause 8.5.3.3.3 would produce, so it is read
        // where it lies instead of being gathered into a scratch block first.
        let pad = cast(s32) FramePadding
        if firstX >= -pad and firstY >= -pad and firstX + cast(s32) width + 7 <= cast(s32) frame.width + pad and firstY + cast(s32) height + 7 <= cast(s32) frame.height + pad
        {
            reference       = frame.lumaAt(firstX, firstY)!
            referenceStride = frame.strideLuma
        }
        else
        {
            reference       = &gathered[0]
            referenceStride = cast(u64) MaxRefSide
            .gatherReference(frame, 0, xInt, yInt, width, height, 3, 8, &gathered[0], referenceStride)
        }

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
                var column = 0'u32
                while column + 8 <= width
                {
                    Simd.store(&.predBuffer[list, row * width + column], filterLumaUnsigned8(&reference[source + cast(u64) column], 1, lumaTapsX, shift1))
                    column += 8
                }

                if column + 4 <= width
                {
                    storeLow4(&.predBuffer[list, row * width + column], filterLumaUnsigned4(&reference[source + cast(u64) column], 1, lumaTapsX, shift1))
                    column += 4
                }

                while column < width
                {
                    var sum = 0's32
                    for tap in 8'u32 do
                        sum += cast(s32) LumaFilter[xFrac, tap] * cast(s32) reference[source + cast(u64) (column + tap)]
                    .predBuffer[list, row * width + column] = cast(s16) (sum >> shift1)
                    column += 1
                }
            }

            return
        }

        if !xFrac
        {
            for row in height
            {
                var column = 0'u32
                while column + 8 <= width
                {
                    let source = &reference[cast(u64) row * referenceStride + cast(u64) (column + 3)]
                    Simd.store(&.predBuffer[list, row * width + column], filterLumaUnsigned8(source, referenceStride, lumaTapsY, shift1))
                    column += 8
                }

                if column + 4 <= width
                {
                    let source = &reference[cast(u64) row * referenceStride + cast(u64) (column + 3)]
                    storeLow4(&.predBuffer[list, row * width + column], filterLumaUnsigned4(source, referenceStride, lumaTapsY, shift1))
                    column += 4
                }

                while column < width
                {
                    var sum = 0's32
                    for tap in 8'u32 do
                        sum += cast(s32) LumaFilter[yFrac, tap] * cast(s32) reference[cast(u64) (row + tap) * referenceStride + cast(u64) (column + 3)]
                    .predBuffer[list, row * width + column] = cast(s16) (sum >> shift1)
                    column += 1
                }
            }

            return
        }

        // Both directions: the horizontal filter runs over every row the vertical one reads.
        var intermediate: [MaxRefSide * MaxPredSide] s16
        for row in height + 7
        {
            let source = cast(u64) row * referenceStride
            var column = 0'u32
            while column + 8 <= width
            {
                Simd.store(&intermediate[cast(u64) row * cast(u64) width + cast(u64) column], filterLumaUnsigned8(&reference[source + cast(u64) column], 1, lumaTapsX, shift1))
                column += 8
            }

            if column + 4 <= width
            {
                storeLow4(&intermediate[cast(u64) row * cast(u64) width + cast(u64) column], filterLumaUnsigned4(&reference[source + cast(u64) column], 1, lumaTapsX, shift1))
                column += 4
            }

            while column < width
            {
                var sum = 0's32
                for tap in 8'u32 do
                    sum += cast(s32) LumaFilter[xFrac, tap] * cast(s32) reference[source + cast(u64) (column + tap)]
                intermediate[cast(u64) row * cast(u64) width + cast(u64) column] = cast(s16) (sum >> shift1)
                column += 1
            }
        }

        for row in height
        {
            var column = 0'u32
            while column + 8 <= width
            {
                let source = &intermediate[cast(u64) row * cast(u64) width + cast(u64) column]
                Simd.store(&.predBuffer[list, row * width + column], filterLumaSigned8(source, cast(u64) width, lumaTapsY, shift2))
                column += 8
            }

            if column + 4 <= width
            {
                let source = &intermediate[cast(u64) row * cast(u64) width + cast(u64) column]
                storeLow4(&.predBuffer[list, row * width + column], filterLumaSigned4(source, cast(u64) width, lumaTapsY, shift2))
                column += 4
            }

            while column < width
            {
                var sum = 0's32
                for tap in 8'u32 do
                    sum += cast(s32) LumaFilter[yFrac, tap] * cast(s32) intermediate[cast(u64) (row + tap) * cast(u64) width + cast(u64) column]
                .predBuffer[list, row * width + column] = cast(s16) (sum >> shift2)
                column += 1
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
        let xInt        = x + (cast(s32) mvX >> 3)
        let yInt        = y + (cast(s32) mvY >> 3)
        let xFrac       = cast(u32) (cast(s32) mvX & 7)
        let yFrac       = cast(u32) (cast(s32) mvY & 7)
        let chromaTapsX = chromaTaps(xFrac)
        let chromaTapsY = chromaTaps(yFrac)

        var gathered:        [MaxRefSide * MaxRefSide] u16
        var reference:       const [*] u16
        var referenceStride: u64
        let firstX                                         = xInt - 1
        let firstY                                         = yInt - 1
        let pad                                            = cast(s32) FramePadding
        if firstX >= -pad and firstY >= -pad and firstX + cast(s32) width + 3 <= cast(s32) frame.chromaWidth + pad and firstY + cast(s32) height + 3 <= cast(s32) frame.chromaHeight + pad
        {
            let plane = component == 1 ? frame.chromaB.buffer! : frame.chromaR.buffer!
            reference       = plane + cast(u64) (firstY + cast(s32) FramePadding) * frame.strideChroma + cast(u64) (firstX + cast(s32) FramePadding)
            referenceStride = frame.strideChroma
        }
        else
        {
            reference       = &gathered[0]
            referenceStride = cast(u64) MaxRefSide
            .gatherReference(frame, component, xInt, yInt, width, height, 1, 4, &gathered[0], referenceStride)
        }

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
                var column = 0'u32
                while column + 8 <= width
                {
                    Simd.store(&.predBuffer[list, row * width + column], filterChromaUnsigned8(&reference[source + cast(u64) column], 1, chromaTapsX, shift1))
                    column += 8
                }

                if column + 4 <= width
                {
                    storeLow4(&.predBuffer[list, row * width + column], filterChromaUnsigned4(&reference[source + cast(u64) column], 1, chromaTapsX, shift1))
                    column += 4
                }

                while column < width
                {
                    var sum = 0's32
                    for tap in 4'u32 do
                        sum += cast(s32) ChromaFilter[xFrac, tap] * cast(s32) reference[source + cast(u64) (column + tap)]
                    .predBuffer[list, row * width + column] = cast(s16) (sum >> shift1)
                    column += 1
                }
            }

            return
        }

        if !xFrac
        {
            for row in height
            {
                var column = 0'u32
                while column + 8 <= width
                {
                    let source = &reference[cast(u64) row * referenceStride + cast(u64) (column + 1)]
                    Simd.store(&.predBuffer[list, row * width + column], filterChromaUnsigned8(source, referenceStride, chromaTapsY, shift1))
                    column += 8
                }

                if column + 4 <= width
                {
                    let source = &reference[cast(u64) row * referenceStride + cast(u64) (column + 1)]
                    storeLow4(&.predBuffer[list, row * width + column], filterChromaUnsigned4(source, referenceStride, chromaTapsY, shift1))
                    column += 4
                }

                while column < width
                {
                    var sum = 0's32
                    for tap in 4'u32 do
                        sum += cast(s32) ChromaFilter[yFrac, tap] * cast(s32) reference[cast(u64) (row + tap) * referenceStride + cast(u64) (column + 1)]
                    .predBuffer[list, row * width + column] = cast(s16) (sum >> shift1)
                    column += 1
                }
            }

            return
        }

        var intermediate: [MaxRefSide * MaxPredSide] s16
        for row in height + 3
        {
            let source = cast(u64) row * referenceStride
            var column = 0'u32
            while column + 8 <= width
            {
                Simd.store(&intermediate[cast(u64) row * cast(u64) width + cast(u64) column], filterChromaUnsigned8(&reference[source + cast(u64) column], 1, chromaTapsX, shift1))
                column += 8
            }

            if column + 4 <= width
            {
                storeLow4(&intermediate[cast(u64) row * cast(u64) width + cast(u64) column], filterChromaUnsigned4(&reference[source + cast(u64) column], 1, chromaTapsX, shift1))
                column += 4
            }

            while column < width
            {
                var sum = 0's32
                for tap in 4'u32 do
                    sum += cast(s32) ChromaFilter[xFrac, tap] * cast(s32) reference[source + cast(u64) (column + tap)]
                intermediate[cast(u64) row * cast(u64) width + cast(u64) column] = cast(s16) (sum >> shift1)
                column += 1
            }
        }

        for row in height
        {
            var column = 0'u32
            while column + 8 <= width
            {
                let source = &intermediate[cast(u64) row * cast(u64) width + cast(u64) column]
                Simd.store(&.predBuffer[list, row * width + column], filterChromaSigned8(source, cast(u64) width, chromaTapsY, shift2))
                column += 8
            }

            if column + 4 <= width
            {
                let source = &intermediate[cast(u64) row * cast(u64) width + cast(u64) column]
                storeLow4(&.predBuffer[list, row * width + column], filterChromaSigned4(source, cast(u64) width, chromaTapsY, shift2))
                column += 4
            }

            while column < width
            {
                var sum = 0's32
                for tap in 4'u32 do
                    sum += cast(s32) ChromaFilter[yFrac, tap] * cast(s32) intermediate[cast(u64) (row + tap) * cast(u64) width + cast(u64) column]
                .predBuffer[list, row * width + column] = cast(s16) (sum >> shift2)
                column += 1
            }
        }
    }

    // Combines the interpolated lists into the picture, clause 8.5.3.3.4.
    private mtd combinePrediction(component: u32, x, y: s32, width, height: u32, motion: const *PuMotion, sps: const *Sps, identityWeights: bool)
    {
        let header   = &.header
        let frame    = .current!
        let bitDepth = component == 0 ? sps.bitDepthLuma : sps.bitDepthChroma
        let maximum  = cast(s32) ((1'u32 << bitDepth) - 1)

        var destination: [*] u16
        var stride:      u64
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

        let weighted = !identityWeights and header.hasWeights and ((header.sliceType == SliceTypeP and .activePps!.weightedPred) or (header.sliceType == SliceTypeB and .activePps!.weightedBipred))
        if weighted
        {
            .combineWeighted(destination, stride, component, width, height, motion, usesL0, usesL1, bitDepth, maximum)
            return
        }

        let shift1  = Math.max(2'u32, 14 - bitDepth)
        let shift2  = Math.max(3'u32, 15 - bitDepth)
        let offset1 = 1's32 << (shift1 - 1)
        let offset2 = 1's32 << (shift2 - 1)
        let zeros   = Simd.splat(0's32)
        let maxima  = Simd.splat(maximum)

        if usesL0 and usesL1
        {
            for row in height
            {
                let out    = destination + cast(u64) row * stride
                let base   = row * width
                var column = 0'u32
                while column + 8 <= width
                {
                    let first  = Simd.load(&.predBuffer[0, base + column])
                    let second = Simd.load(&.predBuffer[1, base + column])
                    let low    = (Simd.widenLow(first) + Simd.widenLow(second) + offset2) >> shift2
                    let high   = (Simd.widenHigh(first) + Simd.widenHigh(second) + offset2) >> shift2
                    Simd.store(out + column, Simd.packUnsigned(Math.max(Math.min(low, maxima), zeros), Math.max(Math.min(high, maxima), zeros)))
                    column += 8
                }

                if column + 4 <= width
                {
                    let first   = Simd.load(&.predBuffer[0, base + column])
                    let second  = Simd.load(&.predBuffer[1, base + column])
                    let low     = (Simd.widenLow(first) + Simd.widenLow(second) + offset2) >> shift2
                    let clipped = Math.max(Math.min(low, maxima), zeros)
                    storeLow4(out + column, Simd.packUnsigned(clipped, clipped))
                    column += 4
                }

                while column < width
                {
                    let index = base + column
                    let sum   = cast(s32) .predBuffer[0, index] + cast(s32) .predBuffer[1, index] + offset2
                    out[column] = cast(u16) Math.clamp(sum >> shift2, 0, maximum)
                    column      += 1
                }
            }

            return
        }

        let list = usesL0 ? 0'u32 : 1'u32
        for row in height
        {
            let out    = destination + cast(u64) row * stride
            let base   = row * width
            var column = 0'u32
            while column + 8 <= width
            {
                let pixels = Simd.load(&.predBuffer[list, base + column])
                let low    = (Simd.widenLow(pixels) + offset1) >> shift1
                let high   = (Simd.widenHigh(pixels) + offset1) >> shift1
                Simd.store(out + column, Simd.packUnsigned(Math.max(Math.min(low, maxima), zeros), Math.max(Math.min(high, maxima), zeros)))
                column += 8
            }

            if column + 4 <= width
            {
                let pixels  = Simd.load(&.predBuffer[list, base + column])
                let low     = (Simd.widenLow(pixels) + offset1) >> shift1
                let clipped = Math.max(Math.min(low, maxima), zeros)
                storeLow4(out + column, Simd.packUnsigned(clipped, clipped))
                column += 4
            }

            while column < width
            {
                let value = cast(s32) .predBuffer[list, base + column] + offset1
                out[column] = cast(u16) Math.clamp(value >> shift1, 0, maximum)
                column      += 1
            }
        }
    }

    // Combines the interpolated lists with the weights the slice header carries, clause 8.5.3.3.4.3.
    private mtd combineWeighted(destination: [*] u16, stride: u64, component, width, height: u32, motion: const *PuMotion, usesL0, usesL1: bool, bitDepth: u32, maximum: s32)
    {
        let header      = &.header
        let shift1      = Math.max(2'u32, 14 - bitDepth)
        let denom       = component == 0 ? header.lumaLog2WeightDenom : header.chromaLog2WeightDenom
        let log2Wd      = denom + shift1
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

        let zeros  = Simd.splat(0's32)
        let maxima = Simd.splat(maximum)

        if usesL0 and usesL1
        {
            let rounding = (offset[0] + offset[1] + 1) << log2Wd
            for row in height
            {
                let out    = destination + cast(u64) row * stride
                let base   = row * width
                var column = 0'u32
                while column + 8 <= width
                {
                    let first  = Simd.load(&.predBuffer[0, base + column])
                    let second = Simd.load(&.predBuffer[1, base + column])
                    let low    = (Simd.widenLow(first) * weight[0] + Simd.widenLow(second) * weight[1] + rounding) >> (log2Wd + 1)
                    let high   = (Simd.widenHigh(first) * weight[0] + Simd.widenHigh(second) * weight[1] + rounding) >> (log2Wd + 1)
                    Simd.store(out + column, Simd.packUnsigned(Math.max(Math.min(low, maxima), zeros), Math.max(Math.min(high, maxima), zeros)))
                    column += 8
                }

                if column + 4 <= width
                {
                    let first  = Simd.load(&.predBuffer[0, base + column])
                    let second = Simd.load(&.predBuffer[1, base + column])
                    let low    = (Simd.widenLow(first) * weight[0] + Simd.widenLow(second) * weight[1] + rounding) >> (log2Wd + 1)
                    storeLow4(out + column, Simd.packUnsigned(Math.max(Math.min(low, maxima), zeros), Math.max(Math.min(low, maxima), zeros)))
                    column += 4
                }

                while column < width
                {
                    let index = base + column
                    let sum   = cast(s32) .predBuffer[0, index] * weight[0] + cast(s32) .predBuffer[1, index] * weight[1] + rounding
                    out[column] = cast(u16) Math.clamp(sum >> (log2Wd + 1), 0, maximum)
                    column      += 1
                }
            }

            return
        }

        let list     = usesL0 ? 0'u32 : 1'u32
        let rounding = 1's32 << (log2Wd - 1)
        for row in height
        {
            let out    = destination + cast(u64) row * stride
            let base   = row * width
            var column = 0'u32
            while column + 8 <= width
            {
                let pixels = Simd.load(&.predBuffer[list, base + column])
                let low    = ((Simd.widenLow(pixels) * weight[list] + rounding) >> log2Wd) + offset[list]
                let high   = ((Simd.widenHigh(pixels) * weight[list] + rounding) >> log2Wd) + offset[list]
                Simd.store(out + column, Simd.packUnsigned(Math.max(Math.min(low, maxima), zeros), Math.max(Math.min(high, maxima), zeros)))
                column += 8
            }

            if column + 4 <= width
            {
                let pixels = Simd.load(&.predBuffer[list, base + column])
                let low    = ((Simd.widenLow(pixels) * weight[list] + rounding) >> log2Wd) + offset[list]
                storeLow4(out + column, Simd.packUnsigned(Math.max(Math.min(low, maxima), zeros), Math.max(Math.min(low, maxima), zeros)))
                column += 4
            }

            while column < width
            {
                let value = ((cast(s32) .predBuffer[list, base + column] * weight[list] + rounding) >> log2Wd) + offset[list]
                out[column] = cast(u16) Math.clamp(value, 0, maximum)
                column      += 1
            }
        }
    }
}
