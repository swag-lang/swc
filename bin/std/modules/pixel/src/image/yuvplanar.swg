#global public

using Core, Core.Math

// Selects the matrix that converts luma and chroma samples to RGB.
enum YuvMatrix
{
    Bt601      // ITU-R BT.601, used by standard-definition video.
    Bt709      // ITU-R BT.709, used by high-definition SDR video.
    Bt2020     // ITU-R BT.2020 non-constant-luminance conversion.
}

// Borrows one picture in planar YUV from whatever produced it.
//
// Every video codec reconstructs this layout: a full-resolution luma plane and two chroma planes,
// either at half resolution on both axes, where one chroma sample serves a two-by-two block of
// pixels, or at the resolution of luma. `chromaShift` says which, and it is the only difference
// between the two: one for 4:2:0, none for 4:4:4. A view owns nothing and stays valid only while
// the planes behind it do.
//
// The offsets are already applied, so a cropped picture is described by pointing the planes at
// its visible corner. A crop is stated in chroma units — a 4:2:0 one is therefore an even number
// of luma samples — which is what lets a chroma plane be addressed at the shifted coordinates.
//
// Rows run top-down: the plane pointers address the top-left visible sample, which is the order
// every codec reconstructs a picture in. [[Pixel.Image]] stores its rows the other way round, so
// a conversion into one writes them in reverse, and a renderer that samples the planes directly
// accounts for the difference itself.
struct YuvPlanarView
{
    public
    {
        luma:    const [*] u8     // Full-resolution luma of the visible corner.
        chromaB: const [*] u8     // Blue-difference chroma.
        chromaR: const [*] u8     // Red-difference chroma.

        lumaStride:   u64     // Bytes between luma rows.
        chromaStride: u64     // Bytes between chroma rows.

        width:  s32     // Visible width in luma samples.
        height: s32     // Visible height in luma samples.

        // How far a pixel coordinate shifts right to address the chroma planes: one for 4:2:0,
        // none for 4:4:4.
        chromaShift: s32 = 1

        matrix:      YuvMatrix = .Bt601     // Matrix used when the planes are converted to RGB.
        studioRange: bool      = true       // Whether luma uses 16..235 rather than the full 0..255 range.
    }
}

impl YuvPlanarView
{
    // Reports whether dimensions, chroma subsampling, and row strides form a supported layout.
    //
    // Plane pointers must still refer to readable storage for the described rows.
    public mtd const isValidLayout()->bool
    {
        if .width <= 0 or .height <= 0 or (.chromaShift != 0 and .chromaShift != 1) do
            return false

        let divisor     = 1's32 << .chromaShift
        let chromaWidth = .width / divisor + (.width % divisor != 0 ? 1 : 0)
        return .lumaStride >= cast(u64, .width) and .chromaStride >= cast(u64, chromaWidth)
    }

    // Returns the width of one chroma plane, in samples.
    #[Swag.Inline]
    mtd const chromaWidth()->s32
    {
        Swag.assert(.isValidLayout(), "YUV planar view has an invalid layout")
        let divisor = 1's32 << .chromaShift
        return .width / divisor + (.width % divisor != 0 ? 1 : 0)
    }

    // Returns the number of rows of one chroma plane.
    #[Swag.Inline]
    mtd const chromaHeight()->s32
    {
        Swag.assert(.isValidLayout(), "YUV planar view has an invalid layout")
        let divisor = 1's32 << .chromaShift
        return .height / divisor + (.height % divisor != 0 ? 1 : 0)
    }

    // Converts the picture into `target`, which is created or reused as RGB8.
    //
    // Subsampled chroma is linearly upsampled at luma pixel centers, matching texture sampling
    // used by hardware video renderers.
    // Bands of rows are independent, so the work fans through the scheduler when one is running.
    // A caller drawing through a renderer should not need this at all: converting a large picture
    // costs more processor time than decoding it, and a renderer converts where it draws.
    mtd const convertToRgb(target: *Image)
    {
        Swag.assert(.isValidLayout(), "YUV planar view has an invalid layout")
        if target.width != .width or target.height != .height or target.pixelFormat != .RGB8 do
            target[] = Image.create(.width, .height, .RGB8)

        // The luma rows sharing one chroma row are one group: two of them in 4:2:0, one in
        // 4:4:4. The runtime groups these independent bands by measured cost and keeps small
        // conversions on the caller without starting workers.
        let view  = me
        let band  = 1's32 << .chromaShift
        let count = (cast(u64, .height) + cast(u64, band) - 1) / cast(u64, band)
        parallel for |view, target, band| group in count
        {
            let first = cast(s32, (group * cast(u64, band)))
            view.convertRowsToRgb(target, first, first + Math.min(band, view.height - first))
        }
    }

