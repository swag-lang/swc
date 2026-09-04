//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns picture storage, edge extension, collocated motion, and planar export.
//
#global namespace Hevc
#global internal

using Core, Core.Errors, Core.Math

// Padding kept around each plane so motion compensation can read past the picture edge.
//
// The luma interpolator reads three samples before a block and four after it, so a motion vector
// pointing just outside the picture still lands inside the padded storage once the edges are
// replicated. Longer excursions clamp through the bounded fallback of the interpolator.
const FramePadding = 80'u32

// The granularity the standard stores collocated motion at, clause 8.5.3.2.8.
//
// Temporal prediction rounds the collocated position down to a sixteen-sample grid, so a picture
// only has to keep one motion record per sixteen samples rather than one per prediction block.
const ColMotionLog2 = 4'u32

// Published when a picture will never finish, so nothing waits on it forever.
const FrameProgressFailed = -1's32

// The motion one 16x16 region of a reference picture exports to temporal prediction.
//
// Scaling a temporal candidate needs the distance between the collocated picture and what that
// picture predicted from, so the record carries the referenced picture's order count rather than
// its index: the index means nothing once the reference lists have moved on.
struct ColMotion
{
    mv:          [2, 2] s16     // [list][component], in quarter samples.
    refPoc:      [2] s32        // Order count of the picture each list referred to.
    predFlags:   u8             // Bit 0 for list 0, bit 1 for list 1; zero for an intra region.
    longTermRef: u8             // Same bits, set when that reference was a long-term picture.
}

// How a picture is marked in the decoded picture buffer, clause 8.3.2.
enum FrameMarking
{
    Unused
    ShortTerm
    LongTerm
}

// One decoded picture: padded 4:2:0 planes at the stream's bit depth, plus the reference state
// and the collocated motion later pictures read from it.
//
// Samples are sixteen bits whatever the bit depth. A Main 10 stream needs ten, and holding eight
// and ten bit streams in one layout keeps the reconstruction free of a second set of paths.
struct Frame
{
    luma:          Array'u16     // Padded luma plane.
    chromaB:       Array'u16     // Padded blue-difference plane.
    chromaR:       Array'u16     // Padded red-difference plane.
    strideLuma:    u64
    strideChroma:  u64
    width:         u32     // Coded luma width, before the conformance window.
    height:        u32
    chromaWidth:   u32
    chromaHeight:  u32
    bitDepth:      u32
    visibleWidth:  u32
    visibleHeight: u32
    cropLeft:      u32
    cropTop:       u32
    subWidthC:     u32
    subHeightC:    u32
    matrix:        YuvMatrix
    studioRange:   bool

    poc:          s32
    marking:      FrameMarking
    outputNeeded: bool     // The picture has not been handed to the consumer yet.
    isIrap:       bool
    noRaslOutput: bool

    heldByCaller:        u32     // The container still shows this picture.
    reconstructionHolds: u32     // Pictures still predicting from this one.

    // Reconstruction progress, in final coding tree block rows. A later picture waits on the rows
    // it predicts from rather than on the whole picture, which is what lets pictures overlap.
    progressRows:    s32
    progressWaiters: u32
    progressLock:    Sync.Mutex
    progressEvent:   Sync.Event

    colMotion: Array'ColMotion
    colWidth:  u32     // Collocated motion records per row.
    colHeight: u32
}

impl Frame
{
    // Allocates or reuses storage for a picture of the sequence `sps` describes.
    mtd prepare(sps: const *Sps)
    {
        .width         = sps.width
        .height        = sps.height
        .chromaWidth   = sps.width / sps.subWidthC
        .chromaHeight  = sps.height / sps.subHeightC
        .bitDepth      = sps.bitDepthLuma
        .visibleWidth  = sps.visibleWidth()
        .visibleHeight = sps.visibleHeight()
        .cropLeft      = sps.cropLeft
        .cropTop       = sps.cropTop
        .subWidthC     = sps.subWidthC
        .subHeightC    = sps.subHeightC
        .studioRange   = !sps.fullRange
        switch sps.matrixCoefficients
        {
        case 1:     .matrix = .Bt709
        case 9, 10: .matrix = .Bt2020
        case 5, 6:  .matrix = .Bt601
        default:    .matrix = sps.width >= 1280 or sps.height > 576 ? .Bt709 : .Bt601
        }

        .strideLuma   = cast(u64) (.width + FramePadding * 2)
        .strideChroma = cast(u64) (.chromaWidth + FramePadding * 2)

        let lumaSize   = .strideLuma * cast(u64) (.height + FramePadding * 2)
        let chromaSize = .strideChroma * cast(u64) (.chromaHeight + FramePadding * 2)
        if .luma.count != lumaSize
        {
            .luma.resize(lumaSize)
            .chromaB.resize(chromaSize)
            .chromaR.resize(chromaSize)
        }

        .colWidth  = (.width + (1 << ColMotionLog2) - 1) >> ColMotionLog2
        .colHeight = (.height + (1 << ColMotionLog2) - 1) >> ColMotionLog2
        let records = cast(u64) .colWidth * cast(u64) .colHeight
        if .colMotion.count != records do
            .colMotion.resize(records)

        .marking      = .Unused
        .outputNeeded = false
        if !.progressEvent.isValid() do
            .progressEvent.init(manual: true)
        Atomic.exchange(&.heldByCaller, 0)
        Atomic.exchange(&.reconstructionHolds, 0)
        Atomic.exchange(&.progressRows, 0)
    }

