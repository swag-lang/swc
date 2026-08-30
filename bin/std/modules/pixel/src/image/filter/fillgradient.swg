using Core

struct FillGradient4Context
{
    topLeft, topRight, bottomLeft, bottomRight: Color
}

public impl Image
{
    // Fill with an horizontal gradient from 'color0' to 'color1'
    mtd fillGradient(color0, color1: Color)
    {
        if !.pixelFormat.isPacked() do
            return

        let legacy = (.pixelFormat == .BGR8 or .pixelFormat == .BGRA8 or .pixelFormat == .RGB8 or .pixelFormat == .RGBA8) and .alphaMode == .Straight
        if !legacy
        {
            var context = {color0: color0, color1: color1}
            .transformLogicalPixels(&context)
            {
                let params = userData![as #decltype(context)]
                let factor = image.width > 1 ? x / cast(f32) (image.width - 1) : 0
                let first  = colorPixelValue(params.color0)
                let second = colorPixelValue(params.color1)
                value = {
                    Math.lerp(first.r, second.r, factor),
                    Math.lerp(first.g, second.g, factor),
                    Math.lerp(first.b, second.b, factor),
                    Math.lerp(first.a, second.a, factor)}
            }

            return
        }

        #[Swag.Mixin]
        mtd(PF: PixelFormat) doIt()
        {
            var pix = .pixels.buffer
            for x in .width
            {
                let factor0 = .width > 1 ? x / cast(f32) (.width - 1) : 0
                let b       = cast(u8) Math.lerp(cast(f32) color0.b, cast(f32) color1.b, factor0)
                let g       = cast(u8) Math.lerp(cast(f32) color0.g, cast(f32) color1.g, factor0)
                let r       = cast(u8) Math.lerp(cast(f32) color0.r, cast(f32) color1.r, factor0)
                var a       = 255'u8
                if PF.bitsPerPixel() == 32 do
                    a = cast(u8) Math.lerp(cast(f32) color0.a, cast(f32) color1.a, factor0)
                convertToRGBA8'PF(cast([*] u8) pix!, r, g, b, a)
                pix += .bytesPerPixel
            }
        }

        switch .pixelFormat
        {
        case .BGR8:  .doIt'BGR8()
        case .BGRA8: .doIt'BGRA8()
        case .RGB8:  .doIt'RGB8()
        case .RGBA8: .doIt'RGBA8()
        default:     Debug.assert(false)
        }

        .visitPixels(stride: .width)
        {
            Memory.copy(pix, cast([*] u8) image.pixels.buffer!, cast(u64) image.width * image.bytesPerPixel)
        }
    }

    // Fill with a gradient with a different color at each corner
    mtd fillGradient(topLeft, topRight, bottomLeft, bottomRight: Color)
    {
        if !.pixelFormat.isPacked() do
            return

        var ctx    = FillGradient4Context{topLeft, topRight, bottomLeft, bottomRight}
        let legacy = (.pixelFormat == .BGR8 or .pixelFormat == .BGRA8 or .pixelFormat == .RGB8 or .pixelFormat == .RGBA8) and .alphaMode == .Straight
        if !legacy
        {
            .transformLogicalPixels(&ctx)
            {
                let colors      = userData![as FillGradient4Context]
                let factor0     = image.width > 1 ? x / cast(f32) (image.width - 1) : 0
                let factor1     = image.height > 1 ? y / cast(f32) (image.height - 1) : 0
                let topLeft     = colorPixelValue(colors.topLeft)
                let topRight    = colorPixelValue(colors.topRight)
                let bottomLeft  = colorPixelValue(colors.bottomLeft)
                let bottomRight = colorPixelValue(colors.bottomRight)
                let lower       = PixelValue{
                    Math.lerp(bottomLeft.r, bottomRight.r, factor0), Math.lerp(bottomLeft.g, bottomRight.g, factor0),
                    Math.lerp(bottomLeft.b, bottomRight.b, factor0), Math.lerp(bottomLeft.a, bottomRight.a, factor0)}
                let upper = PixelValue{
                    Math.lerp(topLeft.r, topRight.r, factor0), Math.lerp(topLeft.g, topRight.g, factor0),
                    Math.lerp(topLeft.b, topRight.b, factor0), Math.lerp(topLeft.a, topRight.a, factor0)}
                value = {
                    Math.lerp(lower.r, upper.r, factor1), Math.lerp(lower.g, upper.g, factor1),
                    Math.lerp(lower.b, upper.b, factor1), Math.lerp(lower.a, upper.a, factor1)}
            }

            return
        }

        #[Swag.Mixin]
        mtd(PF: PixelFormat) doIt()
        {
            .visitPixels(&ctx)
            {
                let colors  = cast(*FillGradient4Context) userData!
                let factor0 = image.width > 1 ? x / cast(f32) (image.width - 1) : 0
                let factor1 = image.height > 1 ? y / cast(f32) (image.height - 1) : 0
                let colH1   = Color.lerp(colors.topLeft, colors.topRight, factor0)
                let colH0   = Color.lerp(colors.bottomLeft, colors.bottomRight, factor0)
                let col     = Color.lerp(colH0, colH1, factor1)
                convertToRGBA8'PF(pix, col.r, col.g, col.b, col.a)
            }
        }

        switch .pixelFormat
        {
        case .BGR8:  .doIt'BGR8()
        case .BGRA8: .doIt'BGRA8()
        case .RGB8:  .doIt'RGB8()
        case .RGBA8: .doIt'RGBA8()
        default:     Debug.assert(false)
        }
    }
}
