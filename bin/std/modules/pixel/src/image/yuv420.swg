#global public

using Core, Core.Math

// One picture in planar 4:2:0, borrowed from whatever produced it.
//
// Every video codec reconstructs this layout: full-resolution luma and two chroma planes at half
// resolution on both axes, so one chroma sample serves a two-by-two block of pixels. A view owns
// nothing and stays valid only while the planes behind it do.
//
// The offsets are already applied, so a cropped picture is described by pointing the planes at
// its visible corner. A 4:2:0 crop is always an even number of luma samples — the format states
// it in chroma units — which is what lets the chroma plane be addressed at half the coordinates.
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
                convertYuvRgb16(destination, luma, cbRow + chromaAt, crRow + chromaAt)
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
                storeYuvRgbPixel(destination, yuvLumaTerm(luma[0]), rTerm, gTerm, bTerm)
                storeYuvRgbPixel(destination + 3, yuvLumaTerm(luma[1]), rTerm, gTerm, bTerm)
                destination += 6
                luma        += 2
                chromaAt    += 1
                remaining   -= 2
            }

            if remaining
            {
                let d = cast(s32) cbRow[chromaAt] - 128
                let e = cast(s32) crRow[chromaAt] - 128
                storeYuvRgbPixel(destination, yuvLumaTerm(luma[0]), 409 * e + 128, -100 * d - 208 * e + 128, 516 * d + 128)
            }
        }
    }
}

private const Yuv420Bands = 16'u32

// Returns the scaled luma term of the limited-range BT.601 conversion.
#[Swag.Inline]
private func yuvLumaTerm(luma: u8)->s32
{
    let above = cast(s32) luma - 16
    return (above & ~(above >> 31)) * 298
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
private func convertYuvRgb16(destination: [*] u8, luma, cb, cr: const [*] u8)
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
