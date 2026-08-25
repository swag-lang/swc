#global namespace Hevc
#global internal

using Core

// Returns the sign of a difference, which is what an edge offset class is derived from.
#[Swag.Inline]
private func signOf(value: s32)->s32 => value > 0 ? 1 : (value < 0 ? -1 : 0)

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

impl Decoder
{
    // Reads the sample adaptive offset parameters of one coding tree block, clause 7.3.8.3.
    mtd readSaoParameters(rx, ry: s32) fail
    {
        let sps    = .activeSps!
        let header = &.header
        let index  = cast(u64) ry * cast(u64) sps.widthInCtbs + cast(u64) rx

        var merged = false
        if rx > 0
        {
            let leftInSlice = .ctbAddrRs > .sliceAddrRs
            let leftInTile  = .tileId[.ctbAddrTs] == .tileId[.ctbRsToTs[.ctbAddrRs - 1]]
            if leftInSlice and leftInTile and .cabac.decision(CtxSaoMergeFlag) != 0
            {
                .sao[index] = .sao[index - 1]
                .saoUsed  = .saoUsed or .sao[index].typeIdx[0] != 0 or .sao[index].typeIdx[1] != 0
                merged = true
            }
        }

        if !merged and ry > 0
        {
            let upInSlice = .ctbAddrRs >= .sliceAddrRs + sps.widthInCtbs
            let upInTile  = .tileId[.ctbAddrTs] == .tileId[.ctbRsToTs[.ctbAddrRs - sps.widthInCtbs]]
            if upInSlice and upInTile and .cabac.decision(CtxSaoMergeFlag) != 0
            {
                .sao[index] = .sao[index - cast(u64) sps.widthInCtbs]
                .saoUsed  = .saoUsed or .sao[index].typeIdx[0] != 0 or .sao[index].typeIdx[1] != 0
                merged = true
            }
        }

        if merged do
            return

        var parameters: SaoParameters
        let maximumOffset = (1'u32 << (Math.min(sps.bitDepthLuma, 10'u32) - 5)) - 1

        for component in 3'u32
        {
            if (component == 0 and !header.saoLuma) or (component > 0 and !header.saoChroma) do
                continue

            // The two chroma components share one type and one class, stated with the first.
            var kind = 0'u32
            if component < 2
            {
                if .cabac.decision(CtxSaoTypeIdx) != 0 do
                    kind = .cabac.bypass() != 0 ? 2'u32 : 1'u32
            }
            else
            {
                kind = cast(u32) parameters.typeIdx[1]
            }

            parameters.typeIdx[component] = cast(u8) kind
            if !kind do
                continue

            var magnitude: [4] u32
            for entry in 4'u32
            {
                var value = 0'u32
                while value < maximumOffset and .cabac.bypass() != 0 do
                    value += 1
                magnitude[entry] = value
            }

            if kind == 1
            {
                for entry in 4'u32
                {
                    var value = cast(s16) magnitude[entry]
                    if magnitude[entry] != 0 and .cabac.bypass() != 0 do
                        value = -value
                    parameters.offsets[component, entry + 1] = value
                }

                parameters.bandPosition[component] = cast(u8) .cabac.bypassBits(5)
            }
            else
            {
                // An edge offset states magnitudes only: the first two raise a sample and the
                // last two lower it, clause 7.4.9.3.
                parameters.offsets[component, 1] = cast(s16) magnitude[0]
                parameters.offsets[component, 2] = cast(s16) magnitude[1]
                parameters.offsets[component, 3] = -cast(s16) magnitude[2]
                parameters.offsets[component, 4] = -cast(s16) magnitude[3]
                if component < 2 do
                    parameters.eoClass[component] = cast(u8) .cabac.bypassBits(2)
                else do
                    parameters.eoClass[2] = parameters.eoClass[1]
            }
        }

        .sao[index] = parameters
        if parameters.typeIdx[0] != 0 or parameters.typeIdx[1] != 0 or parameters.typeIdx[2] != 0 do
            .saoUsed = true
    }

    // Applies the sample adaptive offset of every coding tree block, clause 8.7.3.
    //
    // The filter reads the deblocked picture and writes a new one, so the samples one block reads
    // are never the ones an earlier block wrote; the deblocked picture is kept aside for that.
    mtd applySampleAdaptiveOffset()
    {
        let sps = .activeSps!
        if !sps.saoEnabled or !.saoUsed do
            return

        let frame = .current!
        .saoSource.resize(frame.luma.count)
        .saoSourceChromaB.resize(frame.chromaB.count)
        .saoSourceChromaR.resize(frame.chromaR.count)
        Memory.copy(.saoSource.buffer!, frame.luma.buffer!, frame.luma.count * #sizeof(u16))
        Memory.copy(.saoSourceChromaB.buffer!, frame.chromaB.buffer!, frame.chromaB.count * #sizeof(u16))
        Memory.copy(.saoSourceChromaR.buffer!, frame.chromaR.buffer!, frame.chromaR.count * #sizeof(u16))

        for ry in sps.heightInCtbs
        {
            for rx in sps.widthInCtbs
            {
                let parameters = &.sao[cast(u64) ry * cast(u64) sps.widthInCtbs + cast(u64) rx]
                for component in 3'u32
                {
                    if !parameters.typeIdx[component] do
                        continue
                    .applySaoBlock(parameters, component, cast(s32) rx, cast(s32) ry)
                }
            }
        }
    }

    // Applies one block's offsets to one component, clause 8.7.3.2.
    private mtd applySaoBlock(parameters: const *SaoParameters, component: u32, rx, ry: s32)
    {
        let sps      = .activeSps!
        let frame    = .current!
        let scale    = component == 0 ? 1's32 : 2's32
        let bitDepth = component == 0 ? sps.bitDepthLuma : sps.bitDepthChroma
        let maximum  = cast(s32) ((1'u32 << bitDepth) - 1)

        let ctbSize    = cast(s32) sps.ctbSize / scale
        let planeWidth  = cast(s32) (component == 0 ? sps.width : sps.width / sps.subWidthC)
        let planeHeight = cast(s32) (component == 0 ? sps.height : sps.height / sps.subHeightC)
        let x0 = rx * ctbSize
        let y0 = ry * ctbSize
        let width  = Math.min(ctbSize, planeWidth - x0)
        let height = Math.min(ctbSize, planeHeight - y0)
        if width <= 0 or height <= 0 do
            return

        var source: const [*] u16 = undefined
        var destination: [*] u16 = undefined
        var stride: u64
        if !component
        {
            source      = .saoSource.buffer!
            destination = frame.luma.buffer!
            stride      = frame.strideLuma
        }
        else
        {
            source      = component == 1 ? .saoSourceChromaB.buffer! : .saoSourceChromaR.buffer!
            destination = component == 1 ? frame.chromaB.buffer! : frame.chromaR.buffer!
            stride      = frame.strideChroma
        }

        let origin = cast(u64) FramePadding * stride + cast(u64) FramePadding

        if parameters.typeIdx[component] == 1
        {
            // Band offset: four consecutive bands of the sample range are shifted.
            var bands: [32] s16
            let position = cast(u32) parameters.bandPosition[component]
            for entry in 4'u32 do
                bands[(position + entry) & 31] = parameters.offsets[component, entry + 1]

            let shift = bitDepth - 5
            for row in height
            {
                let line = origin + cast(u64) (y0 + row) * stride + cast(u64) x0
                for column in width
                {
                    let value = cast(s32) source[line + cast(u64) column]
                    let band  = bands[cast(u32) value >> shift]
                    if band != 0 do
                        destination[line + cast(u64) column] = cast(u16) Math.clamp(value + cast(s32) band, 0, maximum)
                }
            }

            return
        }

        // Edge offset: a sample is shifted by how it compares with two neighbours.
        let eoClass = cast(u32) parameters.eoClass[component]
        let h0 = cast(s32) SaoEdgeHPos[eoClass, 0]
        let h1 = cast(s32) SaoEdgeHPos[eoClass, 1]
        let v0 = cast(s32) SaoEdgeVPos[eoClass, 0]
        let v1 = cast(s32) SaoEdgeVPos[eoClass, 1]

        for row in height
        {
            let y = y0 + row
            for column in width
            {
                let x = x0 + column

                // A sample whose comparison would leave the picture is left alone.
                if x + h0 < 0 or x + h0 >= planeWidth or x + h1 < 0 or x + h1 >= planeWidth do
                    continue
                if y + v0 < 0 or y + v0 >= planeHeight or y + v1 < 0 or y + v1 >= planeHeight do
                    continue

                let centre = cast(s32) source[origin + cast(u64) y * stride + cast(u64) x]
                let first  = cast(s32) source[origin + cast(u64) (y + v0) * stride + cast(u64) (x + h0)]
                let second = cast(s32) source[origin + cast(u64) (y + v1) * stride + cast(u64) (x + h1)]

                var edge = 2 + signOf(centre - first) + signOf(centre - second)
                if edge <= 2 do
                    edge = edge == 2 ? 0 : edge + 1

                let offset = parameters.offsets[component, cast(u32) edge]
                if offset != 0 do
                    destination[origin + cast(u64) y * stride + cast(u64) x] = cast(u16) Math.clamp(centre + cast(s32) offset, 0, maximum)
            }
        }
    }
}
