#global namespace H264
#global internal

using Core, Core.Errors, Core.Math

// Padding kept around each plane so motion compensation can read past the picture edge.
//
// The luma interpolator reads up to five samples beyond a block, so a motion vector pointing
// just outside the frame stays inside the padded storage once the edges are replicated. Longer
// excursions go through the bounded fallback of the interpolator instead.
const FramePadding = 32's32
private const ConversionBands = 16'u32

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

    poc:          s32     // Picture order count of the frame.
    frameNum:     u32
    isShortTerm:  bool
    isLongTerm:   bool
    longTermIdx:  s32
    frameNumWrap: s32     // Recomputed for every slice against the current frame number.
    picNum:       s32
    heldByCaller: bool     // The container still displays this frame.

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

        .isShortTerm  = false
        .isLongTerm   = false
        .heldByCaller = false
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
                .colMbShort[mbIndex] != 0,
            }
        }

        return {
            [.colMv[blockIndex * 2], .colMv[blockIndex * 2 + 1]],
            .colRef[blockIndex],
            .colPoc[blockIndex],
            .colShort[blockIndex] != 0,
        }
    }

    // Converts the visible window of the frame into a bottom-up RGB8 image, with the
    // limited-range BT.601 arithmetic every decoder of this module uses.
    mtd const toRgb(target: *Pixel.Image, width, height, cropLeft, cropTop: s32)
    {
        if target.width != width or target.height != height or target.pixelFormat != .RGB8 do
            target[] = Pixel.Image.create(width, height, .RGB8)

        let bandCount = Math.min(Math.min(Jobs.workerCount(), ConversionBands), cast(u32) height)
        if bandCount <= 1
        {
            convertRgbRows(me, target, width, height, cropLeft, cropTop, 0, height)
            return
        }

        var context = {frame: me, target: target, width: width, height: height, cropLeft: cropLeft, cropTop: cropTop, bandCount: bandCount}
        Jobs.parallelFor(bandCount, &context)
        {
            let state = cast(*#decltype(context)) data!
            let first = state.height * cast(s32) index / cast(s32) state.bandCount
            let end   = state.height * cast(s32) (index + 1) / cast(s32) state.bandCount
            convertRgbRows(state.frame, state.target, state.width, state.height, state.cropLeft, state.cropTop, first, end)
        }
    }

    // Replicates the picture edges into the padding so motion compensation can read there.
    mtd extendEdges()
    {
        extendPlane(.luma.buffer!, .strideLuma, .mbWidth * 16, .mbHeight * 16)
        extendPlane(.cb.buffer!, .strideChroma, .mbWidth * 8, .mbHeight * 8)
        extendPlane(.cr.buffer!, .strideChroma, .mbWidth * 8, .mbHeight * 8)
    }
}

// Converts a contiguous band of visible rows. Bands write disjoint destination rows.
private func convertRgbRows(frame: const *Frame, target: *Pixel.Image, width, height, cropLeft, cropTop, firstY, endY: s32)
{
    for y in firstY until endY
    {
        var destination = target.pixels.buffer! + cast(u64) (height - y - 1) * cast(u64) target.rowStride
        var luma        = frame.luma.buffer! + cast(u64) (cropTop + y + FramePadding) * frame.strideLuma + cast(u64) (cropLeft + FramePadding)
        let chromaRow   = cast(u64) (((cropTop + y) >> 1) + FramePadding) * frame.strideChroma
        let cbRow       = frame.cb.buffer! + chromaRow
        let crRow       = frame.cr.buffer! + chromaRow

        // Two horizontal luma samples share one chroma sample, so the chroma terms of the
        // conversion are computed once per pair. An odd crop offsets the pairing by one.
        var chromaAt  = cast(u64) ((cropLeft >> 1) + FramePadding)
        var remaining = width
        if cropLeft & 1
        {
            let d = cast(s32) cbRow[chromaAt] - 128
            let e = cast(s32) crRow[chromaAt] - 128
            storeRgbPixel(destination, max0S32(cast(s32) luma[0] - 16) * 298, 409 * e + 128, -100 * d - 208 * e + 128, 516 * d + 128)
            destination += 3
            luma        += 1
            chromaAt    += 1
            remaining   -= 1
        }

        while remaining >= 16
        {
            convertRgb16(destination, luma, cbRow + chromaAt, crRow + chromaAt)
            destination += 48
            luma        += 16
            chromaAt    += 8
            remaining   -= 16
        }

        while remaining >= 2
        {
            let d     = cast(s32) cbRow[chromaAt] - 128
            let e     = cast(s32) crRow[chromaAt] - 128
            let rTerm = 409 * e + 128
            let gTerm = -100 * d - 208 * e + 128
            let bTerm = 516 * d + 128
            storeRgbPixel(destination, max0S32(cast(s32) luma[0] - 16) * 298, rTerm, gTerm, bTerm)
            storeRgbPixel(destination + 3, max0S32(cast(s32) luma[1] - 16) * 298, rTerm, gTerm, bTerm)
            destination += 6
            luma        += 2
            chromaAt    += 1
            remaining   -= 2
        }

        if remaining
        {
            let d = cast(s32) cbRow[chromaAt] - 128
            let e = cast(s32) crRow[chromaAt] - 128
            storeRgbPixel(destination, max0S32(cast(s32) luma[0] - 16) * 298, 409 * e + 128, -100 * d - 208 * e + 128, 516 * d + 128)
        }
    }
}

// Stores one converted pixel from its scaled luma and the shared chroma terms.
#[Swag.Inline]
private func storeRgbPixel(destination: [*] u8, c298, rTerm, gTerm, bTerm: s32)
{
    destination[0] = clampPixel((c298 + rTerm) >> 8)
    destination[1] = clampPixel((c298 + gTerm) >> 8)
    destination[2] = clampPixel((c298 + bTerm) >> 8)
}

