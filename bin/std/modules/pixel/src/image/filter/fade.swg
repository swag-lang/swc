using Core

public impl Image
{
    // Blends the color channels toward `color`.
    //
    // `factor` is expected in [0, 1], from the original image at zero to `color` at one.
    // Alpha is unchanged.
    mtd fade(color: Color, factor: f32 = 0.5)
    {
        if not .pixelFormat.isPacked() do
            return

        if .pixelFormat.isGrayscale() or .pixelFormat.bitDepth() != 8 or .alphaMode == .Premultiplied
        {
            var target = PixelValue{cast(f32) color.r / 255.0, cast(f32) color.g / 255.0,
                                    cast(f32) color.b / 255.0, cast(f32) color.a / 255.0}
            var context = {target: target, factor: factor}
            .transformLogicalPixels(&context)
            {
                let params = (cast(const *#decltype(context)) userData!)[]
                value.r = Math.lerp(value.r, params.target.r, params.factor)
                value.g = Math.lerp(value.g, params.target.g, params.factor)
                value.b = Math.lerp(value.b, params.target.b, params.factor)
            }

            return
        }

        var convArrR: [256] u8
        var convArrG: [256] u8
        var convArrB: [256] u8

        if .pixelFormat == .BGR8 or .pixelFormat == .BGRA8
        {
            for i in 256
            {
                convArrR[i] = cast(u8) Math.lerp(cast(f32) i, cast(f32) color.b, factor)
                convArrG[i] = cast(u8) Math.lerp(cast(f32) i, cast(f32) color.g, factor)
                convArrB[i] = cast(u8) Math.lerp(cast(f32) i, cast(f32) color.r, factor)
            }
        }
        elif .pixelFormat == .RGB8 or .pixelFormat == .RGBA8
        {
            for i in 256
            {
                convArrR[i] = cast(u8) Math.lerp(cast(f32) i, cast(f32) color.r, factor)
                convArrG[i] = cast(u8) Math.lerp(cast(f32) i, cast(f32) color.g, factor)
                convArrB[i] = cast(u8) Math.lerp(cast(f32) i, cast(f32) color.b, factor)
            }
        }

        .applyColorLuts(&convArrR[0], &convArrG[0], &convArrB[0])
    }
}
