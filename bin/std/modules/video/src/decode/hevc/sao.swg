//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns sample adaptive offset parameters and their application.
//
#global namespace Hevc
#global internal

using Core

// Returns the sign of a difference, which is what an edge offset class is derived from.
#[Swag.Inline]
private func signOf(value: s32)->s32
{
    if value > 0
    {
        return 1
    }

    if value < 0
    {
        return -1
    }

    return 0
}

// Returns the same sign for eight samples at once, as the lane values 1, 0 and -1.
//
// A comparison answers with a lane of ones, which is minus one read as a number, so the two
// comparisons carry the whole answer and the subtraction the clause writes never runs.
#[Swag.Inline]
private func signOfDifference(centre, other: Simd.S16x8)->Simd.S16x8 => cast #bit(Simd.S16x8, (other > centre)) - cast #bit(Simd.S16x8, (centre > other))

// Table 8-13: the two neighbours each edge offset class compares a sample against.
const SaoEdgeHPos: [4, 2] s8 = [[-1, 1], [0, 0], [-1, 1], [1, -1]]
const SaoEdgeVPos: [4, 2] s8 = [[0, 0], [-1, 1], [-1, 1], [-1, 1]]

// The sample adaptive offset parameters of one coding tree block, clause 7.3.8.3.
//
// Type zero leaves the block alone, one shifts a band of the sample range, and two shifts samples
// by how they compare with two neighbours along one direction.
struct SaoParameters
{
    typeIdx:      [3] u8
    offsets:      [3, 5] s16     // Index zero is always zero, so an edge class indexes it directly.
    bandPosition: [3] u8
    eoClass:      [3] u8
}

private struct SaoEdgeBlock
{
    source:      const [*] u16
    destination: [*] u16
    stride:      u64
    rx, ry:      s32
    width:       s32
    height:      s32
}

impl Decoder
{
    // Reads the sample adaptive offset parameters of one coding tree block, clause 7.3.8.3.
    mtd readSaoParameters(rx, ry: s32) fail
    {
        let sps    = unwrap .activeSps
        let header = &.header
        let index  = cast(u64, ry) * cast(u64, sps.widthInCtbs) + cast(u64, rx)

        var merged = false
        if rx > 0
        {
            let leftInSlice = .ctbAddrRs > .sliceAddrRs
            let leftInTile  = .tileId[.ctbAddrTs] == .tileId[.ctbRsToTs[.ctbAddrRs - 1]]
            if leftInSlice and leftInTile and .cabac.decision(CtxSaoMergeFlag) != 0
            {
                .sao[index] = .sao[index - 1]
                .saoUsed    = .saoUsed or .sao[index].typeIdx[0] != 0 or .sao[index].typeIdx[1] != 0
                merged      = true
            }
        }

        if not merged and ry > 0
        {
            let upInSlice = .ctbAddrRs >= .sliceAddrRs + sps.widthInCtbs
            let upInTile  = .tileId[.ctbAddrTs] == .tileId[.ctbRsToTs[.ctbAddrRs - sps.widthInCtbs]]
            if upInSlice and upInTile and .cabac.decision(CtxSaoMergeFlag) != 0
            {
                .sao[index] = .sao[index - cast(u64, sps.widthInCtbs)]
                .saoUsed    = .saoUsed or .sao[index].typeIdx[0] != 0 or .sao[index].typeIdx[1] != 0
                merged      = true
            }
        }

        if merged
        {
            return
        }

        var parameters: SaoParameters
        let maximumOffset = (1_u32 << (Math.min(sps.bitDepthLuma, 10_u32) - 5)) - 1

        for component in 3_u32
        {
            if (component == 0 and not header.saoLuma) or (component > 0 and not header.saoChroma)
            {
                continue
            }

            // The two chroma components share one type and one class, stated with the first.
            var kind = 0_u32
            if component < 2
            {
                if .cabac.decision(CtxSaoTypeIdx) != 0
                {
                    kind = .cabac.bypass() != 0 ? 2_u32 : 1_u32
                }
            }
            else
            {
                kind = cast(u32, parameters.typeIdx[1])
            }

            parameters.typeIdx[component] = cast(u8, kind)
            if not kind
            {
                continue
            }

            var magnitude: [4] u32
            for entry in 4_u32
            {
                var value = 0_u32
                while value < maximumOffset and .cabac.bypass() != 0
                {
                    value += 1
                }

                magnitude[entry] = value
            }

            if kind == 1
            {
                for entry in 4_u32
                {
                    var value = cast(s16, magnitude[entry])
                    if magnitude[entry] != 0 and .cabac.bypass() != 0
                    {
                        value = -value
                    }

                    parameters.offsets[component, entry + 1] = value
                }

                parameters.bandPosition[component] = cast(u8, .cabac.bypassBits(5))
            }
            else
            {
                // An edge offset states magnitudes only: the first two raise a sample and the
                // last two lower it, clause 7.4.9.3.
                parameters.offsets[component, 1] = cast(s16, magnitude[0])
                parameters.offsets[component, 2] = cast(s16, magnitude[1])
                parameters.offsets[component, 3] = -cast(s16, magnitude[2])
                parameters.offsets[component, 4] = -cast(s16, magnitude[3])
                if component < 2
                {
                    parameters.eoClass[component] = cast(u8, .cabac.bypassBits(2))
                }
                else
                {
                    parameters.eoClass[2] = parameters.eoClass[1]
                }
            }
        }

        .sao[index] = parameters
        if parameters.typeIdx[0] != 0 or parameters.typeIdx[1] != 0 or parameters.typeIdx[2] != 0
        {
            .saoUsed = true
        }
    }

