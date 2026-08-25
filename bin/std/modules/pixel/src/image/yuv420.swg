#global public

using Core, Core.Math

// Selects the matrix that converts luma and chroma samples to RGB.
enum YuvMatrix
{
    Bt601      // ITU-R BT.601, used by standard-definition video.
    Bt709      // ITU-R BT.709, used by high-definition SDR video.
    Bt2020     // ITU-R BT.2020 non-constant-luminance conversion.
}

// One picture in planar 4:2:0, borrowed from whatever produced it.
//
// Every video codec reconstructs this layout: full-resolution luma and two chroma planes at half
// resolution on both axes, so one chroma sample serves a two-by-two block of pixels. A view owns
// nothing and stays valid only while the planes behind it do.
//
// The offsets are already applied, so a cropped picture is described by pointing the planes at
// its visible corner. A 4:2:0 crop is always an even number of luma samples — the format states
// it in chroma units — which is what lets the chroma plane be addressed at half the coordinates.
//
// Rows run top-down: the plane pointers address the top-left visible sample, which is the order
// every codec reconstructs a picture in. [[Pixel.Image]] stores its rows the other way round, so
// a conversion into one writes them in reverse, and a renderer that samples the planes directly
// accounts for the difference itself.
struct Yuv420View
{
    public
    {
        luma:    const [*] u8     // Full-resolution luma of the visible corner.
        chromaB: const [*] u8     // Blue-difference chroma at half resolution.
        chromaR: const [*] u8     // Red-difference chroma at half resolution.

        lumaStride:   u64     // Bytes between luma rows.
        chromaStride: u64     // Bytes between chroma rows.

        width:  s32     // Visible width in luma samples.
        height: s32     // Visible height in luma samples.

        matrix:      YuvMatrix = .Bt601     // Matrix used when the planes are converted to RGB.
        studioRange: bool      = true       // Whether luma uses 16..235 rather than the full 0..255 range.
    }
}

