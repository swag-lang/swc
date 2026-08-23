#global namespace H264
#global internal

using Core, Core.Errors, Core.Math

// Padding kept around each plane so motion compensation can read past the picture edge.
//
// The luma interpolator reads up to five samples beyond a block, so a motion vector pointing
// just outside the frame stays inside the padded storage once the edges are replicated. Longer
// excursions go through the bounded fallback of the interpolator instead.
const FramePadding = 32's32

// Row progress a picture publishes while it is being reconstructed.
//
// A value of `n` means the first `n` macroblock rows hold their final samples and carry their
// side padding, and that the top padding is written once `n` is at least one. The completion
// value additionally covers the bottom padding, so a prediction reading past the picture waits
// for it. A failed picture publishes [[FrameProgressFailed]] so nothing waits on it forever.
const FrameProgressFailed = -1's32

// Co-located motion read by direct B prediction.
struct ColMotion
{
    mv:      [2] s16
    ref:     s8
    poc:     s32
    isShort: bool
}

// One decoded picture: padded 4:2:0 planes plus the reference and motion state the rest of
// the stream needs from it.
struct Frame
{
    luma:         Array'u8     // Padded luma plane.
    cb:           Array'u8     // Padded blue-difference plane.
    cr:           Array'u8     // Padded red-difference plane.
    strideLuma:   u64
    strideChroma: u64
    mbWidth:      s32
    mbHeight:     s32

    poc:                 s32     // Picture order count of the frame.
    frameNum:            u32
    isShortTerm:         bool
    isLongTerm:          bool
    longTermIdx:         s32
    frameNumWrap:        s32     // Recomputed for every slice against the current frame number.
    picNum:              s32
    heldByCaller:        u32     // The container still displays this frame; shared across pipeline lanes.
    reconstructionHolds: u32     // Parsed pictures still borrow this frame for reconstruction.
    parseProgress:       u32     // Zero while metadata is incomplete, one when ready, two on failure.

    // Reconstruction progress, in final macroblock rows. Prediction in a later picture waits on
    // it rather than on the whole picture, which is what lets consecutive pictures overlap.
    progressRows:    s32
    progressWaiters: u32
    progressLock:    Sync.Mutex
    progressEvent:   Sync.Event

    // Motion exported for co-located prediction in later B slices, one entry per 4x4 block:
    // the L0 motion when the block had one, its L1 motion otherwise.
    colMv:    Array's16     // Two components per block.
    colRef:   Array's8      // Reference index, or -1 for an intra or unpredicted block.
    colPoc:   Array's32     // Picture order count of the referenced frame.
    colShort: Array'u8      // Whether the referenced frame was short-term.

    // A uniform P-skip exports the same co-located motion for all sixteen blocks. Keep it once
    // per macroblock so the serial entropy path does not write five full grids for still areas.
    colUniform: Array'u8
    colMbMv:    Array's16
    colMbRef:   Array's8
    colMbPoc:   Array's32
    colMbShort: Array'u8
}

impl Frame
{
    // Allocates or reuses storage for a picture of `mbWidth` by `mbHeight` macroblocks.
    mtd prepare(mbWidth, mbHeight: s32)
    {
        .mbWidth      = mbWidth
        .mbHeight     = mbHeight
        .strideLuma   = cast(u64) (mbWidth * 16 + FramePadding * 2)
        .strideChroma = cast(u64) (mbWidth * 8 + FramePadding * 2)

        let lumaSize   = .strideLuma * cast(u64) (mbHeight * 16 + FramePadding * 2)
        let chromaSize = .strideChroma * cast(u64) (mbHeight * 8 + FramePadding * 2)
        if .luma.count != lumaSize
        {
            .luma.resize(lumaSize)
            .cb.resize(chromaSize)
            .cr.resize(chromaSize)
        }

        let blocks = cast(u64) mbWidth * cast(u64) mbHeight * 16
        if .colRef.count != blocks
        {
            .colMv.resize(blocks * 2)
            .colRef.resize(blocks)
            .colPoc.resize(blocks)
            .colShort.resize(blocks)

            let macroblocks = cast(u64) mbWidth * cast(u64) mbHeight
            .colUniform.resize(macroblocks)
            .colMbMv.resize(macroblocks * 2)
            .colMbRef.resize(macroblocks)
            .colMbPoc.resize(macroblocks)
            .colMbShort.resize(macroblocks)
        }

        .isShortTerm = false
        .isLongTerm  = false
        if !.progressEvent.isValid() do
            .progressEvent.init(manual: true)
        Atomic.exchange(&.heldByCaller, 0)
        Atomic.exchange(&.parseProgress, 0)
        Atomic.exchange(&.progressRows, 0)
        Debug.assert(Atomic.get(&.reconstructionHolds) == 0)
    }

