#global public

using Core, Pixel

// One decoded picture in planar 4:2:0, the layout every modern video codec produces.
//
// A codec reconstructs luma and two half-resolution chroma planes; turning them into packed RGB
// costs more than every other stage of a 4K decode put together, and a consumer that draws the
// picture through a renderer does not need it done on the processor at all. A reader hands the
// planes over as they are, and [[Pixel.Painter.drawVideoFrame]] converts them where the picture
// is drawn.
//
// Rows are tightly packed: `strideLuma` is `width` and `strideChroma` is `(width + 1) / 2`. The
// chroma planes carry `(height + 1) / 2` rows. Storage is reused across frames, so a caller
// decoding a whole stream allocates one picture in total.
//
// ```swag
// var picture: PlanarFrame
// while reader.decodeFramePlanesInto(&picture, index)
// {
//     painter.drawVideoFrame(rectangle, &picture)
//     index += 1
// }
// ```
struct PlanarFrame
{
    public
    {
        luma:    Array'u8     // Full-resolution luma, `height` rows of `strideLuma`.
        chromaB: Array'u8     // Blue-difference chroma at half resolution.
        chromaR: Array'u8     // Red-difference chroma at half resolution.

        width:  s32     // Visible picture width in luma samples.
        height: s32     // Visible picture height in luma samples.

        strideLuma:   u32     // Bytes between luma rows, equal to `width`.
        strideChroma: u32     // Bytes between chroma rows, equal to `(width + 1) / 2`.

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

    // Returns the number of chroma rows, which is half the luma rows rounded up.
    mtd const chromaHeight()->s32 => (.height + 1) / 2

    // Describes the picture as a borrowed planar view.
    //
    // Hand it to [[Pixel.IRenderer.addImage]] or [[Pixel.IRenderer.updateTexture]] and the
    // renderer converts where it draws, which is the whole reason a decoder produces planes.
    mtd const view()->Pixel.Yuv420View
    {
        return {
            luma: .luma.buffer!,
            chromaB: .chromaB.buffer!,
            chromaR: .chromaR.buffer!,
            lumaStride: cast(u64) .strideLuma,
            chromaStride: cast(u64) .strideChroma,
            width: .width,
            height: .height,
            matrix: .matrix,
            studioRange: .studioRange}
    }

    // Resizes the planes for a picture of `width` by `height`, keeping the storage it can.
    mtd resize(width, height: s32)
    {
        let chromaWidth = cast(u32) ((width + 1) / 2)
        let chromaRows  = cast(u64) ((height + 1) / 2)
        let lumaSize    = cast(u64) width * cast(u64) height
        let chromaSize  = cast(u64) chromaWidth * chromaRows

        .width        = width
        .height       = height
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