    // Applies the sample adaptive offset of every coding tree block, clause 8.7.3.
    //
    // The filter reads the deblocked picture and writes a new one, so the samples one block reads
    // are never the ones an earlier block wrote. Swapping the picture with the retained scratch
    // storage makes that separation free; each block then writes every destination sample once.
    mtd applySampleAdaptiveOffset()
    {
        let sps = unwrap .activeSps
        if not sps.saoEnabled or not .saoUsed
        {
            return
        }

        let frame   = unwrap .current
        let columns = cast(u64, sps.widthInCtbs)
        for component in 3_u32
        {
            // A plane without offsets already holds its final samples.
            var hasOffsets = false
            for &parameters in .sao where parameters.typeIdx[component]
            {
                hasOffsets = true
                break
            }

            if not hasOffsets
            {
                continue
            }

            let plane   = component == 0 ? &frame.luma : component == 1 ? &frame.chromaB : &frame.chromaR
            let scratch = component == 0 ? &.saoSource : component == 1 ? &.saoSourceChromaB : &.saoSourceChromaR
            scratch.resize(plane.count)
            Core.swap(scratch, plane)

            for ry in sps.heightInCtbs
            {
                let row = .sao.storage() + cast(u64, ry) * columns
                var rx  = 0_u64
                while rx < columns
                {
                    let parameters = row + rx
                    var endRx      = rx + 1

                    // Adjacent blocks without offsets can copy each row as one span.
                    if not parameters.typeIdx[component]
                    {
                        while endRx < columns and not row[endRx].typeIdx[component]
                        {
                            endRx += 1
                        }
                    }

                    .applySaoBlock(parameters, component, cast(s32, rx), cast(s32, endRx), cast(s32, ry))
                    rx = endRx
                }
            }
        }
    }