    // Returns the progress value that covers the whole picture, padding included.
    #[Swag.Inline]
    mtd const progressComplete()->s32 => .mbHeight + 1

    // Publishes reconstruction progress and releases everything waiting for less than it.
    mtd publishProgress(rows: s32)
    {
        .progressLock.lock()
        Atomic.exchange(&.progressRows, rows)

        // Every macroblock row publishes, and with a picture per decoder lane that is thousands
        // of signals a second on a stream nobody is waiting on. Only pay for the wake-up when a
        // waiter registered itself.
        if .progressWaiters do
            .progressEvent.signal()
        .progressLock.unlock()
    }

    // Waits until the first `rows` macroblock rows are final, and returns the progress it
    // observed, which is [[FrameProgressFailed]] when the picture will never produce them.
    //
    // The event stays manual so one publication releases every waiter. A waiter that still
    // needs more clears it under the lock before waiting again, which cannot lose a
    // publication because a publication takes the same lock; a waiter that leaves sets it
    // again so the others re-read the counter rather than sleeping through it.
    mtd awaitProgress(rows: s32)->s32
    {
        var value = Atomic.get(&.progressRows)
        if value >= rows do
            return value

        .progressLock.lock()
        .progressWaiters += 1
        while true
        {
            value = Atomic.get(&.progressRows)
            if value >= rows or value == FrameProgressFailed do
                break
            .progressEvent.reset()
            .progressLock.unlock()
            .progressEvent.wait()
            .progressLock.lock()
        }

        .progressWaiters -= 1
        if .progressWaiters do
            .progressEvent.signal()
        .progressLock.unlock()
        return value
    }

    // Returns the address of the luma sample at `x`, `y` of the coded picture.
    #[Swag.Inline]
    mtd pixLuma(x, y: s32)->[*] u8 => .luma.buffer! + cast(u64) (y + FramePadding) * .strideLuma + cast(u64) (x + FramePadding)

    // Returns the address of one chroma sample; `plane` selects Cb or Cr.
    #[Swag.Inline]
    mtd pixChroma(plane: u32, x, y: s32)->[*] u8
    {
        let base: [*] u8 = plane == 0 ? .cb.buffer! : .cr.buffer!
        return base + cast(u64) (y + FramePadding) * .strideChroma + cast(u64) (x + FramePadding)
    }

    // Reports whether the frame is referenced by upcoming pictures.
    mtd const isReference()->bool => .isShortTerm or .isLongTerm

    // Returns co-located motion for one raster 4x4 block.
    mtd const colMotion(blockIndex: u64)->ColMotion
    {
        let blocksWide = .mbWidth * 4
        let x4         = cast(s32) (blockIndex % cast(u64) blocksWide)
        let y4         = cast(s32) (blockIndex / cast(u64) blocksWide)
        let mbIndex    = cast(u64) ((y4 >> 2) * .mbWidth + (x4 >> 2))

        if .colUniform[mbIndex] != 0
        {
            return {
                [.colMbMv[mbIndex * 2], .colMbMv[mbIndex * 2 + 1]],
                .colMbRef[mbIndex],
                .colMbPoc[mbIndex],
                .colMbShort[mbIndex] != 0}
        }

        return {
            [.colMv[blockIndex * 2], .colMv[blockIndex * 2 + 1]],
            .colRef[blockIndex],
            .colPoc[blockIndex],
            .colShort[blockIndex] != 0}
    }

    // Converts the visible window of the frame into a bottom-up RGB8 image, with the
    // limited-range BT.601 arithmetic every decoder of this module uses.
    mtd toRgb(target: *Pixel.Image, width, height, cropLeft, cropTop: s32)
    {
        .view(width, height, cropLeft, cropTop).convertToRgb(target)
    }

    // Describes the visible window of the picture without copying it.
    //
    // A 4:2:0 crop is stated in chroma units, so both offsets are even and the chroma plane is
    // addressed at exactly half the luma coordinates.
    mtd view(width, height, cropLeft, cropTop: s32)->Pixel.Yuv420View
    {
        Debug.assert((cropLeft & 1) == 0 and (cropTop & 1) == 0)
        return {
            luma: .pixLuma(cropLeft, cropTop),
            chromaB: .pixChroma(0, cropLeft / 2, cropTop / 2),
            chromaR: .pixChroma(1, cropLeft / 2, cropTop / 2),
            lumaStride: .strideLuma,
            chromaStride: .strideChroma,
            width: width,
            height: height}
    }