impl Yuv420View
{
    // Converts the picture into `target`, which is created or reused as RGB8.
    //
    // Bands of rows are independent, so the work fans through the scheduler when one is running.
    // A caller drawing through a renderer should not need this at all: converting a large picture
    // costs more processor time than decoding it, and a renderer converts where it draws.
    mtd const convertToRgb(target: *Image)
    {
        if target.width != .width or target.height != .height or target.pixelFormat != .RGB8 do
            target[] = Image.create(.width, .height, .RGB8)

        let bandCount = Math.min(Math.min(Jobs.workerCount(), Yuv420Bands), cast(u32) .height)
        if bandCount <= 1
        {
            .convertRowsToRgb(target, 0, .height)
            return
        }

        var context = {view: me, target: target, bandCount: bandCount}
        Jobs.parallelFor(bandCount, &context)
        {
            let state = cast(*#decltype(context)) data!
            let first = state.view.height * cast(s32) index / cast(s32) state.bandCount
            let end   = state.view.height * cast(s32) (index + 1) / cast(s32) state.bandCount
            state.view.convertRowsToRgb(state.target, first, end)
        }
    }

    // Converts rows `firstY` until `endY` into an RGB8 `target` of the same geometry.
    //
    // Bands write disjoint destination rows, so they run concurrently on one target.
    mtd const convertRowsToRgb(target: *Image, firstY, endY: s32)
    {
        let factors = .conversionFactors()
        for y in firstY until endY
        {
            var destination = target.pixels.buffer! + cast(u64) (.height - y - 1) * cast(u64) target.rowStride
            var luma        = .luma + cast(u64) y * .lumaStride
            let chromaRow   = cast(u64) (y >> 1) * .chromaStride
            let cbRow       = .chromaB + chromaRow
            let crRow       = .chromaR + chromaRow

            // Two horizontal luma samples share one chroma sample, so the chroma terms of the
            // conversion are computed once per pair.
            var chromaAt  = 0'u64
            var remaining = .width
            while remaining >= 16
            {
                convertYuvRgb16(destination, luma, cbRow + chromaAt, crRow + chromaAt, &factors)
                destination += 48
                luma        += 16
                chromaAt    += 8
                remaining   -= 16
            }

            while remaining >= 2
            {
                let d     = cast(s32) cbRow[chromaAt] - 128
                let e     = cast(s32) crRow[chromaAt] - 128
                let rTerm = factors.redCr * e + 128
                let gTerm = factors.greenCb * d + factors.greenCr * e + 128
                let bTerm = factors.blueCb * d + 128
                storeYuvRgbPixel(destination, yuvLumaTerm(luma[0], &factors), rTerm, gTerm, bTerm)
                storeYuvRgbPixel(destination + 3, yuvLumaTerm(luma[1], &factors), rTerm, gTerm, bTerm)
                destination += 6
                luma        += 2
                chromaAt    += 1
                remaining   -= 2
            }

            if remaining
            {
                let d = cast(s32) cbRow[chromaAt] - 128
                let e = cast(s32) crRow[chromaAt] - 128
                storeYuvRgbPixel(destination,
                                 yuvLumaTerm(luma[0], &factors),
                                 factors.redCr * e + 128,
                                 factors.greenCb * d + factors.greenCr * e + 128,
                                 factors.blueCb * d + 128)
            }
        }
    }

    // Returns the fixed-point factors shared by the scalar, SIMD, CPU-renderer, and shader paths.
    internal mtd const conversionFactors()->YuvConversionFactors
    {
        let lumaScale  = .studioRange ? 298 : 256
        let lumaOffset = .studioRange ? 16 : 0
        switch #complete .matrix
        {
        case .Bt601:  return .studioRange ? {lumaScale, lumaOffset, 409, -100, -208, 516} : {lumaScale, lumaOffset, 359, -88, -183, 454}
        case .Bt709:  return .studioRange ? {lumaScale, lumaOffset, 459, -55, -136, 541} : {lumaScale, lumaOffset, 403, -48, -120, 475}
        case .Bt2020: return .studioRange ? {lumaScale, lumaOffset, 430, -48, -167, 548} : {lumaScale, lumaOffset, 377, -42, -146, 483}
        }
    }
}

private const Yuv420Bands = 16'u32

// Public only because it is embedded in backend-owned storage; callers never construct it.
#[Swag.NoDoc]
struct YuvConversionFactors
{
    lumaScale:  s32
    lumaOffset: s32
    redCr:      s32
    greenCb:    s32
    greenCr:    s32
    blueCb:     s32
}

// Returns the scaled luma term of the selected conversion.
#[Swag.Inline]
private func yuvLumaTerm(luma: u8, factors: const *YuvConversionFactors)->s32
{
    let above = cast(s32) luma - factors.lumaOffset
    return (above & ~(above >> 31)) * factors.lumaScale
}

// Clamps one converted channel to a byte without branching.
#[Swag.Inline]
private func clampYuvChannel(value: s32)->u8
{
    let positive = value & ~(value >> 31)
    return cast(u8) ((positive | ((255 - positive) >> 31)) & 255)
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
    const DupPairs = cast(Simd.U8x16) [0'u8, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7]

    let y16 = Simd.subSaturating(Simd.load(luma), Simd.splat(cast(u8) factors.lumaOffset))
    let yLo = Simd.widenLow(y16)
    let yHi = Simd.widenHigh(y16)
    let y0  = (cast #bit(Simd.S32x4) Simd.widenLow(yLo)) * factors.lumaScale
    let y1  = (cast #bit(Simd.S32x4) Simd.widenHigh(yLo)) * factors.lumaScale
    let y2  = (cast #bit(Simd.S32x4) Simd.widenLow(yHi)) * factors.lumaScale
    let y3  = (cast #bit(Simd.S32x4) Simd.widenHigh(yHi)) * factors.lumaScale

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

    let r8 = Simd.packUnsigned(Simd.packSigned((y0 + e0 * factors.redCr + 128) >> 8, (y1 + e1 * factors.redCr + 128) >> 8),
                               Simd.packSigned((y2 + e2 * factors.redCr + 128) >> 8, (y3 + e3 * factors.redCr + 128) >> 8))
    let g8 = Simd.packUnsigned(Simd.packSigned((y0 + d0 * factors.greenCb + e0 * factors.greenCr + 128) >> 8, (y1 + d1 * factors.greenCb + e1 * factors.greenCr + 128) >> 8),
                               Simd.packSigned((y2 + d2 * factors.greenCb + e2 * factors.greenCr + 128) >> 8, (y3 + d3 * factors.greenCb + e3 * factors.greenCr + 128) >> 8))
    let b8 = Simd.packUnsigned(Simd.packSigned((y0 + d0 * factors.blueCb + 128) >> 8, (y1 + d1 * factors.blueCb + 128) >> 8),
                               Simd.packSigned((y2 + d2 * factors.blueCb + 128) >> 8, (y3 + d3 * factors.blueCb + 128) >> 8))

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
