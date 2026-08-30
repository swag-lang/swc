using Core

public impl Image
{
    // Fade to a given color. 'factor' is [0, 1]
    mtd fade(color: Color, factor: f32 = 0.5)
    {
        if !.pixelFormat.isPacked() do
            return

        if .pixelFormat.isGrayscale() or .pixelFormat.bitDepth() != 8 or .alphaMode == .Premultiplied
        {
            var target = PixelValue{cast(f32) color.r / 255.0, cast(f32) color.g / 255.0,
                                    cast(f32) color.b / 255.0, cast(f32) color.a / 255.0}
            var context = {target: target, factor: factor}
            .transformLogicalPixels(&context)
            {
                let params = userData![as #decltype(context)]
                value.r = Math.lerp(value.r, params.target.r, params.factor)
                value.g = Math.lerp(value.g, params.target.g, params.factor)
                value.b = Math.lerp(value.b, params.target.b, params.factor)
            }

            return
        }

        var convArrR: [256] u8 = undefined
        var convArrG: [256] u8 = undefined
        var convArrB: [256] u8 = undefined

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
