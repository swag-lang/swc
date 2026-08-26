//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns inverse transforms and coefficient scaling.
//
#global namespace Hevc
#global internal

using Core

// Clause 8.6.3: the six scaling steps one quantization period cycles through.
const LevelScale: [6] u16 = [40, 45, 51, 57, 64, 72]

// Clause 7.4.3.2.1: the range a transform coefficient is kept in without the range extensions.
const Log2TransformRange = 15'u32
const CoeffMin           = -32768's32
const CoeffMax           = 32767's32

// The state one transform block needs from the coding unit that contains it.
struct TransformBlock
{
    x:             s32     // Luma position of the block, whatever the component.
    y:             s32
    size:          u32     // Block size in samples of its own component.
    log2Size:      u32
    component:     u32     // Zero luma, one blue-difference chroma, two red-difference chroma.
    isIntra:       bool
    transformSkip: bool
    bypass:        bool
    qp:            s32
    lastX:         u32     // Highest column holding a coefficient, for the column pass.
    lastY:         u32     // Highest row holding a coefficient, for the row pass.
}

// Repeats one pair of sixteen-bit values across a vector, in the layout `pmaddwd` sums.
//
// The instruction multiplies neighbours and adds them, so a matrix row interleaved with the next
// one meets the two values that go with them here.
#[Swag.Inline]
private func coefficientPair(first, second: s16)->Simd.S16x8
{
    let packed = (cast(u32) cast #wrap(u16) first) | ((cast(u32) cast #wrap(u16) second) << 16)
    return cast #bit(Simd.S16x8) Simd.splat(packed)
}

impl Decoder
{
    // Starts a quantization group and predicts its quantization parameter, clause 8.6.1.
    //
    // The prediction is the average of the parameters to the left and above the group, each of
    // which falls back to the last parameter decoded when it is not inside the same coding tree
    // block.
    mtd beginQuantizationGroup(x0, y0: s32)
    {
        let sps = .activeSps!

        var left = .qpYPrev
        if x0 > 0 and (x0 & cast(s32) (sps.ctbSize - 1)) != 0 and .isAvailable(x0, y0, x0 - 1, y0) do
            left = cast(s32) .qpY[.blockIndex(x0 - 1, y0)]

        var above = .qpYPrev
        if y0 > 0 and (y0 & cast(s32) (sps.ctbSize - 1)) != 0 and .isAvailable(x0, y0, x0, y0 - 1) do
            above = cast(s32) .qpY[.blockIndex(x0, y0 - 1)]

        .qpYPred = (left + above + 1) >> 1
        .refreshQp()
    }

    // Recomputes the quantization parameter of the current unit, equation 8-283.
    mtd refreshQp()
    {
        let sps   = .activeSps!
        let range = 52 + sps.qpBdOffsetY
        .currentQp = ((.qpYPred + .cuQpDeltaVal + 52 + 2 * sps.qpBdOffsetY) % range) - sps.qpBdOffsetY
    }

    // Returns the chroma quantization parameter of one component, clause 8.6.1.
    mtd const chromaQp(component: u32)->s32
    {
        let sps    = .activeSps!
        let pps    = .activePps!
        let header = &.header
        let offset = component == 1 ? pps.cbQpOffset + header.cbQpOffset : pps.crQpOffset + header.crQpOffset

        let index = Math.clamp(.currentQp + offset, -sps.qpBdOffsetC, 57)
        if index < 30 do
            return index
        if index > 43 do
            return index - 6
        return cast(s32) ChromaQpMapping[index - 30]
    }

    // Adds the residual of one transform block to samples already in the picture, clause 8.6.6.
    mtd addResidualInPlace(block: const *TransformBlock)
    {
        let sps      = .activeSps!
        let frame    = .current!
        let bitDepth = block.component == 0 ? sps.bitDepthLuma : sps.bitDepthChroma
        let maximum  = cast(s32) ((1'u32 << bitDepth) - 1)
        let size     = block.size

        var destination: [*] u16 = undefined
        var stride:      u64
        if !block.component
        {
            destination = frame.lumaAtMutable(block.x, block.y)
            stride      = frame.strideLuma
        }
        else
        {
            destination = frame.chromaAtMutable(block.component - 1, block.x / cast(s32) sps.subWidthC, block.y / cast(s32) sps.subHeightC)
            stride      = frame.strideChroma
        }

        let zeros  = Simd.splat(0's32)
        let maxima = Simd.splat(maximum)

        for row in size
        {
            let out    = destination + cast(u64) row * stride
            let base   = row * size
            var column = 0'u32
            while column + 8 <= size
            {
                let pixels = Simd.load(out + column)
                let low    = cast #bit(Simd.S32x4) Simd.widenLow(pixels) + Simd.load(&.residual[base + column])
                let high   = cast #bit(Simd.S32x4) Simd.widenHigh(pixels) + Simd.load(&.residual[base + column + 4])
                Simd.store(out + column, Simd.packUnsigned(Math.max(Math.min(low, maxima), zeros), Math.max(Math.min(high, maxima), zeros)))
                column += 8
            }

            while column < size
            {
                out[column] = cast(u16) Math.clamp(cast(s32) out[column] + .residual[base + column], 0, maximum)
                column      += 1
            }
        }
    }

    // Returns one reconstructed sample of the picture being decoded, in its own component's grid.
    #[Swag.Inline]
    mtd const reconstructedSample(component: u32, x, y: s32)->u16
    {
        let frame = .current!
        if !component do
            return frame.lumaAt(x, y)![0]
        return frame.chromaAtMutable(component - 1, x, y)[0]
    }

    // Turns the parsed coefficients of one transform block into residual samples, clause 8.6.2.
    //
    // The coefficients are scaled in place and the result is left in `.residual`, in raster order.
    mtd reconstructResidual(block: const *TransformBlock)
    {
        let sps      = .activeSps!
        let size     = block.size
        let bitDepth = block.component == 0 ? sps.bitDepthLuma : sps.bitDepthChroma

        if block.bypass
        {
            for index in size * size do
                .residual[index] = cast(s32) .coefficients[index]
            return
        }

        .scaleCoefficients(block, bitDepth)

        let bdShift = Math.max(20 - cast(s32) bitDepth, 0)
        if block.transformSkip
        {
            // A skipped transform only rescales, clause 8-298.
            let tsShift = 5 + cast(s32) block.log2Size
            for index in size * size do
                .residual[index] = ((cast(s32) .coefficients[index] << tsShift) + (1 << (bdShift - 1))) >> bdShift
            return
        }

        // The intra 4x4 luma block is the only one that uses the sine transform, clause 8.6.4.1.
        let useDst = block.isIntra and size == 4 and block.component == 0
        .inverseTransform(size, block.log2Size, useDst, block.lastX, block.lastY, bdShift)
    }

    // Scales the parsed coefficients into the coefficient array, clause 8.6.3.
    private mtd scaleCoefficients(block: const *TransformBlock, bitDepth: u32)
    {
        let sps      = .activeSps!
        let pps      = .activePps!
        let size     = block.size
        let bdShift  = cast(s32) (bitDepth + block.log2Size + 10 - Log2TransformRange)
        let rounding = 1's32 << (bdShift - 1)
        let scale    = cast(s32) LevelScale[block.qp % 6]
        let shift    = cast(u32) (block.qp / 6)

        // A flat matrix is the common case, and it collapses the whole derivation to one multiply.
        let flat = !sps.scalingListEnabled or (block.transformSkip and size > 4)
        if flat
        {
            let factor     = scale * 16
            var columnMask = .coefficientColumns
            while columnMask
            {
                let x = Math.trailingZeros(columnMask)
                columnMask &= columnMask - 1
                var rowMask = .coefficientRows[x]
                while rowMask
                {
                    let y = Math.trailingZeros(rowMask)
                    rowMask &= rowMask - 1
                    let index = y * size + x
                    let level = cast(s32) .coefficients[index]
                    .coefficients[index] = cast(s16) Math.clamp((((level * factor) << shift) + rounding) >> bdShift, CoeffMin, CoeffMax)
                }
            }

            return
        }

        let sizeId     = block.log2Size - 2
        let matrixId   = .scalingMatrixId(block, sizeId)
        var columnMask = .coefficientColumns
        while columnMask
        {
            let x = Math.trailingZeros(columnMask)
            columnMask &= columnMask - 1
            var rowMask = .coefficientRows[x]
            while rowMask
            {
                let y = Math.trailingZeros(rowMask)
                rowMask &= rowMask - 1
                let index  = y * size + x
                let level  = cast(s32) .coefficients[index]
                let factor = scale * cast(s32) .scalingFactor(&pps.scalingLists, sizeId, matrixId, x, y, size)
                .coefficients[index] = cast(s16) Math.clamp((((level * factor) << shift) + rounding) >> bdShift, CoeffMin, CoeffMax)
            }
        }
    }

    // Returns the quantization matrix a block uses, Table 7-4.
    private mtd const scalingMatrixId(block: const *TransformBlock, sizeId: u32)->u32
    {
        var matrixId = (block.isIntra ? 0'u32 : 3'u32) + block.component

        // The 32x32 size carries the two luma matrices only, so chroma reuses the 16x16 one.
        if sizeId == 3 and block.component != 0 do
            matrixId = block.isIntra ? 0 : 3
        return matrixId
    }

    // Expands one entry of a quantization matrix to the sample grid, equations 7-44 to 7-49.
    private mtd const scalingFactor(lists: const *ScalingLists, sizeId, matrixId, x, y, size: u32)->u32
    {
        if !sizeId do
            return cast(u32) lists.lists[0, matrixId, DiagScan4x4Index[y * 4 + x]]

        // Above 8x8 the stored matrix is 8x8 and every entry covers a square of samples.
        let shift = sizeId - 1
        let inner = (y >> shift) * 8 + (x >> shift)
        if sizeId > 1 and !x and !y do
            return cast(u32) lists.dc[sizeId - 2, matrixId]
        return cast(u32) lists.lists[sizeId, matrixId, DiagScan8x8Index[inner]]
    }

    // Applies the two-dimensional inverse transform of clause 8.6.4 to the scaled coefficients.
    private mtd inverseTransform(size, log2Size: u32, useDst: bool, lastX, lastY: u32, bdShift: s32)
    {
        // Quantized video leaves a large share of transform blocks with a DC coefficient only.
        // The first DCT basis is constant, so both matrix passes collapse to one value.
        if !useDst and !lastX and !lastY
        {
            let first    = Math.clamp((64 * cast(s32) .coefficients[0] + 64) >> 7, CoeffMin, CoeffMax)
            let rounding = 1's32 << (bdShift - 1)
            let value    = (64 * first + rounding) >> bdShift
            let values   = Simd.splat(value)
            var index    = 0'u32
            let count    = size * size
            while index < count
            {
                Simd.store(&.residual[index], values)
                index += 4
            }

            return
        }

        // The four-point DCT is frequent at residual boundaries. Its even/odd factorization
        // produces exactly the same integer sums as the matrix form with twelve multiplies per
        // pass instead of sixty-four.
        if size == 4 and !useDst
        {
            .inverseDct4(lastX, lastY, bdShift)
            return
        }

        if size == 8 and !useDst
        {
            .inverseDct8(lastX, lastY, bdShift)
            return
        }

        var intermediate: [32 * 32] s32 = undefined

        if useDst
        {
            let rows    = lastY + 1
            let columns = lastX + 1
            for x in columns
            {
                for sample in size
                {
                    var sum = 0's32
                    for basis in rows do
                        sum += cast(s32) TransMatrixDst4[basis, sample] * cast(s32) .coefficients[basis * size + x]
                    intermediate[sample * size + x] = Math.clamp((sum + 64) >> 7, CoeffMin, CoeffMax)
                }
            }

            let rounding = 1's32 << (bdShift - 1)
            for y in size
            {
                let base = y * size
                for sample in size
                {
                    var sum = 0's32
                    for basis in columns do
                        sum += cast(s32) TransMatrixDst4[basis, sample] * intermediate[base + basis]
                    .residual[base + sample] = (sum + rounding) >> bdShift
                }
            }

            return
        }

        // Only significant coefficients contribute to the first pass, and only their columns
        // contribute to the second. Quantized large blocks are sparse even when one high-frequency
        // coefficient makes their rectangular extent cover most of the transform.
        //
        // The buffer between the passes holds one column of the block per row, which is the
        // order the first pass produces: it fills eight consecutive samples of one column at a
        // time, and the second pass reads one sample per basis, for which a stride costs nothing.
        //
        // Two basis functions are carried by one instruction. Every value the passes multiply is
        // clamped into sixteen bits, so a row of the matrix and a row of the next one interleave
        // into the pair layout `pmaddwd` sums, and one multiply-add covers eight products where a
        // widened multiply covered four. What the pair costs is one interleave of two loads the
        // scalar form was loading anyway.
        let step   = 32 >> log2Size
        let matrix = cast([*] s16) &.transformMatrix[0]
        let minima = Simd.splat(CoeffMin)
        let maxima = Simd.splat(CoeffMax)

        var activeColumns = .coefficientColumns
        while activeColumns
        {
            let x = Math.trailingZeros(activeColumns)
            activeColumns &= activeColumns - 1

            let column = x * size
            var sample = 0'u32
            while sample < size
            {
                var low:  Simd.S32x4 = Simd.splat(0's32)
                var high: Simd.S32x4 = Simd.splat(0's32)
                var activeRows       = .coefficientRows[x]
                while activeRows
                {
                    let first = Math.trailingZeros(activeRows)
                    activeRows &= activeRows - 1

                    // An odd count leaves the last basis on its own: it pairs with itself against
                    // a zero, which the multiply-add then contributes nothing for.
                    var second      = first
                    var secondValue = 0's16
                    if activeRows
                    {
                        second      = Math.trailingZeros(activeRows)
                        secondValue = .coefficients[second * size + x]
                        activeRows  &= activeRows - 1
                    }

                    let rowA   = Simd.load(matrix + first * step * 32 + sample)
                    let rowB   = Simd.load(matrix + second * step * 32 + sample)
                    let values = coefficientPair(.coefficients[first * size + x], secondValue)
                    low  += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U16x8) rowA, cast #bit(Simd.U16x8) rowB), values)
                    high += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(cast #bit(Simd.U16x8) rowA, cast #bit(Simd.U16x8) rowB), values)
                }

                Simd.store(&intermediate[column + sample], Math.max(Math.min((low + 64) >> 7, maxima), minima))
                Simd.store(&intermediate[column + sample + 4], Math.max(Math.min((high + 64) >> 7, maxima), minima))

                sample += 8
            }
        }

        let rounding = 1's32 << (bdShift - 1)
        for y in size
        {
            let base   = y * size
            var sample = 0'u32
            while sample < size
            {
                var low:  Simd.S32x4 = Simd.splat(0's32)
                var high: Simd.S32x4 = Simd.splat(0's32)
                var activeBasis      = .coefficientColumns
                while activeBasis
                {
                    let first = Math.trailingZeros(activeBasis)
                    activeBasis &= activeBasis - 1

                    var second      = first
                    var secondValue = 0's16
                    if activeBasis
                    {
                        second      = Math.trailingZeros(activeBasis)
                        secondValue = cast(s16) intermediate[second * size + y]
                        activeBasis &= activeBasis - 1
                    }

                    let rowA   = Simd.load(matrix + first * step * 32 + sample)
                    let rowB   = Simd.load(matrix + second * step * 32 + sample)
                    let values = coefficientPair(cast(s16) intermediate[first * size + y], secondValue)
                    low  += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveLow(cast #bit(Simd.U16x8) rowA, cast #bit(Simd.U16x8) rowB), values)
                    high += Simd.mulAddPairs(cast #bit(Simd.S16x8) Simd.interleaveHigh(cast #bit(Simd.U16x8) rowA, cast #bit(Simd.U16x8) rowB), values)
                }

                // A row of the residual is contiguous, so the two vectors are written where they
                // stand instead of being read back lane by lane.
                Simd.store(&.residual[base + sample], (low + rounding) >> cast(u32) bdShift)
                Simd.store(&.residual[base + sample + 4], (high + rounding) >> cast(u32) bdShift)

                sample += 8
            }
        }
    }

    // Applies both passes of the HEVC four-point inverse DCT.
    private mtd inverseDct4(lastX, lastY: u32, bdShift: s32)
    {
        var intermediate: [16] s32 = undefined
        let rows = lastY + 1
        for x in lastX + 1
        {
            let c0 = cast(s32) .coefficients[x]
            let c1 = rows > 1 ? cast(s32) .coefficients[4 + x] : 0
            let c2 = rows > 2 ? cast(s32) .coefficients[8 + x] : 0
            let c3 = rows > 3 ? cast(s32) .coefficients[12 + x] : 0
            let e0 = 64 * (c0 + c2)
            let e1 = 64 * (c0 - c2)
            let o0 = 83 * c1 + 36 * c3
            let o1 = 36 * c1 - 83 * c3
            intermediate[x]      = Math.clamp((e0 + o0 + 64) >> 7, CoeffMin, CoeffMax)
            intermediate[4 + x]  = Math.clamp((e1 + o1 + 64) >> 7, CoeffMin, CoeffMax)
            intermediate[8 + x]  = Math.clamp((e1 - o1 + 64) >> 7, CoeffMin, CoeffMax)
            intermediate[12 + x] = Math.clamp((e0 - o0 + 64) >> 7, CoeffMin, CoeffMax)
        }

        let columns  = lastX + 1
        let rounding = 1's32 << (bdShift - 1)
        for y in 4'u32
        {
            let base = y * 4
            let c0   = intermediate[base]
            let c1   = columns > 1 ? intermediate[base + 1] : 0
            let c2   = columns > 2 ? intermediate[base + 2] : 0
            let c3   = columns > 3 ? intermediate[base + 3] : 0
            let e0   = 64 * (c0 + c2)
            let e1   = 64 * (c0 - c2)
            let o0   = 83 * c1 + 36 * c3
            let o1   = 36 * c1 - 83 * c3
            .residual[base]     = (e0 + o0 + rounding) >> bdShift
            .residual[base + 1] = (e1 + o1 + rounding) >> bdShift
            .residual[base + 2] = (e1 - o1 + rounding) >> bdShift
            .residual[base + 3] = (e0 - o0 + rounding) >> bdShift
        }
    }

    // Applies both passes of the HEVC eight-point inverse DCT. Splitting even and odd basis
    // rows removes the repeated products shared by the mirrored output samples.
    private mtd inverseDct8(lastX, lastY: u32, bdShift: s32)
    {
        var intermediate: [64] s32 = undefined
        let rows = lastY + 1
        for x in lastX + 1
        {
            let c0 = cast(s32) .coefficients[x]
            let c1 = rows > 1 ? cast(s32) .coefficients[8 + x] : 0
            let c2 = rows > 2 ? cast(s32) .coefficients[16 + x] : 0
            let c3 = rows > 3 ? cast(s32) .coefficients[24 + x] : 0
            let c4 = rows > 4 ? cast(s32) .coefficients[32 + x] : 0
            let c5 = rows > 5 ? cast(s32) .coefficients[40 + x] : 0
            let c6 = rows > 6 ? cast(s32) .coefficients[48 + x] : 0
            let c7 = rows > 7 ? cast(s32) .coefficients[56 + x] : 0

            let o0  = 89 * c1 + 75 * c3 + 50 * c5 + 18 * c7
            let o1  = 75 * c1 - 18 * c3 - 89 * c5 - 50 * c7
            let o2  = 50 * c1 - 89 * c3 + 18 * c5 + 75 * c7
            let o3  = 18 * c1 - 50 * c3 + 75 * c5 - 89 * c7
            let eo0 = 83 * c2 + 36 * c6
            let eo1 = 36 * c2 - 83 * c6
            let ee0 = 64 * (c0 + c4)
            let ee1 = 64 * (c0 - c4)
            let e0  = ee0 + eo0
            let e1  = ee1 + eo1
            let e2  = ee1 - eo1
            let e3  = ee0 - eo0

            intermediate[x]      = Math.clamp((e0 + o0 + 64) >> 7, CoeffMin, CoeffMax)
            intermediate[8 + x]  = Math.clamp((e1 + o1 + 64) >> 7, CoeffMin, CoeffMax)
            intermediate[16 + x] = Math.clamp((e2 + o2 + 64) >> 7, CoeffMin, CoeffMax)
            intermediate[24 + x] = Math.clamp((e3 + o3 + 64) >> 7, CoeffMin, CoeffMax)
            intermediate[32 + x] = Math.clamp((e3 - o3 + 64) >> 7, CoeffMin, CoeffMax)
            intermediate[40 + x] = Math.clamp((e2 - o2 + 64) >> 7, CoeffMin, CoeffMax)
            intermediate[48 + x] = Math.clamp((e1 - o1 + 64) >> 7, CoeffMin, CoeffMax)
            intermediate[56 + x] = Math.clamp((e0 - o0 + 64) >> 7, CoeffMin, CoeffMax)
        }

        let columns  = lastX + 1
        let rounding = 1's32 << (bdShift - 1)
        for y in 8'u32
        {
            let base = y * 8
            let c0   = intermediate[base]
            let c1   = columns > 1 ? intermediate[base + 1] : 0
            let c2   = columns > 2 ? intermediate[base + 2] : 0
            let c3   = columns > 3 ? intermediate[base + 3] : 0
            let c4   = columns > 4 ? intermediate[base + 4] : 0
            let c5   = columns > 5 ? intermediate[base + 5] : 0
            let c6   = columns > 6 ? intermediate[base + 6] : 0
            let c7   = columns > 7 ? intermediate[base + 7] : 0

            let o0  = 89 * c1 + 75 * c3 + 50 * c5 + 18 * c7
            let o1  = 75 * c1 - 18 * c3 - 89 * c5 - 50 * c7
            let o2  = 50 * c1 - 89 * c3 + 18 * c5 + 75 * c7
            let o3  = 18 * c1 - 50 * c3 + 75 * c5 - 89 * c7
            let eo0 = 83 * c2 + 36 * c6
            let eo1 = 36 * c2 - 83 * c6
            let ee0 = 64 * (c0 + c4)
            let ee1 = 64 * (c0 - c4)
            let e0  = ee0 + eo0
            let e1  = ee1 + eo1
            let e2  = ee1 - eo1
            let e3  = ee0 - eo0

            .residual[base]     = (e0 + o0 + rounding) >> bdShift
            .residual[base + 1] = (e1 + o1 + rounding) >> bdShift
            .residual[base + 2] = (e2 + o2 + rounding) >> bdShift
            .residual[base + 3] = (e3 + o3 + rounding) >> bdShift
            .residual[base + 4] = (e3 - o3 + rounding) >> bdShift
            .residual[base + 5] = (e2 - o2 + rounding) >> bdShift
            .residual[base + 6] = (e1 - o1 + rounding) >> bdShift
            .residual[base + 7] = (e0 - o0 + rounding) >> bdShift
        }
    }

    // Adds the residual of one transform block to the reconstructed picture, clause 8.6.6.
    mtd addResidual(block: const *TransformBlock, hasResidual: bool)
    {
        let sps      = .activeSps!
        let frame    = .current!
        let bitDepth = block.component == 0 ? sps.bitDepthLuma : sps.bitDepthChroma
        let maximum  = cast(s32) ((1'u32 << bitDepth) - 1)
        let size     = block.size

        var destination: [*] u16 = undefined
        var stride:      u64
        if !block.component
        {
            destination = frame.lumaAtMutable(block.x, block.y)
            stride      = frame.strideLuma
        }
        else
        {
            destination = frame.chromaAtMutable(block.component - 1, block.x / cast(s32) sps.subWidthC, block.y / cast(s32) sps.subHeightC)
            stride      = frame.strideChroma
        }

        if !hasResidual
        {
            for row in size
            {
                let out = destination + cast(u64) row * stride
                Memory.copy(out, &.predSamples[row * size], cast(u64) size * #sizeof(u16))
            }

            return
        }

        let zeros  = Simd.splat(0's32)
        let maxima = Simd.splat(maximum)
        for row in size
        {
            let out    = destination + cast(u64) row * stride
            let base   = row * size
            var column = 0'u32
            while column + 8 <= size
            {
                let prediction = Simd.load(&.predSamples[base + column])
                let low        = cast #bit(Simd.S32x4) Simd.widenLow(prediction) + Simd.load(&.residual[base + column])
                let high       = cast #bit(Simd.S32x4) Simd.widenHigh(prediction) + Simd.load(&.residual[base + column + 4])
                Simd.store(out + column, Simd.packUnsigned(Math.max(Math.min(low, maxima), zeros), Math.max(Math.min(high, maxima), zeros)))
                column += 8
            }

            while column < size
            {
                let value = cast(s32) .predSamples[base + column] + .residual[base + column]
                out[column] = cast(u16) Math.clamp(value, 0, maximum)
                column      += 1
            }
        }
    }
}
