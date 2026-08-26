//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns intra luma and chroma prediction.
//
#global namespace Hevc
#global internal

using Core

// Table 8-4: above this distance from the horizontal and vertical directions, the neighbouring
// samples are smoothed before an angular prediction reads them.
const IntraSmoothingThreshold: [4] u8 = [0, 7, 1, 0]

// The reference samples of one intra prediction, in the order clause 8.4.4.2.2 substitutes them.
//
// Index `2 * nTbS` holds the corner. Below it the left column runs upward, and above it the top
// row runs rightward, so a single forward pass fills every sample that was not available.
struct IntraReference
{
    samples:   [129] u16
    available: [129] bool
    count:     u32     // Samples in use, which is `4 * nTbS + 1`.
    size:      u32     // nTbS.
}

impl IntraReference
{
    #[Swag.Inline]
    mtd const left(y: u32)->u16 => .samples[.size * 2 - 1 - y]

    #[Swag.Inline]
    mtd const corner()->u16 => .samples[.size * 2]

    #[Swag.Inline]
    mtd const top(x: u32)->u16 => .samples[.size * 2 + 1 + x]

    #[Swag.Inline]
    mtd setLeft(y: u32, value: u16) { .samples[.size * 2 - 1 - y] = value }

    #[Swag.Inline]
    mtd setCorner(value: u16) { .samples[.size * 2] = value }

    #[Swag.Inline]
    mtd setTop(x: u32, value: u16) { .samples[.size * 2 + 1 + x] = value }
}

impl Decoder
{
    // Predicts one intra transform block into `.predSamples`, clause 8.4.4.2.
    //
    // `(x, y)` is the position of the block in samples of its own component, and `xLuma`,
    // `yLuma` the same position in luma samples, which is what availability is answered in.
    mtd intraPredict(x, y, xLuma, yLuma: s32, log2Size, component, mode: u32)
    {
        let sps      = .activeSps!
        let size     = 1'u32 << log2Size
        let bitDepth = component == 0 ? sps.bitDepthLuma : sps.bitDepthChroma

        var reference: IntraReference
        .gatherReference(&reference, x, y, xLuma, yLuma, size, component, bitDepth)
        .filterReference(&reference, size, log2Size, component, mode, bitDepth)

        switch
        {
        case mode == IntraPlanar: .predictPlanar(&reference, size, log2Size)
        case mode == IntraDc:     .predictDc(&reference, size, log2Size, component)
        default:                  .predictAngular(&reference, size, component, mode, bitDepth)
        }
    }

    // Collects the neighbouring samples of one block and substitutes the ones that are missing,
    // clauses 8.4.4.2.1 and 8.4.4.2.2.
    private mtd gatherReference(reference: *IntraReference, x, y, xLuma, yLuma: s32, size, component, bitDepth: u32)
    {
        let sps   = .activeSps!
        let pps   = .activePps!
        let frame = .current!
        let total = size * 2
        let scale = component == 0 ? 1's32 : 2's32

        reference.size  = size
        reference.count = total * 2 + 1

        // Availability is uniform inside a four-sample luma block, so it is answered once per
        // group rather than once per sample.
        let step = component == 0 ? 4'u32 : 2'u32

        discard frame

        // The corner.
        let cornerAvailable = .isIntraNeighbourAvailable(xLuma, yLuma, xLuma - 1, yLuma - 1, pps.constrainedIntraPred)
        reference.available[size * 2] = cornerAvailable
        if cornerAvailable do
            reference.setCorner(.reconstructedSample(component, x - 1, y - 1))

        // The left column, downward.
        var offset = 0'u32
        while offset < total
        {
            let sampleY   = y + cast(s32) offset
            let available = .isIntraNeighbourAvailable(xLuma, yLuma, xLuma - 1, yLuma + cast(s32) offset * scale, pps.constrainedIntraPred)
            for inner in step
            {
                let index = offset + inner
                if index >= total do
                    break
                reference.available[size * 2 - 1 - index] = available
                if available do
                    reference.setLeft(index, .reconstructedSample(component, x - 1, sampleY + cast(s32) inner))
            }

            offset += step
        }

        // The top row, rightward.
        offset = 0
        while offset < total
        {
            let sampleX   = x + cast(s32) offset
            let available = .isIntraNeighbourAvailable(xLuma, yLuma, xLuma + cast(s32) offset * scale, yLuma - 1, pps.constrainedIntraPred)
            for inner in step
            {
                let index = offset + inner
                if index >= total do
                    break
                reference.available[size * 2 + 1 + index] = available
                if available do
                    reference.setTop(index, .reconstructedSample(component, sampleX + cast(s32) inner, y - 1))
            }

            offset += step
        }

        .substituteReference(reference, bitDepth)
    }

