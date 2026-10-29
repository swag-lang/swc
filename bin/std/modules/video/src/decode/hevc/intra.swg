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

// Keep the reference and the later filtered/angular workspace disjoint within
// Decoder.residual, which is no longer live while an intra block is predicted.
const IntraScratchOffset = 128'u32
#assert(#sizeof(IntraReference) <= IntraScratchOffset * #sizeof(s32))

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

// Four columns fit in the low lanes; the reference array owns the wider
// load, and each row writes exactly four samples to the prediction buffer.
#[Swag.NoInline]
func predictPlanar4(reference: const *IntraReference, destination: [*] u16)
{
    let top          = Simd.load(&reference.samples[9])
    let leftWeights  = cast(Simd.U16x8, [3'u16, 2, 1, 0, 0, 0, 0, 0])
    let rightWeights = cast(Simd.U16x8, [1'u16, 2, 3, 4, 0, 0, 0, 0])
    let right        = Simd.splat(reference.top(4))
    let bottom       = cast(u32, reference.left(4))
    for y in 4'u32
    {
        let left      = Simd.splat(reference.left(y))
        let topWeight = Simd.splat(cast(u16, (3 - y)))
        let bias      = Simd.splat(cast(u16, ((y + 1) * bottom + 4)))
        let values    = (leftWeights * left + rightWeights * right + topWeight * top + bias) >> 3
        cast([*] u64, (destination + 4 * y))[0] = cast #bit(Simd.U64x2, values)[0]
    }
}

// The planar numerator is at most 2 * 32 * 1023 + 32, so unsigned
// 16-bit lanes hold every intermediate for the supported 8/10-bit profiles.
#[Swag.NoInline]
func predictPlanarPacked(reference: const *IntraReference, destination: [*] u16, size, log2Size: u32)
{
    let indices = cast(Simd.U16x8, [0'u16, 1, 2, 3, 4, 5, 6, 7])
    let right   = Simd.splat(reference.top(size))
    let bottom  = cast(u32, reference.left(size))
    let size8   = Simd.splat(cast(u16, size))
    let one     = Simd.splat(1'u16)
    for y in size
    {
        let left      = Simd.splat(reference.left(y))
        let topWeight = Simd.splat(cast(u16, (size - 1 - y)))
        let bias      = Simd.splat(cast(u16, ((y + 1) * bottom + size)))
        var x         = 0'u32
        while x < size
        {
            let rightWeight = indices + Simd.splat(cast(u16, x)) + one
            let leftWeight  = size8 - rightWeight
            let top         = Simd.load(&reference.samples[2 * size + 1 + x])
            let values      = leftWeight * left + rightWeight * right + topWeight * top + bias
            Simd.store(destination + y * size + x, values >> (log2Size + 1))
            x += 8
        }
    }
}

// Write the vertical angular predictor by rows. Its weighted sum is at most
// 32 * 1023 + 16 for Main10, so unsigned 16-bit lanes are sufficient. The
// reference points into a 160-sample buffer, including for four-wide loads.
#[Swag.NoInline]
func predictAngularVertical(main: const [*] u16, destination: [*] u16, size: u32, angle: s32)
{
    for row in size
    {
        let step   = cast(s32, (row + 1)) * angle
        let shift  = step >> 5
        let blend  = step & 31
        let source = main + cast(s64, (shift + 1))
        let out    = destination + row * size
        if blend == 0
        {
            if size == 4 do
                cast([*] u64, out)[0] = cast(const [*] u64, source)[0]
            else
            {
                var x = 0'u32
                while x < size
                {
                    Simd.store(out + x, Simd.load(source + x))
                    x += 8
                }
            }

            continue
        }

        let firstWeight  = Simd.splat(cast(u16, (32 - blend)))
        let secondWeight = Simd.splat(cast(u16, blend))
        let rounding     = Simd.splat(16'u16)
        if size == 4
        {
            let values = (Simd.load(source) * firstWeight + Simd.load(source + 1) * secondWeight + rounding) >> 5
            cast([*] u64, out)[0] = cast #bit(Simd.U64x2, values)[0]
        }
        else
        {
            var x = 0'u32
            while x < size
            {
                let values = (Simd.load(source + x) * firstWeight + Simd.load(source + x + 1) * secondWeight + rounding) >> 5
                Simd.store(out + x, values)
                x += 8
            }
        }
    }
}

// Compute up to eight samples of one horizontal column. The source points
// into the same padded angular reference used by vertical prediction.
#[Swag.Inline]
private func angularColumn(main: const [*] u16, position: u32, angle: s32)->Simd.U16x8
{
    let step         = cast(s32, (position + 1)) * angle
    let blend        = step & 31
    let source       = main + cast(s64, ((step >> 5) + 1))
    let firstWeight  = Simd.splat(cast(u16, (32 - blend)))
    let secondWeight = Simd.splat(cast(u16, blend))
    return (Simd.load(source) * firstWeight + Simd.load(source + 1) * secondWeight + Simd.splat(16'u16)) >> 5
}

// Transpose four predicted columns into four consecutive four-sample rows.
#[Swag.NoInline]
func predictAngularHorizontal4(main: const [*] u16, destination: [*] u16, angle: s32)
{
    let c0 = angularColumn(main, 0, angle)
    let c1 = angularColumn(main, 1, angle)
    let c2 = angularColumn(main, 2, angle)
    let c3 = angularColumn(main, 3, angle)
    let p0 = cast #bit(Simd.U32x4, Simd.interleaveLow(c0, c1))
    let p1 = cast #bit(Simd.U32x4, Simd.interleaveLow(c2, c3))
    Simd.store(destination, cast #bit(Simd.U16x8, Simd.interleaveLow(p0, p1)))
    Simd.store(destination + 8, cast #bit(Simd.U16x8, Simd.interleaveHigh(p0, p1)))
}

// A zero-angle horizontal prediction repeats one reference sample per row.
#[Swag.NoInline]
func predictAngularHorizontalZero(main: const [*] u16, destination: [*] u16, size: u32)
{
    for y in size
    {
        let values = Simd.splat(main[y + 1])
        let out    = destination + y * size
        if size == 4
        {
            cast([*] u64, out)[0] = cast #bit(Simd.U64x2, values)[0]
        }
        else
        {
            var x = 0'u32
            while x < size
            {
                Simd.store(out + x, values)
                x += 8
            }
        }
    }
}

// Predict an 8x8 tile as eight columns, then transpose it into destination
// rows without a temporary tile. All supported larger sizes are multiples of eight.
#[Swag.NoInline]
func predictAngularHorizontalPacked(main: const [*] u16, destination: [*] u16, size: u32, angle: s32)
{
    var y = 0'u32
    while y < size
    {
        var x = 0'u32
        while x < size
        {
            let ref = main + y
            let c0  = angularColumn(ref, x, angle)
            let c1  = angularColumn(ref, x + 1, angle)
            let c2  = angularColumn(ref, x + 2, angle)
            let c3  = angularColumn(ref, x + 3, angle)
            let c4  = angularColumn(ref, x + 4, angle)
            let c5  = angularColumn(ref, x + 5, angle)
            let c6  = angularColumn(ref, x + 6, angle)
            let c7  = angularColumn(ref, x + 7, angle)
            let a0  = Simd.interleaveLow(c0, c1)
            let a1  = Simd.interleaveLow(c2, c3)
            let a2  = Simd.interleaveLow(c4, c5)
            let a3  = Simd.interleaveLow(c6, c7)
            let a4  = Simd.interleaveHigh(c0, c1)
            let a5  = Simd.interleaveHigh(c2, c3)
            let a6  = Simd.interleaveHigh(c4, c5)
            let a7  = Simd.interleaveHigh(c6, c7)
            let b0  = Simd.interleaveLow(cast #bit(Simd.U32x4, a0), cast #bit(Simd.U32x4, a1))
            let b1  = Simd.interleaveHigh(cast #bit(Simd.U32x4, a0), cast #bit(Simd.U32x4, a1))
            let b2  = Simd.interleaveLow(cast #bit(Simd.U32x4, a2), cast #bit(Simd.U32x4, a3))
            let b3  = Simd.interleaveHigh(cast #bit(Simd.U32x4, a2), cast #bit(Simd.U32x4, a3))
            let b4  = Simd.interleaveLow(cast #bit(Simd.U32x4, a4), cast #bit(Simd.U32x4, a5))
            let b5  = Simd.interleaveHigh(cast #bit(Simd.U32x4, a4), cast #bit(Simd.U32x4, a5))
            let b6  = Simd.interleaveLow(cast #bit(Simd.U32x4, a6), cast #bit(Simd.U32x4, a7))
            let b7  = Simd.interleaveHigh(cast #bit(Simd.U32x4, a6), cast #bit(Simd.U32x4, a7))
            Simd.store(destination + (y + 0) * size + x, cast #bit(Simd.U16x8, Simd.interleaveLow(cast #bit(Simd.U64x2, b0), cast #bit(Simd.U64x2, b2))))
            Simd.store(destination + (y + 1) * size + x, cast #bit(Simd.U16x8, Simd.interleaveHigh(cast #bit(Simd.U64x2, b0), cast #bit(Simd.U64x2, b2))))
            Simd.store(destination + (y + 2) * size + x, cast #bit(Simd.U16x8, Simd.interleaveLow(cast #bit(Simd.U64x2, b1), cast #bit(Simd.U64x2, b3))))
            Simd.store(destination + (y + 3) * size + x, cast #bit(Simd.U16x8, Simd.interleaveHigh(cast #bit(Simd.U64x2, b1), cast #bit(Simd.U64x2, b3))))
            Simd.store(destination + (y + 4) * size + x, cast #bit(Simd.U16x8, Simd.interleaveLow(cast #bit(Simd.U64x2, b4), cast #bit(Simd.U64x2, b6))))
            Simd.store(destination + (y + 5) * size + x, cast #bit(Simd.U16x8, Simd.interleaveHigh(cast #bit(Simd.U64x2, b4), cast #bit(Simd.U64x2, b6))))
            Simd.store(destination + (y + 6) * size + x, cast #bit(Simd.U16x8, Simd.interleaveLow(cast #bit(Simd.U64x2, b5), cast #bit(Simd.U64x2, b7))))
            Simd.store(destination + (y + 7) * size + x, cast #bit(Simd.U16x8, Simd.interleaveHigh(cast #bit(Simd.U64x2, b5), cast #bit(Simd.U64x2, b7))))
            x += 8
        }

        y += 8
    }
}

// Strong smoothing interpolates 63 positions between each edge's endpoints.
// At ten bits the numerator is at most 64 * 1023 + 32, within u16.
#[Swag.NoInline]
func smoothStrongReference(reference: *IntraReference, corner, lastTop, lastLeft: u16)
{
    let ascending  = cast(Simd.U16x8, [1'u16, 2, 3, 4, 5, 6, 7, 8])
    let descending = cast(Simd.U16x8, [8'u16, 7, 6, 5, 4, 3, 2, 1])
    let full       = Simd.splat(64'u16)
    let corner8    = Simd.splat(corner)
    let top8       = Simd.splat(lastTop)
    let left8      = Simd.splat(lastLeft)
    let rounding   = Simd.splat(32'u16)
    var index      = 0'u32
    while index + 8 <= 63
    {
        let base       = Simd.splat(cast(u16, index))
        let topWeight  = base + ascending
        let leftWeight = base + descending
        let top        = ((full - topWeight) * corner8 + topWeight * top8 + rounding) >> 6
        let left       = ((full - leftWeight) * corner8 + leftWeight * left8 + rounding) >> 6
        Simd.store(&reference.samples[65 + index], top)
        Simd.store(&reference.samples[56 - index], left)
        index += 8
    }

    while index < 63
    {
        let weight = index + 1
        reference.setLeft(index, cast(u16, (((64 - weight) * cast(u32, corner) + weight * cast(u32, lastLeft) + 32) >> 6)))
        reference.setTop(index, cast(u16, (((64 - weight) * cast(u32, corner) + weight * cast(u32, lastTop) + 32) >> 6)))
        index += 1
    }
}

const ReverseIntraWords = cast(Simd.U8x16, [14'u8, 15, 12, 13, 10, 11, 8, 9, 6, 7, 4, 5, 2, 3, 0, 1])
const ReverseIntraFour  = cast(Simd.U8x16, [6'u8, 7, 4, 5, 2, 3, 0, 1, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80])

// Copy the main angular reference in prediction order; the left reference is
// stored in reverse, so reverse eight words per step. The only shorter case
// is a four-sample negative-angle block and uses an exact eight-byte load.
#[Swag.NoInline]
func prepareAngularMain(reference: const *IntraReference, main: [*] u16, size: u32, vertical, extended: bool)
{
    main[0] = reference.corner()
    let count = extended ? 2 * size : size
    if count == 4
    {
        if vertical do
            cast([*] u64, (main + 1))[0] = cast(const [*] u64, &reference.samples[2 * size + 1])[0]
        else
        {
            let input    = cast #bit(Simd.U8x16, Simd.splat(cast(const [*] u64, &reference.samples[2 * size - 4])[0]))
            let reversed = Simd.shuffle(input, ReverseIntraFour)
            cast([*] u64, (main + 1))[0] = cast #bit(Simd.U64x2, reversed)[0]
        }

        return
    }

    var index = 0'u32
    while index < count
    {
        if vertical
        {
            Simd.store(main + 1 + index, Simd.load(&reference.samples[2 * size + 1 + index]))
        }
        else
        {
            let input = cast #bit(Simd.U8x16, Simd.load(&reference.samples[2 * size - index - 8]))
            Simd.store(main + 1 + index, cast #bit(Simd.U16x8, Simd.shuffle(input, ReverseIntraWords)))
        }

        index += 8
    }
}

// The corresponding vertical edge is strided in the output block. Reverse
// the contiguous reference lanes, then scatter only the corrected column.
#[Swag.NoInline]
func blendAngularLeftEdge(reference: const *IntraReference, destination: [*] u16, size: u32, maximum: s32)
{
    let top    = Simd.splat(cast(s16, reference.top(0)))
    let corner = Simd.splat(cast(s16, reference.corner()))
    let zero   = Simd.splat(0's16)
    let max    = Simd.splat(cast(s16, maximum))
    if size == 4
    {
        let input  = cast #bit(Simd.U8x16, Simd.splat(cast(const [*] u64, &reference.samples[2 * size - 4])[0]))
        let left   = cast #bit(Simd.S16x8, Simd.shuffle(input, ReverseIntraFour))
        let values = cast #bit(Simd.U16x8, Math.max(Math.min(top + ((left - corner) >> 1), max), zero))
        let packed = cast #bit(Simd.U64x2, values)[0]
        destination[0]        = cast #wrap(u16, packed)
        destination[size]     = cast #wrap(u16, (packed >> 16))
        destination[2 * size] = cast #wrap(u16, (packed >> 32))
        destination[3 * size] = cast #wrap(u16, (packed >> 48))
        return
    }

    var y = 0'u32
    while y < size
    {
        let input  = cast #bit(Simd.U8x16, Simd.load(&reference.samples[2 * size - y - 8]))
        let left   = cast #bit(Simd.S16x8, Simd.shuffle(input, ReverseIntraWords))
        let values = cast #bit(Simd.U16x8, Math.max(Math.min(top + ((left - corner) >> 1), max), zero))
        let packed = cast #bit(Simd.U64x2, values)
        let low    = packed[0]
        let high   = packed[1]
        let out    = destination + y * size
        out[0]        = cast #wrap(u16, low)
        out[size]     = cast #wrap(u16, (low >> 16))
        out[2 * size] = cast #wrap(u16, (low >> 32))
        out[3 * size] = cast #wrap(u16, (low >> 48))
        out[4 * size] = cast #wrap(u16, high)
        out[5 * size] = cast #wrap(u16, (high >> 16))
        out[6 * size] = cast #wrap(u16, (high >> 32))
        out[7 * size] = cast #wrap(u16, (high >> 48))
        y             += 8
    }
}

// The pure horizontal mode corrects its top row from the opposite reference.
// Samples and differences stay within signed 16-bit lanes at ten bits.
#[Swag.NoInline]
func blendAngularTopEdge(reference: const *IntraReference, destination: [*] u16, size: u32, maximum: s32)
{
    let left   = Simd.splat(cast(s16, reference.left(0)))
    let corner = Simd.splat(cast(s16, reference.corner()))
    let zero   = Simd.splat(0's16)
    let max    = Simd.splat(cast(s16, maximum))
    let source = cast(const [*] u16, &reference.samples[2 * size + 1])
    if size == 4
    {
        let top    = cast #bit(Simd.S16x8, Simd.splat(cast(const [*] u64, source)[0]))
        let values = Math.max(Math.min(left + ((top - corner) >> 1), max), zero)
        cast([*] u64, destination)[0] = cast #bit(Simd.U64x2, values)[0]
        return
    }

    var x = 0'u32
    while x < size
    {
        let top    = cast #bit(Simd.S16x8, Simd.load(source + x))
        let values = Math.max(Math.min(left + ((top - corner) >> 1), max), zero)
        Simd.store(destination + x, cast #bit(Simd.U16x8, values))
        x += 8
    }
}

impl Decoder
{
    // Predicts one intra transform block into `.predSamples`, clause 8.4.4.2.
    //
    // `(x, y)` is the position of the block in samples of its own component, and `xLuma`,
    // `yLuma` the same position in luma samples, which is what availability is answered in.
    mtd intraPredict(x, y, xLuma, yLuma: s32, log2Size, component, mode: u32)
    {
        let sps      = unwrap .activeSps
        let size     = 1'u32 << log2Size
        let bitDepth = component == 0 ? sps.bitDepthLuma : sps.bitDepthChroma

        let reference = cast(*IntraReference, &.residual[0])
        .gatherReference(reference, x, y, xLuma, yLuma, size, component, bitDepth)
        .filterReference(reference, size, log2Size, component, mode, bitDepth)

        switch
        {
        case mode == IntraPlanar:
            if size >= 8 do
                predictPlanarPacked(reference, &.predSamples[0], size, log2Size)
            else do
                predictPlanar4(reference, &.predSamples[0])

        case mode == IntraDc:
            .predictDc(reference, size, log2Size, component)

        default:
            .predictAngular(reference, size, component, mode, bitDepth)
        }
    }

    // Collects the neighbouring samples of one block and substitutes the ones that are missing,
    // clauses 8.4.4.2.1 and 8.4.4.2.2.
    mtd gatherReference(reference: *IntraReference, x, y, xLuma, yLuma: s32, size, component, bitDepth: u32)
    {
        let pps   = unwrap .activePps
        let total = size * 2
        let scale = component == 0 ? 1's32 : 2's32

        reference.size  = size
        reference.count = total * 2 + 1

        // Availability is uniform inside a four-sample luma block, so it is answered once per
        // group rather than once per sample.
        let step = component == 0 ? 4'u32 : 2'u32

        // The corner.
        let cornerAvailable = .isIntraNeighbourAvailable(xLuma, yLuma, xLuma - 1, yLuma - 1, pps.constrainedIntraPred)
        reference.available[size * 2] = cornerAvailable
        if cornerAvailable do
            reference.setCorner(.reconstructedSample(component, x - 1, y - 1))

        // The left column, downward.
        var offset = 0'u32
        while offset < total
        {
            let sampleY   = y + cast(s32, offset)
            let available = .isIntraNeighbourAvailable(xLuma, yLuma, xLuma - 1, yLuma + cast(s32, offset) * scale, pps.constrainedIntraPred)

            // Left samples come from successive rows and land in reverse order.
            let index = size * 2 - offset - step
            if component == 0
            {
                cast([*] u32, &reference.available[index])[0] = available ? 0x01010101'u32 : 0'u32
                if available
                {
                    let frame   = unwrap .current
                    let samples = unwrap frame.lumaAt(x - 1, sampleY)
                    let stride  = frame.strideLuma
                    let values  = (cast(u64, samples[0]) << 48) | (cast(u64, samples[stride]) << 32) |
                                  (cast(u64, samples[2 * stride]) << 16) | cast(u64, samples[3 * stride])
                    cast([*] u64, &reference.samples[index])[0] = values
                }
            }
            else
            {
                cast([*] u16, &reference.available[index])[0] = available ? 0x0101'u16 : 0'u16
                if available
                {
                    let frame   = unwrap .current
                    let samples = frame.chromaAtMutable(component - 1, x - 1, sampleY)
                    let values  = (cast(u32, samples[0]) << 16) | cast(u32, samples[frame.strideChroma])
                    cast([*] u32, &reference.samples[index])[0] = values
                }
            }

            offset += step
        }

        // The top row, rightward.
        offset = 0
        while offset < total
        {
            let sampleX   = x + cast(s32, offset)
            let available = .isIntraNeighbourAvailable(xLuma, yLuma, xLuma + cast(s32, offset) * scale, yLuma - 1, pps.constrainedIntraPred)

            // Both supported group sizes divide the reference length. Adjacent
            // top samples are contiguous in the padded plane and reference array.
            let index = size * 2 + 1 + offset
            if component == 0
            {
                cast([*] u32, &reference.available[index])[0] = available ? 0x01010101'u32 : 0'u32
                if available
                {
                    let frame   = unwrap .current
                    let samples = unwrap frame.lumaAt(sampleX, y - 1)
                    cast([*] u64, &reference.samples[index])[0] = cast(const [*] u64, samples)[0]
                }
            }
            else
            {
                cast([*] u16, &reference.available[index])[0] = available ? 0x0101'u16 : 0'u16
                if available
                {
                    let frame   = unwrap .current
                    let samples = frame.chromaAtMutable(component - 1, sampleX, y - 1)
                    cast([*] u32, &reference.samples[index])[0] = cast(const [*] u32, samples)[0]
                }
            }

            offset += step
        }

        .substituteReference(reference, bitDepth)
    }

    // Reports whether a neighbouring sample may be used for intra prediction, clause 8.4.4.2.1.
    private mtd const isIntraNeighbourAvailable(xCurr, yCurr, xNb, yNb: s32, constrained: bool)->bool
    {
        if not .isAvailable(xCurr, yCurr, xNb, yNb) do
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
            let midpoint = cast(u16, (1'u32 << (bitDepth - 1)))
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
            if not reference.available[index] do
                reference.samples[index] = reference.samples[index - 1]
        }
    }

    // Smooths the reference samples when the prediction direction calls for it, clause 8.4.4.2.3.
    mtd filterReference(reference: *IntraReference, size, log2Size, component, mode, bitDepth: u32)
    {
        let sps = unwrap .activeSps
        if component != 0 or size == 4 or mode == IntraDc or sps.intraSmoothingDisabled do
            return

        let distance = Math.min(Math.abs(cast(s32, mode) - 26), Math.abs(cast(s32, mode) - 10))
        if distance <= cast(s32, IntraSmoothingThreshold[log2Size - 2]) do
            return

        let total = size * 2

        // A large flat block is interpolated between its corners instead of smoothed, which is
        // what keeps a gradient from banding, clause 8-37.
        if sps.strongIntraSmoothing and size == 32
        {
            let limit    = 1's32 << (bitDepth - 5)
            let corner   = cast(s32, reference.corner())
            let flatTop  = Math.abs(corner + cast(s32, reference.top(total - 1)) - 2 * cast(s32, reference.top(size - 1))) < limit
            let flatLeft = Math.abs(corner + cast(s32, reference.left(total - 1)) - 2 * cast(s32, reference.left(size - 1))) < limit
            if flatTop and flatLeft
            {
                smoothStrongReference(reference, cast(u16, corner), reference.top(63), reference.left(63))

                return
            }
        }

        // The left edge is stored in reverse order and the top edge in forward
        // order, but the three-tap kernel is symmetric on the whole sequence.
        let filtered = cast([*] u16, &.residual[IntraScratchOffset])
        filtered[0] = reference.samples[0]
        var index    = 1'u32
        let end      = reference.count - 1
        let rounding = Simd.splat(2'u16)
        while index + 8 <= end
        {
            let previous = Simd.load(&reference.samples[index - 1])
            let current  = Simd.load(&reference.samples[index])
            let next     = Simd.load(&reference.samples[index + 1])
            Simd.store(filtered + index, (previous + current + current + next + rounding) >> 2)
            index += 8
        }

        while index < end
        {
            let value = cast(u32, reference.samples[index - 1]) + 2 * cast(u32, reference.samples[index]) + cast(u32, reference.samples[index + 1]) + 2
            filtered[index] = cast(u16, (value >> 2))
            index += 1
        }

        filtered[end] = reference.samples[end]
        Memory.copy(&reference.samples, filtered, cast(u64, reference.count) * #sizeof(u16))
    }

    // Predicts a flat block, clause 8.4.4.2.5.
    mtd predictDc(reference: const *IntraReference, size, log2Size, component: u32)
    {
        // The left samples run in reverse order, but their sum is unchanged.
        // Eight 10-bit top/left pairs accumulated over a 32-wide block sum
        // to at most 65472, which fits in unsigned 16-bit lanes.
        var sums = Simd.splat(0'u16)
        if size == 4
        {
            let top  = cast #bit(Simd.U16x8, Simd.splat(cast(const [*] u64, &reference.samples[2 * size + 1])[0]))
            let left = cast #bit(Simd.U16x8, Simd.splat(cast(const [*] u64, &reference.samples[size])[0]))
            sums = top + left
        }
        else
        {
            var index = 0'u32
            while index < size
            {
                sums  += Simd.load(&reference.samples[2 * size + 1 + index]) + Simd.load(&reference.samples[size + index])
                index += 8
            }
        }

        let total = cast(u32, Simd.sum(sums))
        let sum   = size + (size == 4 ? total >> 1 : total)
        let dc    = sum >> (log2Size + 1)

        let values = Simd.splat(cast(u16, dc))
        var index  = 0'u32
        while index < size * size
        {
            Simd.store(&.predSamples[index], values)
            index += 8
        }

        // The edges of a small luma block are blended with their neighbours, which is what keeps
        // a flat prediction from showing its own boundary.
        if component != 0 or size >= 32 do
            return

        .predSamples[0] = cast(u16, ((cast(u32, reference.left(0)) + 2 * dc + cast(u32, reference.top(0)) + 2) >> 2))
        var x = 1'u32
        if size == 16
        {
            let bias = Simd.splat(cast(u16, (3 * dc + 2)))
            let top  = Simd.load(&reference.samples[2 * size + 2])
            Simd.store(&.predSamples[1], (top + bias) >> 2)
            x = 9
        }

        while x < size
        {
            .predSamples[x] = cast(u16, ((cast(u32, reference.top(x)) + 3 * dc + 2) >> 2))
            x += 1
        }

        for y in 1 until size do
            .predSamples[y * size] = cast(u16, ((cast(u32, reference.left(y)) + 3 * dc + 2) >> 2))
    }

    // Predicts a directional block, clause 8.4.4.2.6.
    mtd predictAngular(reference: const *IntraReference, size, component, mode, bitDepth: u32)
    {
        let angle    = cast(s32, IntraPredAngle[mode])
        let vertical = mode >= 18
        let maximum  = cast(s32, ((1'u32 << bitDepth) - 1))

        // The main reference runs along the direction the prediction comes from, and is extended
        // backwards through the other edge when the angle is negative.
        // Residual samples are consumed before the next prediction and are
        // reconstructed again afterwards. Reuse their storage for this reference
        // rather than clearing a fresh 160-sample temporary for every block.
        let main   = cast([*] u16, &.residual[IntraScratchOffset])
        let origin = 64'u32     // Index of ref[0] inside the array, leaving room for ref[-32..-1].

        prepareAngularMain(reference, &main[origin], size, vertical, angle >= 0)

        if angle < 0
        {
            let limit = (cast(s32, size) * angle) >> 5
            if limit < -1
            {
                let inverse = cast(s32, IntraInvAngle[mode])
                var index   = -1's32
                while index >= limit
                {
                    let position = -1 + ((index * inverse + 128) >> 8)
                    var value: u16
                    if position < 0 do
                        value = reference.corner()
                    else do
                        value = vertical ? reference.left(cast(u32, position)) : reference.top(cast(u32, position))
                    main[cast(u32, (cast(s32, origin) + index))] = value
                    index -= 1
                }
            }
        }

        if vertical
        {
            predictAngularVertical(&main[origin], &.predSamples[0], size, angle)
        }
        elif angle == 0
        {
            predictAngularHorizontalZero(&main[origin], &.predSamples[0], size)
        }
        elif size == 4
        {
            predictAngularHorizontal4(&main[origin], &.predSamples[0], angle)
        }
        else
        {
            predictAngularHorizontalPacked(&main[origin], &.predSamples[0], size, angle)
        }

        // The edge next to the reference the prediction did not read is blended with it, which is
        // what keeps a purely horizontal or vertical prediction from showing a step.
        if component != 0 or size >= 32 do
            return

        if mode == IntraAngular26
        {
            blendAngularLeftEdge(reference, &.predSamples[0], size, maximum)
        }
        elif mode == IntraAngular10
        {
            blendAngularTopEdge(reference, &.predSamples[0], size, maximum)
        }
    }
}
