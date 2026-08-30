using Core

public impl Image
{
    // Fill image with 'color'
    mtd fill(color: Color)
    {
        if !.pixelFormat.isPacked() do
            return

        if .pixelFormat.isGrayscale() or .pixelFormat.bitDepth() != 8 or .alphaMode == .Premultiplied
        {
            var logical = PixelValue{cast(f32) color.r / 255.0, cast(f32) color.g / 255.0,
                                     cast(f32) color.b / 255.0, cast(f32) color.a / 255.0}
            .transformLogicalPixels(&logical)
            {
                value = userData![as PixelValue]
            }

            return
        }

        #[Swag.Mixin]
        mtd(PF: PixelFormat) fillFirstLine()
        {
            var pix = .pixels.buffer
            for x in .width
            {
                convertToRGBA8'PF(cast([*] u8) pix!, color.r, color.g, color.b, color.a)
                pix += .bytesPerPixel
            }
        }

        switch .pixelFormat
        {
        case .BGR8:  .fillFirstLine'BGR8()
        case .BGRA8: .fillFirstLine'BGRA8()
        case .RGB8:  .fillFirstLine'RGB8()
        case .RGBA8: .fillFirstLine'RGBA8()
        default:     Debug.assert(false)
        }

        .visitPixels(stride: .width)
        {
            Memory.copy(pix, cast([*] u8) image.pixels.buffer!, cast(u64) image.width * image.bytesPerPixel)
        }
    }
}