    // Reports whether a neighbouring sample may be used for intra prediction, clause 8.4.4.2.1.
    private mtd const isIntraNeighbourAvailable(xCurr, yCurr, xNb, yNb: s32, constrained: bool)->bool
    {
        if !.isAvailable(xCurr, yCurr, xNb, yNb) do
            return false

        // Constrained intra prediction refuses everything an inter block reconstructed, so a
        // picture stays decodable when the pictures it predicted from were lost.
        if constrained and .predMode[.blockIndex(xNb, yNb)] != ModeIntra do
            return false
        return true
    }

    // Fills the reference samples that were not available, clause 8.4.4.2.2.
    private mtd const substituteReference(reference: *IntraReference, bitDepth: u32)
    {
        let count = reference.count

        var firstAvailable = count
        for index in count where reference.available[index]
        {
            firstAvailable = index
            break
        }

        if firstAvailable == count
        {
            // Nothing around the block was decoded: the whole reference is the midpoint of the
            // sample range.
            let midpoint = cast(u16) (1'u32 << (bitDepth - 1))
            for index in count do
                reference.samples[index] = midpoint
            return
        }

        // The search runs from the bottom of the left column upward and then along the top row,
        // which is exactly the order the array is laid out in.
        for index in firstAvailable do
            reference.samples[index] = reference.samples[firstAvailable]
        for index in firstAvailable + 1 until count
        {
            if !reference.available[index] do
                reference.samples[index] = reference.samples[index - 1]
        }
    }

    // Smooths the reference samples when the prediction direction calls for it, clause 8.4.4.2.3.
    private mtd const filterReference(reference: *IntraReference, size, log2Size, component, mode, bitDepth: u32)
    {
        let sps = .activeSps!
        if component != 0 or size == 4 or mode == IntraDc or sps.intraSmoothingDisabled do
            return

        let distance = Math.min(Math.abs(cast(s32) mode - 26), Math.abs(cast(s32) mode - 10))
        if distance <= cast(s32) IntraSmoothingThreshold[log2Size - 2] do
            return

        let total = size * 2

        // A large flat block is interpolated between its corners instead of smoothed, which is
        // what keeps a gradient from banding, clause 8-37.
        if sps.strongIntraSmoothing and size == 32
        {
            let limit    = 1's32 << (bitDepth - 5)
            let corner   = cast(s32) reference.corner()
            let flatTop  = Math.abs(corner + cast(s32) reference.top(total - 1) - 2 * cast(s32) reference.top(size - 1)) < limit
            let flatLeft = Math.abs(corner + cast(s32) reference.left(total - 1) - 2 * cast(s32) reference.left(size - 1)) < limit
            if flatTop and flatLeft
            {
                let lastTop  = cast(s32) reference.top(63)
                let lastLeft = cast(s32) reference.left(63)
                for index in 63'u32
                {
                    reference.setLeft(index, cast(u16) ((cast(s32) (63 - index) * corner + cast(s32) (index + 1) * lastLeft + 32) >> 6))
                    reference.setTop(index, cast(u16) ((cast(s32) (63 - index) * corner + cast(s32) (index + 1) * lastTop + 32) >> 6))
                }

                return
            }
        }

        var filtered: [129] u16 = undefined
        filtered[size * 2] = cast(u16) ((cast(u32) reference.left(0) + 2 * cast(u32) reference.corner() + cast(u32) reference.top(0) + 2) >> 2)
        for index in total - 1
        {
            let previousLeft = index == 0 ? reference.corner() : reference.left(index - 1)
            let previousTop  = index == 0 ? reference.corner() : reference.top(index - 1)
            filtered[size * 2 - 1 - index] = cast(u16) ((cast(u32) reference.left(index + 1) + 2 * cast(u32) reference.left(index) + cast(u32) previousLeft + 2) >> 2)
            filtered[size * 2 + 1 + index] = cast(u16) ((cast(u32) reference.top(index + 1) + 2 * cast(u32) reference.top(index) + cast(u32) previousTop + 2) >> 2)
        }

        filtered[0] = reference.samples[0]
        filtered[reference.count - 1] = reference.samples[reference.count - 1]
        Memory.copy(&reference.samples, &filtered, cast(u64) reference.count * #sizeof(u16))
    }

    // Predicts a planar block, clause 8.4.4.2.4.
    private mtd predictPlanar(reference: const *IntraReference, size, log2Size: u32)
    {
        let shift      = log2Size + 1
        let rightTop   = cast(u32) reference.top(size)
        let bottomLeft = cast(u32) reference.left(size)
        for y in size
        {
            let leftSample = cast(u32) reference.left(y)
            for x in size
            {
                let value = (size - 1 - x) * leftSample + (x + 1) * rightTop + (size - 1 - y) * cast(u32) reference.top(x) + (y + 1) * bottomLeft + size
                .predSamples[y * size + x] = cast(u16) (value >> shift)
            }
        }
    }

    // Predicts a flat block, clause 8.4.4.2.5.
    private mtd predictDc(reference: const *IntraReference, size, log2Size, component: u32)
    {
        var sum = size
        for index in size do
            sum += cast(u32) reference.top(index) + cast(u32) reference.left(index)
        let dc = sum >> (log2Size + 1)

        for index in size * size do
            .predSamples[index] = cast(u16) dc

        // The edges of a small luma block are blended with their neighbours, which is what keeps
        // a flat prediction from showing its own boundary.
        if component != 0 or size >= 32 do
            return

        .predSamples[0] = cast(u16) ((cast(u32) reference.left(0) + 2 * dc + cast(u32) reference.top(0) + 2) >> 2)
        for x in 1 until size do
            .predSamples[x] = cast(u16) ((cast(u32) reference.top(x) + 3 * dc + 2) >> 2)
        for y in 1 until size do
            .predSamples[y * size] = cast(u16) ((cast(u32) reference.left(y) + 3 * dc + 2) >> 2)
    }

    // Predicts a directional block, clause 8.4.4.2.6.
    private mtd predictAngular(reference: const *IntraReference, size, component, mode, bitDepth: u32)
    {
        let angle    = cast(s32) IntraPredAngle[mode]
        let vertical = mode >= 18
        let maximum  = cast(s32) ((1'u32 << bitDepth) - 1)

        // The main reference runs along the direction the prediction comes from, and is extended
        // backwards through the other edge when the angle is negative.
        var main: [160] u16 = undefined
        let origin          = 64'u32     // Index of ref[0] inside the array, leaving room for ref[-32..-1].

        for index in size + 1
        {
            main[origin + index] = index == 0 ? reference.corner() : (vertical ? reference.top(index - 1) : reference.left(index - 1))
        }

        if angle < 0
        {
            let limit = (cast(s32) size * angle) >> 5
            if limit < -1
            {
                let inverse = cast(s32) IntraInvAngle[mode]
                var index   = -1's32
                while index >= limit
                {
                    let position = -1 + ((index * inverse + 128) >> 8)
                    var value: u16
                    if position < 0 do
                        value = reference.corner()
                    else do
                        value = vertical ? reference.left(cast(u32) position) : reference.top(cast(u32) position)
                    main[cast(u32) (cast(s32) origin + index)] = value
                    index -= 1
                }
            }
        }
        else
        {
            for index in size + 1 to size * 2 do
                main[origin + index] = vertical ? reference.top(index - 1) : reference.left(index - 1)
        }

        for outer in size
        {
            let step  = cast(s32) (outer + 1) * angle
            let shift = step >> 5
            let blend = step & 31
            for inner in size
            {
                let base = cast(u32) (cast(s32) origin + cast(s32) inner + shift + 1)
                var value: u32
                if blend != 0 do
                    value = (cast(u32) (32 - blend) * cast(u32) main[base] + cast(u32) blend * cast(u32) main[base + 1] + 16) >> 5
                else do
                    value = cast(u32) main[base]

                if vertical do
                    .predSamples[outer * size + inner] = cast(u16) value
                else do
                    .predSamples[inner * size + outer] = cast(u16) value
            }
        }

        // The edge next to the reference the prediction did not read is blended with it, which is
        // what keeps a purely horizontal or vertical prediction from showing a step.
        if component != 0 or size >= 32 do
            return

        let corner = cast(s32) reference.corner()
        if mode == IntraAngular26
        {
            for y in size do
                .predSamples[y * size] = cast(u16) Math.clamp(cast(s32) reference.top(0) + ((cast(s32) reference.left(y) - corner) >> 1), 0, maximum)
        }
        elif mode == IntraAngular10
        {
            for x in size do
                .predSamples[x] = cast(u16) Math.clamp(cast(s32) reference.left(0) + ((cast(s32) reference.top(x) - corner) >> 1), 0, maximum)
        }
    }
}