    // Copies the visible window of the frame into tightly packed 4:2:0 planes.
    //
    // The samples leave exactly as the codec reconstructed them: this is the whole point of the
    // planar output, which exists so nothing converts a picture to RGB on the processor.
    mtd copyPlanes(target: *PlanarFrame, width, height, cropLeft, cropTop: s32)
    {
        target.resize(width, height)

        var destination = target.luma.buffer!
        for y in height
        {
            Memory.copy(destination, .pixLuma(cropLeft, cropTop + y), cast(u64) width)
            destination += cast(u64) target.strideLuma
        }

        let chromaWidth  = cast(u64) target.strideChroma
        let chromaRows   = target.chromaHeight()
        let chromaLeft   = cropLeft / 2
        let chromaTop    = cropTop / 2
        var destinationB = target.chromaB.buffer!
        var destinationR = target.chromaR.buffer!
        for y in chromaRows
        {
            Memory.copy(destinationB, .pixChroma(0, chromaLeft, chromaTop + y), chromaWidth)
            Memory.copy(destinationR, .pixChroma(1, chromaLeft, chromaTop + y), chromaWidth)
            destinationB += chromaWidth
            destinationR += chromaWidth
        }
    }

    // Replicates the picture edges into the padding so motion compensation can read there.
    mtd extendEdges()
    {
        extendPlane(.luma.buffer!, .strideLuma, .mbWidth * 16, .mbHeight * 16)
        extendPlane(.cb.buffer!, .strideChroma, .mbWidth * 8, .mbHeight * 8)
        extendPlane(.cr.buffer!, .strideChroma, .mbWidth * 8, .mbHeight * 8)
    }

    // Replicates the left and right edges of one macroblock row, and the top padding with it
    // when that row is the first. A picture publishes a row only once this ran on it, so a
    // later picture predicting from the row reads replicated samples and not stale ones.
    mtd extendRowEdges(mbRow: s32)
    {
        extendPlaneRows(.luma.buffer!, .strideLuma, .mbWidth * 16, mbRow * 16, 16)
        extendPlaneRows(.cb.buffer!, .strideChroma, .mbWidth * 8, mbRow * 8, 8)
        extendPlaneRows(.cr.buffer!, .strideChroma, .mbWidth * 8, mbRow * 8, 8)
        if mbRow == 0
        {
            extendPlaneTop(.luma.buffer!, .strideLuma)
            extendPlaneTop(.cb.buffer!, .strideChroma)
            extendPlaneTop(.cr.buffer!, .strideChroma)
        }
    }

    // Replicates the bottom padding, which only the finished picture can produce.
    mtd extendBottomEdge()
    {
        extendPlaneBottom(.luma.buffer!, .strideLuma, .mbHeight * 16)
        extendPlaneBottom(.cb.buffer!, .strideChroma, .mbHeight * 8)
        extendPlaneBottom(.cr.buffer!, .strideChroma, .mbHeight * 8)
    }
}

// Replicates the left and right edges of `count` rows starting at `first`.
private func extendPlaneRows(base: [*] u8, stride: u64, width, first, count: s32)
{
    let pad = cast(u64) FramePadding
    var row = base + (pad + cast(u64) first) * stride + pad
    for count
    {
        Memory.set(row - pad, row[0], pad)
        Memory.set(row + cast(u64) width, row[cast(u64) width - 1], pad)
        row += stride
    }
}

// Copies the first row of a plane into the padding above it.
private func extendPlaneTop(base: [*] u8, stride: u64)
{
    let pad = cast(u64) FramePadding
    let top = base + pad * stride
    for index in pad do
        Memory.copy(base + index * stride, top, stride)
}

// Copies the last row of a plane into the padding below it.
private func extendPlaneBottom(base: [*] u8, stride: u64, height: s32)
{
    let pad    = cast(u64) FramePadding
    let bottom = base + (pad + cast(u64) height - 1) * stride
    for index in pad do
        Memory.copy(bottom + (index + 1) * stride, bottom, stride)
}

// Replicates the edges of one plane into its padding border.
private func extendPlane(base: [*] u8, stride: u64, width, height: s32)
{
    let pad = cast(u64) FramePadding
    var row = base + pad * stride + pad
    for height
    {
        Memory.set(row - pad, row[0], pad)
        Memory.set(row + cast(u64) width, row[cast(u64) width - 1], pad)
        row += stride
    }

    let top    = base + pad * stride
    let bottom = base + (pad + cast(u64) height - 1) * stride
    for index in pad
    {
        Memory.copy(base + index * stride, top, stride)
        Memory.copy(bottom + (index + 1) * stride, bottom, stride)
    }
}