    // Converts rows `firstY` until `endY` into an RGB8 `target` of the same geometry.
    //
    // The row range is half-open and must be within the image. Bands write disjoint destination
    // rows, so they run concurrently on one target.
    mtd const convertRowsToRgb(target: *Image, firstY, endY: s32)
    {
        if not .isValidLayout() do
            Swag.panic("YUV planar view has an invalid layout", #curlocation)
        if not target.isValid() or
           target.pixelFormat != .RGB8 or
           target.width != .width or
           target.height != .height do
            Swag.panic("YUV conversion target must be a matching RGB8 image", #curlocation)
        let targetRowBytes = cast(u64, target.width) * 3
        if targetRowBytes > Swag.S32.Max or
           target.bytesPerPixel != 3 or
           target.rowStride != cast(s32, targetRowBytes) or
           target.byteCount != targetRowBytes * cast(u64, target.height) or
           target.pixels.count != target.byteCount do
            Swag.panic("YUV conversion target has invalid pixel storage", #curlocation)
        if firstY < 0 or endY < firstY or endY > .height do
            Swag.panic("YUV conversion row range is outside the image", #curlocation)

        let factors = .conversionFactors()
        for y in firstY until endY
        {
            var destination = target.pixels.storage() + cast(u64, (.height - y - 1)) * cast(u64, target.rowStride)
            let luma        = .luma + cast(u64, y) * .lumaStride
            let chromaRow   = cast(u64, (y >> .chromaShift)) * .chromaStride
            let cbRow       = .chromaB + chromaRow
            let crRow       = .chromaR + chromaRow
            if .chromaShift == 0 do
                convertRowFullChroma(destination, luma, cbRow, crRow, .width, &factors)
            else do
                convertRowHalfChroma(destination,
                                     luma,
                                     .chromaB,
                                     .chromaR,
                                     .width,
                                     .height,
                                     .chromaWidth(),
                                     .chromaHeight(),
                                     .chromaStride,
                                     y,
                                     &factors)
        }
    }

    // Returns the fixed-point factors shared by the scalar, SIMD, CPU-renderer, and shader paths.
    internal mtd const conversionFactors()->YuvConversionFactors
        => yuvConversionFactors(.matrix, .studioRange)
}

// Converts one row whose chroma planes carry a sample per pixel.
private func convertRowFullChroma(destination: [*] u8, luma, cb, cr: const [*] u8, width: s32, factors: const *YuvConversionFactors)
{
    var out       = destination
    var y         = luma
    var at        = 0'u64
    var remaining = width
    while remaining >= 16
    {
        convertYuvRgb16Colors(out, y, Simd.load(cb + at), Simd.load(cr + at), factors)
        out       += 48
        y         += 16
        at        += 16
        remaining -= 16
    }

    while remaining > 0
    {
        let d = cast(s32, cb[at]) - 128
        let e = cast(s32, cr[at]) - 128
        storeYuvRgbPixel(out,
                         yuvLumaTerm(y[0], factors),
                         factors.redCr * e + 128,
                         factors.greenCb * d + factors.greenCr * e + 128,
                         factors.blueCb * d + 128)
        out       += 3
        y         += 1
        at        += 1
        remaining -= 1
    }
}

// Keeps the quarter-sample vertical interpolation unrounded for the horizontal pass.
#[Swag.Inline]
private func weightChromaRows(row, adjacent: const [*] u8)->Simd.U16x8
{
    let a      = cast #bit(Simd.U8x16, Simd.splat(cast(const [*] u64, row)[0]))
    let b      = cast #bit(Simd.U8x16, Simd.splat(cast(const [*] u64, adjacent)[0]))
    let middle = Simd.widenLow(a)
    return (middle << 1) + middle + Simd.widenLow(b)
}

// For even 4:2:0 dimensions, the sample centers lie one quarter of a chroma texel off
// the nearest center on both axes. Combine the two passes before rounding once.
#[Swag.Inline]
private func quarterChroma(row, adjacent: const [*] u8, first, last: bool)->Simd.U8x16
{
    const RepeatLeft  = cast(Simd.U8x16, [0'u8, 1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])
    const RepeatRight = cast(Simd.U8x16, [2'u8, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 14, 15])
    let middle = weightChromaRows(row, adjacent)
    let bytes  = cast #bit(Simd.U8x16, middle)
    let left   = first ? cast #bit(Simd.U16x8, Simd.shuffle(bytes, RepeatLeft)) : weightChromaRows(row - 1, adjacent - 1)
    let right  = last ? cast #bit(Simd.U16x8, Simd.shuffle(bytes, RepeatRight)) : weightChromaRows(row + 1, adjacent + 1)
    let base   = (middle << 1) + middle + 8'u16
    let even   = (base + left) >> 4
    let odd    = (base + right) >> 4
    let low    = cast #bit(Simd.S16x8, Simd.interleaveLow(even, odd))
    let high   = cast #bit(Simd.S16x8, Simd.interleaveHigh(even, odd))
    return Simd.packUnsigned(low, high)
}

// Converts one row whose chroma planes carry a sample per pair of pixels.
private func convertRowHalfChroma(destination: [*] u8,
                                  luma,
                                  cb,
                                  cr: const [*] u8,
                                  width,
                                  height,
                                  chromaWidth,
                                  chromaHeight: s32,
                                  chromaStride: u64,
                                  y: s32,
                                  factors: const *YuvConversionFactors)
{
    var x = 0's32
    if not (width & 1) and not (height & 1)
    {
        let row        = y / 2
        let adjacent   = Math.clamp(row + ((y & 1) ? 1 : -1), 0, chromaHeight - 1)
        let rowAt      = cast(u64, row) * chromaStride
        let adjacentAt = cast(u64, adjacent) * chromaStride
        while width - x >= 16
        {
            let column         = cast(u64, x / 2)
            let rowOffset      = rowAt + column
            let adjacentOffset = adjacentAt + column
            let first          = x == 0
            let last           = x + 16 == width
            let blue           = quarterChroma(cb + rowOffset, cb + adjacentOffset, first, last)
            let red            = quarterChroma(cr + rowOffset, cr + adjacentOffset, first, last)
            convertYuvRgb16Colors(destination + cast(u64, x * 3), luma + cast(u64, x), blue, red, factors)
            x += 16
        }
    }

    if x == width do
        return

    // The two chroma planes share the same coordinates and every pixel shares this row.
    let weights = chromaRowWeights(width, height, chromaHeight, chromaStride, y)
    var chromaB: [16] u8
    var chromaR: [16] u8
    while width - x >= 16
    {
        for lane in 16
        {
            let sample = sampleLinearChromaPair(cb, cr, chromaWidth, width, x + cast(s32, lane), &weights)
            chromaB[lane] = sample.cb
            chromaR[lane] = sample.cr
        }

        convertYuvRgb16Colors(destination + cast(u64, x * 3), luma + cast(u64, x), Simd.load(&chromaB[0]), Simd.load(&chromaR[0]), factors)
        x += 16
    }

    while x < width
    {
        let sample = sampleLinearChromaPair(cb, cr, chromaWidth, width, x, &weights)
        let d      = cast(s32, sample.cb) - 128
        let e      = cast(s32, sample.cr) - 128
        storeYuvRgbPixel(destination + cast(u64, x * 3),
                         yuvLumaTerm(luma[cast(u64, x)], factors),
                         factors.redCr * e + 128,
                         factors.greenCb * d + factors.greenCr * e + 128,
                         factors.blueCb * d + 128)
        x += 1
    }
}

private struct ChromaRowWeights
{
    scaleX:      f64
    area:        f64
    top, bottom: u64
    topWeight, bottomWeight: f64
}

private func chromaRowWeights(width, height, chromaHeight: s32, stride: u64, y: s32)->ChromaRowWeights
{
    let scaleY = cast(f64, height) * 2
    let py     = Math.clamp((cast(f64, y) * 2 + 1) * chromaHeight - height, 0.0, (chromaHeight - 1) * scaleY)
    let y0     = cast(s32, Math.floor(py / scaleY))
    let y1     = Math.min(y0 + 1, chromaHeight - 1)
    let ty     = py - y0 * scaleY
    let scaleX = cast(f64, width) * 2
    return ChromaRowWeights{scaleX, scaleX * scaleY, cast(u64, y0) * stride, cast(u64, y1) * stride, scaleY - ty, ty}
}

#[Swag.Inline]
private func applyChromaWeights(plane: const [*] u8, row: const *ChromaRowWeights, x0, x1: u64, left, right: f64)->u8
{
    let top    = cast(f64, plane[row.top + x0]) * left + cast(f64, plane[row.top + x1]) * right
    let bottom = cast(f64, plane[row.bottom + x0]) * left + cast(f64, plane[row.bottom + x1]) * right
    return cast(u8, Math.round((top * row.topWeight + bottom * row.bottomWeight) / row.area))
}

// Reconstructs chroma at the normalized texture coordinate of a luma pixel center.
#[Swag.Inline]
private func sampleLinearChromaPair(cb, cr: const [*] u8, chromaWidth, width, x: s32, row: const *ChromaRowWeights)->{cb, cr: u8}
{
    // Keep the center mapping rational until the final division, including exact half-channel values.
    let px   = Math.clamp((cast(f64, x) * 2 + 1) * chromaWidth - width, 0.0, (chromaWidth - 1) * row.scaleX)
    let x0   = cast(s32, Math.floor(px / row.scaleX))
    let x1   = Math.min(x0 + 1, chromaWidth - 1)
    let tx   = px - x0 * row.scaleX
    let left = row.scaleX - tx
    return {applyChromaWeights(cb, row, cast(u64, x0), cast(u64, x1), left, tx),
            applyChromaWeights(cr, row, cast(u64, x0), cast(u64, x1), left, tx)}
}

// Public only because it is embedded in backend-owned storage; callers never construct it.
internal struct YuvConversionFactors
{
    lumaScale:  s32
    lumaOffset: s32
    redCr:      s32
    greenCb:    s32
    greenCr:    s32
    blueCb:     s32
}

// Returns the fixed-point factors shared by conversion, CPU sampling and the GPU shader.
internal func yuvConversionFactors(matrix: YuvMatrix, studioRange: bool)->YuvConversionFactors
{
    let lumaScale  = studioRange ? 298 : 256
    let lumaOffset = studioRange ? 16 : 0
    switch #complete matrix
    {
    case .Bt601:  return studioRange ? YuvConversionFactors{lumaScale, lumaOffset, 409, -100, -208, 516} : YuvConversionFactors{lumaScale, lumaOffset, 359, -88, -183, 454}
    case .Bt709:  return studioRange ? YuvConversionFactors{lumaScale, lumaOffset, 459, -55, -136, 541} : YuvConversionFactors{lumaScale, lumaOffset, 403, -48, -120, 475}
    case .Bt2020: return studioRange ? YuvConversionFactors{lumaScale, lumaOffset, 430, -48, -167, 548} : YuvConversionFactors{lumaScale, lumaOffset, 377, -42, -146, 483}
    }
}

// Returns the scaled luma term of the selected conversion.
#[Swag.Inline]
private func yuvLumaTerm(luma: u8, factors: const *YuvConversionFactors)->s32
{
    let above = cast(s32, luma) - factors.lumaOffset
    return (above & ~(above >> 31)) * factors.lumaScale
}

// Clamps one converted channel to a byte without branching.
#[Swag.Inline]
private func clampYuvChannel(value: s32)->u8
{
    let positive = value & ~(value >> 31)
    return cast(u8, ((positive | ((255 - positive) >> 31)) & 255))
}

// Stores one converted pixel from its scaled luma and the shared chroma terms.
#[Swag.Inline]
private func storeYuvRgbPixel(destination: [*] u8, c298, rTerm, gTerm, bTerm: s32)
{
    destination[0] = clampYuvChannel((c298 + rTerm) >> 8)
    destination[1] = clampYuvChannel((c298 + gTerm) >> 8)
    destination[2] = clampYuvChannel((c298 + bTerm) >> 8)
}

// Converts sixteen luma samples against their eight shared chroma samples, with the
// exact fixed-point arithmetic of the scalar path: the products need 32-bit lanes,
// the signed pack keeps the shifted values intact (they stay within about -204..481),
// and the unsigned pack is exactly the scalar clamp. The three packed color vectors
// then interleave into the 48 output bytes.
#[Swag.Inline]
private func convertYuvRgb16(destination: [*] u8, luma, cb, cr: const [*] u8, factors: const *YuvConversionFactors)
{
    // Each chroma byte serves a pair of pixels.
    const DupPairs = cast(Simd.U8x16, [0'u8, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7])

    let y16 = Simd.subSaturating(Simd.load(luma), Simd.splat(cast(u8, factors.lumaOffset)))
    let yLo = Simd.widenLow(y16)
    let yHi = Simd.widenHigh(y16)
    let y0  = cast #bit(Simd.S32x4, Simd.widenLow(yLo)) * factors.lumaScale
    let y1  = cast #bit(Simd.S32x4, Simd.widenHigh(yLo)) * factors.lumaScale
    let y2  = cast #bit(Simd.S32x4, Simd.widenLow(yHi)) * factors.lumaScale
    let y3  = cast #bit(Simd.S32x4, Simd.widenHigh(yHi)) * factors.lumaScale

    // A chroma plane may end after exactly eight bytes. Read only those bytes; the
    // duplicated high half is ignored by DupPairs.
    let cb8    = cast #bit(Simd.U8x16, Simd.splat(cast(const [*] u64, cb)[0]))
    let cr8    = cast #bit(Simd.U8x16, Simd.splat(cast(const [*] u64, cr)[0]))
    let dBytes = Simd.shuffle(cb8, DupPairs)
    let eBytes = Simd.shuffle(cr8, DupPairs)
    let dSLo   = cast #bit(Simd.S16x8, Simd.widenLow(dBytes)) - 128
    let dSHi   = cast #bit(Simd.S16x8, Simd.widenHigh(dBytes)) - 128
    let eSLo   = cast #bit(Simd.S16x8, Simd.widenLow(eBytes)) - 128
    let eSHi   = cast #bit(Simd.S16x8, Simd.widenHigh(eBytes)) - 128

    let d0 = Simd.widenLow(dSLo)
    let d1 = Simd.widenHigh(dSLo)
    let d2 = Simd.widenLow(dSHi)
    let d3 = Simd.widenHigh(dSHi)
    let e0 = Simd.widenLow(eSLo)
    let e1 = Simd.widenHigh(eSLo)
    let e2 = Simd.widenLow(eSHi)
    let e3 = Simd.widenHigh(eSHi)

    let r8 = Simd.packUnsigned(Simd.packSigned((y0 + e0 * factors.redCr + 128) >> 8, (y1 + e1 * factors.redCr + 128) >> 8),
                               Simd.packSigned((y2 + e2 * factors.redCr + 128) >> 8, (y3 + e3 * factors.redCr + 128) >> 8))
    let g8 = Simd.packUnsigned(Simd.packSigned((y0 + d0 * factors.greenCb + e0 * factors.greenCr + 128) >> 8, (y1 + d1 * factors.greenCb + e1 * factors.greenCr + 128) >> 8),
                               Simd.packSigned((y2 + d2 * factors.greenCb + e2 * factors.greenCr + 128) >> 8, (y3 + d3 * factors.greenCb + e3 * factors.greenCr + 128) >> 8))
    let b8 = Simd.packUnsigned(Simd.packSigned((y0 + d0 * factors.blueCb + 128) >> 8, (y1 + d1 * factors.blueCb + 128) >> 8),
                               Simd.packSigned((y2 + d2 * factors.blueCb + 128) >> 8, (y3 + d3 * factors.blueCb + 128) >> 8))

    storeYuvRgb48(destination, r8, g8, b8)
}

// Interleaves sixteen converted pixels into the 48 output bytes.
//
// Byte k of them is color k % 3 of pixel k / 3; a permutation index of 128 clears the lane, so
// the three spreads combine with plain ors.
#[Swag.Inline]
private func storeYuvRgb48(destination: [*] u8, r8, g8, b8: Simd.U8x16)
{
    const PermR0 = cast(Simd.U8x16, [0'u8, 128, 128, 1, 128, 128, 2, 128, 128, 3, 128, 128, 4, 128, 128, 5])
    const PermG0 = cast(Simd.U8x16, [128'u8, 0, 128, 128, 1, 128, 128, 2, 128, 128, 3, 128, 128, 4, 128, 128])
    const PermB0 = cast(Simd.U8x16, [128'u8, 128, 0, 128, 128, 1, 128, 128, 2, 128, 128, 3, 128, 128, 4, 128])
    const PermR1 = cast(Simd.U8x16, [128'u8, 128, 6, 128, 128, 7, 128, 128, 8, 128, 128, 9, 128, 128, 10, 128])
    const PermG1 = cast(Simd.U8x16, [5'u8, 128, 128, 6, 128, 128, 7, 128, 128, 8, 128, 128, 9, 128, 128, 10])
    const PermB1 = cast(Simd.U8x16, [128'u8, 5, 128, 128, 6, 128, 128, 7, 128, 128, 8, 128, 128, 9, 128, 128])
    const PermR2 = cast(Simd.U8x16, [128'u8, 11, 128, 128, 12, 128, 128, 13, 128, 128, 14, 128, 128, 15, 128, 128])
    const PermG2 = cast(Simd.U8x16, [128'u8, 128, 11, 128, 128, 12, 128, 128, 13, 128, 128, 14, 128, 128, 15, 128])
    const PermB2 = cast(Simd.U8x16, [10'u8, 128, 128, 11, 128, 128, 12, 128, 128, 13, 128, 128, 14, 128, 128, 15])

    Simd.store(destination, Simd.shuffle(r8, PermR0) | Simd.shuffle(g8, PermG0) | Simd.shuffle(b8, PermB0))
    Simd.store(destination + 16, Simd.shuffle(r8, PermR1) | Simd.shuffle(g8, PermG1) | Simd.shuffle(b8, PermB1))
    Simd.store(destination + 32, Simd.shuffle(r8, PermR2) | Simd.shuffle(g8, PermG2) | Simd.shuffle(b8, PermB2))
}

// Converts sixteen luma samples and their per-pixel chroma values with the same
// fixed-point arithmetic and clamping as the scalar path.
#[Swag.Inline]
private func convertYuvRgb16Colors(destination: [*] u8, luma: const [*] u8, dBytes, eBytes: Simd.U8x16, factors: const *YuvConversionFactors)
{
    let y16 = Simd.subSaturating(Simd.load(luma), Simd.splat(cast(u8, factors.lumaOffset)))
    let yLo = Simd.widenLow(y16)
    let yHi = Simd.widenHigh(y16)
    let y0  = cast #bit(Simd.S32x4, Simd.widenLow(yLo)) * factors.lumaScale
    let y1  = cast #bit(Simd.S32x4, Simd.widenHigh(yLo)) * factors.lumaScale
    let y2  = cast #bit(Simd.S32x4, Simd.widenLow(yHi)) * factors.lumaScale
    let y3  = cast #bit(Simd.S32x4, Simd.widenHigh(yHi)) * factors.lumaScale

    let dSLo = cast #bit(Simd.S16x8, Simd.widenLow(dBytes)) - 128
    let dSHi = cast #bit(Simd.S16x8, Simd.widenHigh(dBytes)) - 128
    let eSLo = cast #bit(Simd.S16x8, Simd.widenLow(eBytes)) - 128
    let eSHi = cast #bit(Simd.S16x8, Simd.widenHigh(eBytes)) - 128

    let d0 = Simd.widenLow(dSLo)
    let d1 = Simd.widenHigh(dSLo)
    let d2 = Simd.widenLow(dSHi)
    let d3 = Simd.widenHigh(dSHi)
    let e0 = Simd.widenLow(eSLo)
    let e1 = Simd.widenHigh(eSLo)
    let e2 = Simd.widenLow(eSHi)
    let e3 = Simd.widenHigh(eSHi)

    let r8 = Simd.packUnsigned(Simd.packSigned((y0 + e0 * factors.redCr + 128) >> 8, (y1 + e1 * factors.redCr + 128) >> 8),
                               Simd.packSigned((y2 + e2 * factors.redCr + 128) >> 8, (y3 + e3 * factors.redCr + 128) >> 8))
    let g8 = Simd.packUnsigned(Simd.packSigned((y0 + d0 * factors.greenCb + e0 * factors.greenCr + 128) >> 8, (y1 + d1 * factors.greenCb + e1 * factors.greenCr + 128) >> 8),
                               Simd.packSigned((y2 + d2 * factors.greenCb + e2 * factors.greenCr + 128) >> 8, (y3 + d3 * factors.greenCb + e3 * factors.greenCr + 128) >> 8))
    let b8 = Simd.packUnsigned(Simd.packSigned((y0 + d0 * factors.blueCb + 128) >> 8, (y1 + d1 * factors.blueCb + 128) >> 8),
                               Simd.packSigned((y2 + d2 * factors.blueCb + 128) >> 8, (y3 + d3 * factors.blueCb + 128) >> 8))

    storeYuvRgb48(destination, r8, g8, b8)
}