    // Applies one block's offsets or copies a span of unchanged blocks, clause 8.7.3.2.
    private mtd applySaoBlock(parameters: const *SaoParameters, component: u32, rx, endRx, ry: s32)
    {
        let sps      = unwrap .activeSps
        let frame    = unwrap .current
        let scale    = component == 0 ? 1_s32 : 2_s32
        let bitDepth = component == 0 ? sps.bitDepthLuma : sps.bitDepthChroma
        let maximum  = cast(s32, ((1_u32 << bitDepth) - 1))

        let ctbSize     = cast(s32, sps.ctbSize) / scale
        let planeWidth  = cast(s32, (component == 0 ? sps.width : sps.width / sps.subWidthC))
        let planeHeight = cast(s32, (component == 0 ? sps.height : sps.height / sps.subHeightC))
        let x0          = rx * ctbSize
        let y0          = ry * ctbSize
        let width       = Math.min(endRx * ctbSize, planeWidth) - x0
        let height      = Math.min(ctbSize, planeHeight - y0)
        if width <= 0 or height <= 0
        {
            return
        }

        var source:      const [*] u16
        var destination: [*] u16
        var stride:      u64
        if not component
        {
            source      = .saoSource.storage()
            destination = frame.luma.storage()
            stride      = frame.strideLuma
        }
        else
        {
            source      = component == 1 ? .saoSourceChromaB.storage() : .saoSourceChromaR.storage()
            destination = component == 1 ? frame.chromaB.storage() : frame.chromaR.storage()
            stride      = frame.strideChroma
        }

        let origin = cast(u64, FramePadding) * stride + cast(u64, FramePadding)
        let kind   = parameters.typeIdx[component]

        if not kind
        {
            var line  = origin + cast(u64, y0) * stride + cast(u64, x0)
            let bytes = cast(u64, width) * #sizeof(u16)
            for height
            {
                Memory.copy(&destination[line], &source[line], bytes)
                line += stride
            }

            return
        }

        if kind == 1
        {
            // Band offset: four consecutive bands of the sample range are shifted. The four are
            // consecutive, so where a sample falls is its distance from the first band rather
            // than an entry of a table of thirty-two, and the same four selections that serve an
            // edge category serve it here.
            let shift     = bitDepth - 5
            let zeros     = Simd.splat(0_s16)
            let ones      = Simd.splat(1_s16)
            let twos      = Simd.splat(2_s16)
            let threes    = Simd.splat(3_s16)
            let masks     = Simd.splat(31_s16)
            let maxima    = Simd.splat(cast(s16, maximum))
            let positions = Simd.splat(cast(s16, parameters.bandPosition[component]))
            let offset1   = Simd.splat(parameters.offsets[component, 1])
            let offset2   = Simd.splat(parameters.offsets[component, 2])
            let offset3   = Simd.splat(parameters.offsets[component, 3])
            let offset4   = Simd.splat(parameters.offsets[component, 4])

            for row in height
            {
                let line   = origin + cast(u64, (y0 + row)) * stride + cast(u64, x0)
                var column = 0_s32

                while column + 8 <= width
                {
                    let samples = Simd.load(&source[line + cast(u64, column)])
                    let bands   = (cast #bit(Simd.S16x8, (samples >> shift)) - positions) & masks
                    var offset  = Simd.select(bands == zeros, offset1, zeros)
                    offset = Simd.select(bands == ones, offset2, offset)
                    offset = Simd.select(bands == twos, offset3, offset)
                    offset = Simd.select(bands == threes, offset4, offset)

                    let values = cast #bit(Simd.S16x8, samples) + offset
                    Simd.store(&destination[line + cast(u64, column)], cast #bit(Simd.U16x8, Math.max(Math.min(values, maxima), zeros)))
                    column += 8
                }

                while column < width
                {
                    let value  = cast(s32, source[line + cast(u64, column)])
                    let band   = (cast(s32, (cast(u32, value) >> shift)) - cast(s32, parameters.bandPosition[component])) & 31
                    let offset = band < 4 ? cast(s32, parameters.offsets[component, cast(u32, band) + 1]) : 0
                    destination[line + cast(u64, column)] = cast(u16, Math.clamp(value + offset, 0, maximum))
                    column += 1
                }
            }

            return
        }

        // Edge offset: a sample is shifted by how it compares with two neighbours.
        let eoClass = cast(u32, parameters.eoClass[component])
        let h0      = cast(s32, SaoEdgeHPos[eoClass, 0])
        let h1      = cast(s32, SaoEdgeHPos[eoClass, 1])
        let v0      = cast(s32, SaoEdgeVPos[eoClass, 0])
        let v1      = cast(s32, SaoEdgeVPos[eoClass, 1])

        // A sample whose comparison would leave the picture keeps the value deblocking gave it,
        // and the samples that do are a border of the picture rather than a property of the
        // sample. Trimming the block to where both neighbours exist takes the four tests out of
        // the loop, which then addresses three lines instead of recomputing three offsets.
        let xBegin = Math.max(x0, -Math.min(h0, h1))
        let xEnd   = Math.min(x0 + width, planeWidth - Math.max(h0, h1))
        let yBegin = Math.max(y0, -Math.min(v0, v1))
        let yEnd   = Math.min(y0 + height, planeHeight - Math.max(v0, v1))

        // The filter below writes only positions whose two neighbours exist. Copy the border it
        // excludes, and copy the whole block when no such position exists.
        if xBegin >= xEnd or yBegin >= yEnd
        {
            for row in height
            {
                let line = origin + cast(u64, (y0 + row)) * stride + cast(u64, x0)
                Memory.copy(&destination[line], &source[line], cast(u64, width) * #sizeof(u16))
            }

            return
        }

        for y in y0 until yBegin
        {
            let line = origin + cast(u64, y) * stride + cast(u64, x0)
            Memory.copy(&destination[line], &source[line], cast(u64, width) * #sizeof(u16))
        }

        for y in yBegin until yEnd
        {
            let line = origin + cast(u64, y) * stride
            if xBegin > x0
            {
                Memory.copy(&destination[line + cast(u64, x0)], &source[line + cast(u64, x0)], cast(u64, (xBegin - x0)) * #sizeof(u16))
            }

            if xEnd < x0 + width
            {
                Memory.copy(&destination[line + cast(u64, xEnd)], &source[line + cast(u64, xEnd)], cast(u64, (x0 + width - xEnd)) * #sizeof(u16))
            }
        }

        for y in yEnd until y0 + height
        {
            let line = origin + cast(u64, y) * stride + cast(u64, x0)
            Memory.copy(&destination[line], &source[line], cast(u64, width) * #sizeof(u16))
        }

        // The categories the standard derives from two comparisons index the offsets directly,
        // and category two, the flat one, carries no offset. Selecting the offset by category
        // rather than the category itself leaves nothing to look up.
        let zeros   = Simd.splat(0_s16)
        let ones    = Simd.splat(1_s16)
        let twos    = Simd.splat(2_s16)
        let threes  = Simd.splat(3_s16)
        let fours   = Simd.splat(4_s16)
        let maxima  = Simd.splat(cast(s16, maximum))
        let offset1 = Simd.splat(parameters.offsets[component, 1])
        let offset2 = Simd.splat(parameters.offsets[component, 2])
        let offset3 = Simd.splat(parameters.offsets[component, 3])
        let offset4 = Simd.splat(parameters.offsets[component, 4])

        for y in yBegin until yEnd
        {
            let centreLine = origin + cast(u64, y) * stride
            let firstLine  = origin + cast(u64, (y + v0)) * stride
            let secondLine = origin + cast(u64, (y + v1)) * stride
            var x          = xBegin

            while x + 8 <= xEnd
            {
                let centre = cast #bit(Simd.S16x8, Simd.load(&source[centreLine + cast(u64, x)]))
                let first  = cast #bit(Simd.S16x8, Simd.load(&source[firstLine + cast(u64, (x + h0))]))
                let second = cast #bit(Simd.S16x8, Simd.load(&source[secondLine + cast(u64, (x + h1))]))

                let category = twos + signOfDifference(centre, first) + signOfDifference(centre, second)
                var shift    = Simd.select(category == zeros, offset1, zeros)
                shift = Simd.select(category == ones, offset2, shift)
                shift = Simd.select(category == threes, offset3, shift)
                shift = Simd.select(category == fours, offset4, shift)

                Simd.store(&destination[centreLine + cast(u64, x)], cast #bit(Simd.U16x8, Math.max(Math.min(centre + shift, maxima), zeros)))
                x += 8
            }

            while x < xEnd
            {
                let centre = cast(s32, source[centreLine + cast(u64, x)])
                let first  = cast(s32, source[firstLine + cast(u64, (x + h0))])
                let second = cast(s32, source[secondLine + cast(u64, (x + h1))])

                var edge = 2 + signOf(centre - first) + signOf(centre - second)
                if edge <= 2
                {
                    edge = edge == 2 ? 0 : edge + 1
                }

                let offset = parameters.offsets[component, cast(u32, edge)]
                destination[centreLine + cast(u64, x)] = cast(u16, Math.clamp(centre + cast(s32, offset), 0, maximum))
                x += 1
            }
        }

        let pps = unwrap .activePps
        if .sliceParams.count > 1 or not pps.loopFilterAcrossTiles
        {
            let offset = origin + cast(u64, y0) * stride + cast(u64, x0)
            let block  = SaoEdgeBlock{source + offset, destination + offset, stride, rx, ry, width, height}
            .restoreSaoEdges(&block, eoClass)
        }
    }

    // An edge filter may use a sample outside the CTB only when its slice and tile allow it.
    // Interior samples use the same SIMD pass. A diagonal corner compares with the diagonal
    // CTB directly, since the two side neighbours can belong to different slices.
    private mtd const restoreSaoEdges(block: const *SaoEdgeBlock, eoClass: u32)
    {
        let sps     = unwrap .activeSps
        let columns = cast(u64, sps.widthInCtbs)
        let address = cast(u64, block.ry) * columns + cast(u64, block.rx)
        for side in 2
        {
            let dx = cast(s32, SaoEdgeHPos[eoClass, side])
            let dy = cast(s32, SaoEdgeVPos[eoClass, side])
            let nx = block.rx + dx
            let ny = block.ry + dy
            let hasColumn = dx and nx >= 0 and nx < cast(s32, sps.widthInCtbs)
            let hasRow    = dy and ny >= 0 and ny < cast(s32, sps.heightInCtbs)
            let edgeX     = cast(u64, (dx > 0 ? block.width - 1 : 0))
            let edgeY     = cast(u64, (dy > 0 ? block.height - 1 : 0))

            if hasColumn and not .canFilterAcrossBlocks(address, cast(u64, block.ry) * columns + cast(u64, nx))
            {
                let firstY = dy < 0 ? 1 : 0
                let endY   = dy > 0 ? block.height - 1 : block.height
                for y in firstY until endY
                {
                    let index = cast(u64, y) * block.stride + edgeX
                    block.destination[index] = block.source[index]
                }
            }

            if hasRow and not .canFilterAcrossBlocks(address, cast(u64, ny) * columns + cast(u64, block.rx))
            {
                let firstX = dx < 0 ? 1 : 0
                let endX   = dx > 0 ? block.width - 1 : block.width
                let offset = edgeY * block.stride + cast(u64, firstX)
                Memory.copy(block.destination + offset, block.source + offset, cast(u64, (endX - firstX)) * #sizeof(u16))
            }

            if hasColumn and hasRow and not .canFilterAcrossBlocks(address, cast(u64, ny) * columns + cast(u64, nx))
            {
                let corner = edgeY * block.stride + edgeX
                block.destination[corner] = block.source[corner]
            }
        }
    }
}
