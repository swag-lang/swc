#global namespace Hevc
#global internal

using Core

// Clause 8.6.3: the six scaling steps one quantization period cycles through.
const LevelScale: [6] u16 = [40, 45, 51, 57, 64, 72]

// Clause 7.4.3.2.1: the range a transform coefficient is kept in without the range extensions.
const Log2TransformRange = 15'u32
const CoeffMin = -32768's32
const CoeffMax = 32767's32

// The state one transform block needs from the coding unit that contains it.
struct TransformBlock
{
    x:            s32     // Luma position of the block, whatever the component.
    y:            s32
    size:         u32     // Block size in samples of its own component.
    log2Size:     u32
    component:    u32     // Zero luma, one blue-difference chroma, two red-difference chroma.
    isIntra:      bool
    transformSkip: bool
    bypass:       bool
    qp:           s32
    lastX:        u32     // Highest column holding a coefficient, for the column pass.
    lastY:        u32     // Highest row holding a coefficient, for the row pass.
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
        var stride: u64
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

        for row in size
        {
            let out = destination + cast(u64) row * stride
            for column in size do
                out[column] = cast(u16) Math.clamp(cast(s32) out[column] + .residual[row * size + column], 0, maximum)
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
        let sps     = .activeSps!
        let pps     = .activePps!
        let size    = block.size
        let bdShift = cast(s32) (bitDepth + block.log2Size + 10 - Log2TransformRange)
        let rounding = 1's32 << (bdShift - 1)
        let scale   = cast(s32) LevelScale[block.qp % 6]
        let shift   = cast(u32) (block.qp / 6)

        // A flat matrix is the common case, and it collapses the whole derivation to one multiply.
        let flat = !sps.scalingListEnabled or (block.transformSkip and size > 4)
        if flat
        {
            let factor = scale * 16
            for index in size * size
            {
                let level = cast(s32) .coefficients[index]
                if !level do
                    continue
                .coefficients[index] = cast(s16) Math.clamp((((level * factor) << shift) + rounding) >> bdShift, CoeffMin, CoeffMax)
            }

            return
        }

        let sizeId   = block.log2Size - 2
        let matrixId = .scalingMatrixId(block, sizeId)
        for y in size
        {
            for x in size
            {
                let index = y * size + x
                let level = cast(s32) .coefficients[index]
                if !level do
                    continue
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
        var intermediate: [32 * 32] s32 = undefined

        // Only the rows and columns that hold a coefficient contribute, and the entropy decoder
        // already reported where the last one was: a block whose energy sits in its first rows
        // costs a fraction of the full transform.
        let rows    = lastY + 1
        let columns = lastX + 1
        let step    = 32 >> log2Size

        for x in columns
        {
            for i in size
            {
                var sum = 0's32
                if useDst
                {
                    for j in rows do
                        sum += cast(s32) TransMatrixDst4[j, i] * cast(s32) .coefficients[j * size + x]
                }
                else
                {
                    for j in rows do
                        sum += cast(s32) TransMatrix32[j * step, i] * cast(s32) .coefficients[j * size + x]
                }

                intermediate[i * size + x] = Math.clamp((sum + 64) >> 7, CoeffMin, CoeffMax)
            }
        }

        let rounding = 1's32 << (bdShift - 1)
        for y in size
        {
            let base = y * size
            for i in size
            {
                var sum = 0's32
                if useDst
                {
                    for j in columns do
                        sum += cast(s32) TransMatrixDst4[j, i] * intermediate[base + j]
                }
                else
                {
                    for j in columns do
                        sum += cast(s32) TransMatrix32[j * step, i] * intermediate[base + j]
                }

                .residual[base + i] = (sum + rounding) >> bdShift
            }
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
        var stride: u64
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
                for column in size do
                    out[column] = .predSamples[row * size + column]
            }

            return
        }

        for row in size
        {
            let out = destination + cast(u64) row * stride
            for column in size
            {
                let value = cast(s32) .predSamples[row * size + column] + .residual[row * size + column]
                out[column] = cast(u16) Math.clamp(value, 0, maximum)
            }
        }
    }
}