    // Returns a pointer to luma sample `(x, y)`, which may sit in the padding.
    #[Swag.Inline]
    mtd const lumaAt(x, y: s32)->const [*] u16? => .luma.buffer! + (cast(u64) (y + cast(s32) FramePadding)) * .strideLuma + cast(u64) (x + cast(s32) FramePadding)

    #[Swag.Inline]
    mtd lumaAtMutable(x, y: s32)->[*] u16 => .luma.buffer! + (cast(u64) (y + cast(s32) FramePadding)) * .strideLuma + cast(u64) (x + cast(s32) FramePadding)

    #[Swag.Inline]
    mtd chromaAtMutable(plane: u32, x, y: s32)->[*] u16
    {
        let base = plane == 0 ? .chromaB.buffer! : .chromaR.buffer!
        return base + (cast(u64) (y + cast(s32) FramePadding)) * .strideChroma + cast(u64) (x + cast(s32) FramePadding)
    }

    // Returns the collocated motion of the region holding luma sample `(x, y)`.
    mtd const colMotionAt(x, y: s32)->ColMotion
    {
        let cx = Math.clamp(cast(u32) x >> ColMotionLog2, 0, .colWidth - 1)
        let cy = Math.clamp(cast(u32) y >> ColMotionLog2, 0, .colHeight - 1)
        return .colMotion[cast(u64) cy * cast(u64) .colWidth + cast(u64) cx]
    }

    // Returns the progress value that covers the whole picture, padding included.
    #[Swag.Inline]
    mtd const progressComplete()->s32 => cast(s32) ((.height + 63) / 64) + 1

    // Publishes reconstruction progress and releases everything waiting for less than it.
    mtd publishProgress(rows: s32)
    {
        .progressLock.lock()
        Atomic.exchange(&.progressRows, rows)

        // Only pay for the wake-up when a waiter registered itself: a picture nobody predicts
        // from would otherwise signal on every row.
        if .progressWaiters do
            .progressEvent.signal()
        .progressLock.unlock()
    }

    // Waits until the first `rows` coding tree block rows are final, and returns the progress it
    // observed, which is [[FrameProgressFailed]] when the picture will never produce them.
    mtd waitProgress(rows: s32)->s32
    {
        var observed = Atomic.get(&.progressRows)
        if observed >= rows or observed == FrameProgressFailed do
            return observed

        .progressLock.lock()
        .progressWaiters += 1
        for
        {
            observed = Atomic.get(&.progressRows)
            if observed >= rows or observed == FrameProgressFailed do
                break
            .progressEvent.reset()
            .progressLock.unlock()
            .progressEvent.wait()
            .progressLock.lock()
        }

        .progressWaiters -= 1
        .progressLock.unlock()
        return observed
    }

    // Replicates the picture edges into the padding of the rows that are final.
    //
    // Motion compensation reads the padding directly, so it has to hold the edge samples of every
    // row a prediction may reach before that row is published.
    mtd extendRows(firstRow, lastRow: u32)
    {
        .extendPlaneRows(.luma.buffer!, .strideLuma, .width, .height, firstRow, lastRow)
        let chromaFirst = firstRow / 2
        let chromaLast  = (lastRow + 1) / 2
        .extendPlaneRows(.chromaB.buffer!, .strideChroma, .chromaWidth, .chromaHeight, chromaFirst, chromaLast)
        .extendPlaneRows(.chromaR.buffer!, .strideChroma, .chromaWidth, .chromaHeight, chromaFirst, chromaLast)
    }

    // Replicates the top and bottom edges of a plane into its padding.
    //
    // The side padding of every row is written by [[extendRows]] as the rows complete; this
    // finishes the picture by copying the first and last rows upward and downward.
    mtd extendBorders()
    {
        .extendPlaneBorders(.luma.buffer!, .strideLuma, .height)
        .extendPlaneBorders(.chromaB.buffer!, .strideChroma, .chromaHeight)
        .extendPlaneBorders(.chromaR.buffer!, .strideChroma, .chromaHeight)
    }

