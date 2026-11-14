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
// `resize` creates tightly packed rows, while the public strides also describe padded planes when
// their buffers cover every visible row. The chroma width and row count are the picture size
// shifted right by `chromaShift`, rounded up. That shift is one for 4:2:0 and none for 4:4:4.
// Storage is reused across frames, so a caller decoding a whole stream allocates one picture in total.
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

        strideLuma:   u32     // Bytes between luma rows; at least `width`.
        strideChroma: u32     // Bytes between chroma rows; at least the chroma width.

        // How far a pixel coordinate shifts right to address the chroma planes: one for 4:2:0, none for 4:4:4.
        chromaShift: s32 = 1

        // Whether the samples use the studio range of 16 to 235 rather than the full range of 0 to 255.
        //
        // The studio range is what a camera or a screen recorder writes.
        studioRange: bool = true

        // Matrix the renderer uses to convert these planes to RGB.
        matrix: YuvMatrix = .Bt601
    }
}

impl PlanarFrame
{
    // Reports whether all planes contain the samples described by this picture.
    mtd const isValid()->bool
    {
        if .width <= 0 or .height <= 0 or (.chromaShift != 0 and .chromaShift != 1) do
            return false

        let width  = cast(u64, .width)
        let height = cast(u64, .height)
        let chromaWidth  = .chromaShift == 0 ? width : width / 2 + width % 2
        let chromaHeight = .chromaShift == 0 ? height : height / 2 + height % 2
        let lumaStride   = cast(u64, .strideLuma)
        let chromaStride = cast(u64, .strideChroma)
        if lumaStride < width or chromaStride < chromaWidth do
            return false

        let lumaSize   = (height - 1) * lumaStride + width
        let chromaSize = (chromaHeight - 1) * chromaStride + chromaWidth
        return .luma.count >= lumaSize and
               .chromaB.count >= chromaSize and
               .chromaR.count >= chromaSize
    }

    // Returns the number of chroma rows: the luma rows shifted down and rounded up.
    mtd const chromaHeight()->s32 =>
        (.height >> .chromaShift) + ((.height & ((1 << .chromaShift) - 1)) != 0 ? 1 : 0)

    // Describes the picture as a borrowed planar view.
    //
    // Hand it to [[Pixel.IRenderer.addImage]] or [[Pixel.IRenderer.updateTexture]] and the
    // renderer converts where it draws, which is the whole reason a decoder produces planes.
    mtd const view()->Pixel.YuvPlanarView
    {
        return {
            luma: .luma.storage(),
            chromaB: .chromaB.storage(),
            chromaR: .chromaR.storage(),
            lumaStride: cast(u64, .strideLuma),
            chromaStride: cast(u64, .strideChroma),
            width: .width,
            height: .height,
            chromaShift: .chromaShift,
            matrix: .matrix,
            studioRange: .studioRange}
    }

    // Resizes the planes for a picture of `width` by `height`, keeping the storage it can.
    //
    // The chroma planes are `chromaShift` halvings smaller than the luma plane in each direction.
    mtd resize(width, height: s32, chromaShift = 1's32)
    {
        let round       = (1's32 << chromaShift) - 1
        let chromaWidth = cast(u32, (width >> chromaShift) + ((width & round) != 0 ? 1 : 0))
        let chromaRows  = cast(u64, (height >> chromaShift) + ((height & round) != 0 ? 1 : 0))
        let lumaSize    = cast(u64, width) * cast(u64, height)
        let chromaSize  = cast(u64, chromaWidth) * chromaRows

        .width        = width
        .height       = height
        .chromaShift  = chromaShift
        .strideLuma   = cast(u32, width)
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
