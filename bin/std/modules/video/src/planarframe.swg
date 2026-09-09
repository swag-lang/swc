#global public

using Core, Pixel

// One decoded picture in planar YUV, the layout every modern video codec produces.
//
// A codec reconstructs luma and two chroma planes; turning them into packed RGB costs more than
// every other stage of a 4K decode put together, and a consumer that draws the picture through a
// renderer does not need it done on the processor at all. A reader hands the planes over as they
// are through [[Pixel.IRenderer.addImage]]. The resulting texture is drawn with
// [[Pixel.Painter.drawTexture]]; a shader backend converts it while sampling.
//
// Rows are tightly packed: `strideLuma` is `width`, and `strideChroma` and the chroma row count
// are the picture size shifted right by `chromaShift`, rounded up. That shift is one for a 4:2:0
// picture and none for a 4:4:4 one. Storage is reused across frames, so a caller decoding a whole
// stream allocates one picture in total.
//
// ```swag
// var picture: PlanarFrame
// try reader.decodeFramePlanesInto(&picture, index)
// let planes = picture.view()
// var texture = renderer.addImage(&planes)
// painter.drawTexture(rectangle, texture)
// ```
//
// Keep `texture` alive until the submitted frame is rendered, then release it with
// [[Pixel.IRenderer.removeTexture]]. Reuse it for later pictures of the same size with
// [[Pixel.IRenderer.updateTexture]].
struct PlanarFrame
{
    public
    {
        luma:    Array'u8     // Full-resolution luma, `height` rows of `strideLuma`.
        chromaB: Array'u8     // Blue-difference chroma.
        chromaR: Array'u8     // Red-difference chroma.

        width:  s32     // Visible picture width in luma samples.
        height: s32     // Visible picture height in luma samples.

        strideLuma:   u32     // Bytes between luma rows, equal to `width`.
        strideChroma: u32     // Bytes between chroma rows.

        // How far a pixel coordinate shifts right to address the chroma planes: one for 4:2:0,
        // none for 4:4:4.
        chromaShift: s32 = 1

        // Whether the samples use the studio range of 16 to 235, which is what a camera or a
        // screen recorder writes, rather than the full range of 0 to 255.
        studioRange: bool = true

        // Matrix the renderer uses to convert these planes to RGB.
        matrix: YuvMatrix = .Bt601
    }
}

impl PlanarFrame
{
    // Reports whether the picture holds samples.
    mtd const isValid()->bool => .width > 0 and .height > 0 and .luma.count != 0

    // Returns the number of chroma rows: the luma rows shifted down and rounded up.
    mtd const chromaHeight()->s32 => (.height + (1 << .chromaShift) - 1) >> .chromaShift

    // Describes the picture as a borrowed planar view.
    //
    // Hand it to [[Pixel.IRenderer.addImage]] or [[Pixel.IRenderer.updateTexture]] and the
    // renderer converts where it draws, which is the whole reason a decoder produces planes.
    mtd const view()->Pixel.YuvPlanarView
    {
        return {
            luma: .luma.buffer!,
            chromaB: .chromaB.buffer!,
            chromaR: .chromaR.buffer!,
            lumaStride: cast(u64) .strideLuma,
            chromaStride: cast(u64) .strideChroma,
            width: .width,
            height: .height,
            chromaShift: .chromaShift,
            matrix: .matrix,
            studioRange: .studioRange}
    }

    // Resizes the planes for a picture of `width` by `height` whose chroma planes are
    // `chromaShift` halvings smaller, keeping the storage it can.
    mtd resize(width, height: s32, chromaShift = 1's32)
    {
        let round       = (1's32 << chromaShift) - 1
        let chromaWidth = cast(u32) ((width + round) >> chromaShift)
        let chromaRows  = cast(u64) ((height + round) >> chromaShift)
        let lumaSize    = cast(u64) width * cast(u64) height
        let chromaSize  = cast(u64) chromaWidth * chromaRows

        .width        = width
        .height       = height
        .chromaShift  = chromaShift
        .strideLuma   = cast(u32) width
        .strideChroma = chromaWidth
        if .luma.count != lumaSize do
            .luma.resize(lumaSize)
        if .chromaB.count != chromaSize
        {
            .chromaB.resize(chromaSize)
            .chromaR.resize(chromaSize)
        }
    }
}