// Converts sixteen luma samples against their eight shared chroma samples, with the
// exact fixed-point arithmetic of the scalar path: the products need 32-bit lanes,
// the signed pack keeps the shifted values intact (they stay within about -204..481),
// and the unsigned pack is exactly the scalar clamp. The three packed color vectors
// then interleave into the 48 output bytes.
#[Swag.Inline]
private func convertRgb16(destination: [*] u8, luma, cb, cr: const [*] u8)
{
    // Each chroma byte serves a pair of pixels.
    const DupPairs = cast(Simd.U8x16) [0'u8, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7]

    let y16 = Simd.subSaturating(Simd.load(luma), Simd.splat(16'u8))
    let yLo = Simd.widenLow(y16)
    let yHi = Simd.widenHigh(y16)
    let y0  = (cast #bit(Simd.S32x4) Simd.widenLow(yLo)) * 298
    let y1  = (cast #bit(Simd.S32x4) Simd.widenHigh(yLo)) * 298
    let y2  = (cast #bit(Simd.S32x4) Simd.widenLow(yHi)) * 298
    let y3  = (cast #bit(Simd.S32x4) Simd.widenHigh(yHi)) * 298

    let dBytes = Simd.shuffle(Simd.load(cb), DupPairs)
    let eBytes = Simd.shuffle(Simd.load(cr), DupPairs)
    let dSLo   = (cast #bit(Simd.S16x8) Simd.widenLow(dBytes)) - 128
    let dSHi   = (cast #bit(Simd.S16x8) Simd.widenHigh(dBytes)) - 128
    let eSLo   = (cast #bit(Simd.S16x8) Simd.widenLow(eBytes)) - 128
    let eSHi   = (cast #bit(Simd.S16x8) Simd.widenHigh(eBytes)) - 128

    let d0 = Simd.widenLow(dSLo)
    let d1 = Simd.widenHigh(dSLo)
    let d2 = Simd.widenLow(dSHi)
    let d3 = Simd.widenHigh(dSHi)
    let e0 = Simd.widenLow(eSLo)
    let e1 = Simd.widenHigh(eSLo)
    let e2 = Simd.widenLow(eSHi)
    let e3 = Simd.widenHigh(eSHi)

    let r8 = Simd.packUnsigned(Simd.packSigned((y0 + e0 * 409 + 128) >> 8, (y1 + e1 * 409 + 128) >> 8),
                               Simd.packSigned((y2 + e2 * 409 + 128) >> 8, (y3 + e3 * 409 + 128) >> 8))
    let g8 = Simd.packUnsigned(Simd.packSigned((y0 - d0 * 100 - e0 * 208 + 128) >> 8, (y1 - d1 * 100 - e1 * 208 + 128) >> 8),
                               Simd.packSigned((y2 - d2 * 100 - e2 * 208 + 128) >> 8, (y3 - d3 * 100 - e3 * 208 + 128) >> 8))
    let b8 = Simd.packUnsigned(Simd.packSigned((y0 + d0 * 516 + 128) >> 8, (y1 + d1 * 516 + 128) >> 8),
                               Simd.packSigned((y2 + d2 * 516 + 128) >> 8, (y3 + d3 * 516 + 128) >> 8))

    // Byte k of the 48 output bytes is color k % 3 of pixel k / 3; a permutation index
    // of 128 clears the lane, so the three spreads combine with plain ors.
    const PermR0 = cast(Simd.U8x16) [0'u8, 128, 128, 1, 128, 128, 2, 128, 128, 3, 128, 128, 4, 128, 128, 5]
    const PermG0 = cast(Simd.U8x16) [128'u8, 0, 128, 128, 1, 128, 128, 2, 128, 128, 3, 128, 128, 4, 128, 128]
    const PermB0 = cast(Simd.U8x16) [128'u8, 128, 0, 128, 128, 1, 128, 128, 2, 128, 128, 3, 128, 128, 4, 128]
    const PermR1 = cast(Simd.U8x16) [128'u8, 128, 6, 128, 128, 7, 128, 128, 8, 128, 128, 9, 128, 128, 10, 128]
    const PermG1 = cast(Simd.U8x16) [5'u8, 128, 128, 6, 128, 128, 7, 128, 128, 8, 128, 128, 9, 128, 128, 10]
    const PermB1 = cast(Simd.U8x16) [128'u8, 5, 128, 128, 6, 128, 128, 7, 128, 128, 8, 128, 128, 9, 128, 128]
    const PermR2 = cast(Simd.U8x16) [128'u8, 11, 128, 128, 12, 128, 128, 13, 128, 128, 14, 128, 128, 15, 128, 128]
    const PermG2 = cast(Simd.U8x16) [128'u8, 128, 11, 128, 128, 12, 128, 128, 13, 128, 128, 14, 128, 128, 15, 128]
    const PermB2 = cast(Simd.U8x16) [10'u8, 128, 128, 11, 128, 128, 12, 128, 128, 13, 128, 128, 14, 128, 128, 15]

    Simd.store(destination, Simd.shuffle(r8, PermR0) | Simd.shuffle(g8, PermG0) | Simd.shuffle(b8, PermB0))
    Simd.store(destination + 16, Simd.shuffle(r8, PermR1) | Simd.shuffle(g8, PermG1) | Simd.shuffle(b8, PermB1))
    Simd.store(destination + 32, Simd.shuffle(r8, PermR2) | Simd.shuffle(g8, PermG2) | Simd.shuffle(b8, PermB2))
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