    private mtd const extendPlaneRows(plane: [*] u16, stride: u64, width, height, firstRow, lastRow: u32)
    {
        let last = Math.min(lastRow, height)
        for row in firstRow until last
        {
            // The row base sits at the start of the padding, so both sides are written with an
            // index that never goes below zero.
            let rowBase = plane + cast(u64) (row + FramePadding) * stride
            let line    = rowBase + cast(u64) FramePadding
            let left    = Simd.splat(line[0])
            let right   = Simd.splat(line[width - 1])

            // The padding is a multiple of eight samples wide, so both sides fill in whole vectors.
            var offset = 0'u32
            while offset < FramePadding
            {
                Simd.store(rowBase + cast(u64) offset, left)
                Simd.store(line + cast(u64) width + cast(u64) offset, right)
                offset += 8
            }
        }
    }

    private mtd const extendPlaneBorders(plane: [*] u16, stride: u64, height: u32)
    {
        let rowBytes = stride * #sizeof(u16)
        let top      = plane + cast(u64) FramePadding * stride
        for offset in FramePadding do
            Memory.copy(plane + cast(u64) offset * stride, top, rowBytes)

        let bottom = plane + cast(u64) (height + FramePadding - 1) * stride
        for offset in FramePadding do
            Memory.copy(bottom + cast(u64) (offset + 1) * stride, bottom, rowBytes)
    }

    // Copies the visible picture into `target` as eight-bit planes.
    //
    // The renderer samples eight-bit planes, so a ten-bit picture is reduced on the way out with
    // the rounding the standard uses for a bit-depth decrease.
    mtd const writePlanar(target: *PlanarFrame)
    {
        let visibleWidth  = cast(s32) .visibleWidth
        let visibleHeight = cast(s32) .visibleHeight
        target.resize(visibleWidth, visibleHeight)
        target.studioRange = .studioRange
        target.matrix      = .matrix

        let left  = cast(s32) (.cropLeft * .subWidthC)
        let top   = cast(s32) (.cropTop * .subHeightC)
        let shift = .bitDepth - 8

        .reducePlane(target.luma.buffer!, cast(u64) target.strideLuma, .luma.buffer!, .strideLuma, left, top, visibleWidth, visibleHeight, shift)

        let chromaLeft   = left / cast(s32) .subWidthC
        let chromaTop    = top / cast(s32) .subHeightC
        let chromaWidth  = (visibleWidth + 1) / 2
        let chromaHeight = (visibleHeight + 1) / 2
        .reducePlane(target.chromaB.buffer!, cast(u64) target.strideChroma, .chromaB.buffer!, .strideChroma, chromaLeft, chromaTop, chromaWidth, chromaHeight, shift)
        .reducePlane(target.chromaR.buffer!, cast(u64) target.strideChroma, .chromaR.buffer!, .strideChroma, chromaLeft, chromaTop, chromaWidth, chromaHeight, shift)
    }

    private mtd const reducePlane(destination: [*] u8, destinationStride: u64, source: const [*] u16, sourceStride: u64, left, top, width, height: s32, shift: u32)
    {
        let origin = source + (cast(u64) (top + cast(s32) FramePadding)) * sourceStride + cast(u64) (left + cast(s32) FramePadding)
        if !shift
        {
            for row in height
            {
                let line   = origin + cast(u64) row * sourceStride
                let out    = destination + cast(u64) row * destinationStride
                var column = 0's32
                while column + 16 <= width
                {
                    let low  = cast #bit(Simd.S16x8) Simd.load(line + column)
                    let high = cast #bit(Simd.S16x8) Simd.load(line + column + 8)
                    Simd.store(out + column, Simd.packUnsigned(low, high))
                    column += 16
                }

                while column < width
                {
                    out[column] = cast(u8) line[column]
                    column      += 1
                }
            }

            return
        }

        let rounding       = 1'u32 << (shift - 1)
        let maximum        = cast(u32) ((1'u32 << .bitDepth) - 1)
        let packedRounding = Simd.splat(cast(u16) rounding)
        let packedMaximum  = Simd.splat(cast(u16) maximum)
        for row in height
        {
            let line   = origin + cast(u64) row * sourceStride
            let out    = destination + cast(u64) row * destinationStride
            var column = 0's32
            while column + 16 <= width
            {
                let low  = cast #bit(Simd.S16x8) (Math.min(Simd.load(line + column) + packedRounding, packedMaximum) >> shift)
                let high = cast #bit(Simd.S16x8) (Math.min(Simd.load(line + column + 8) + packedRounding, packedMaximum) >> shift)
                Simd.store(out + column, Simd.packUnsigned(low, high))
                column += 16
            }

            while column < width
            {
                out[column] = cast(u8) (Math.min(cast(u32) line[column] + rounding, maximum) >> shift)
                column      += 1
            }
        }
    }
}
