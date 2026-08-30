using Core

public impl Image
{
    // Colorize the image by setting the hue and saturation.
    #[Swag.Safety(.All, false)]
    mtd colorize(hue, saturation: f32, strength = 1.0)
    {
        if !.pixelFormat.isPacked() do
            return

        let h      = Math.clamp(hue, 0.0, 1.0)
        let s      = Math.clamp(saturation, 0.0, 1.0)
        let st     = Math.clamp(strength, 0.0, 1.0)
        let legacy = (.pixelFormat == .BGR8 or .pixelFormat == .BGRA8 or .pixelFormat == .RGB8 or .pixelFormat == .RGBA8) and .alphaMode == .Straight
        if !legacy
        {
            var context = {h: h, s: s, strength: st}
            .transformLogicalPixels(&context)
            {
                let params    = userData![as #decltype(context)]
                let lightness = (Math.min(value.r, value.g, value.b) + Math.max(value.r, value.g, value.b)) * 0.5
                let colorized = hslPixelValue(params.h, params.s, lightness)
                value.r = Math.lerp(value.r, colorized.r, params.strength)
                value.g = Math.lerp(value.g, colorized.g, params.strength)
                value.b = Math.lerp(value.b, colorized.b, params.strength)
            }

            return
        }

        // Precompute bgr depending on luminance
        var convArr: [256, 3] f32 = undefined

        if .pixelFormat == .BGR8 or .pixelFormat == .BGRA8
        {
            for i in 256
            {
                let c = Color.fromHsl(h, s, i / 255.0)
                convArr[i, 0] = cast(f32) c.b
                convArr[i, 1] = cast(f32) c.g
                convArr[i, 2] = cast(f32) c.r
            }
        }
        elif .pixelFormat == .RGB8 or .pixelFormat == .RGBA8
        {
            for i in 256
            {
                let c = Color.fromHsl(h, s, i / 255.0)
                convArr[i, 0] = cast(f32) c.r
                convArr[i, 1] = cast(f32) c.g
                convArr[i, 2] = cast(f32) c.b
            }
        }

        var f = {precalc: cast([*] f32) &convArr[0, 0], st: st}
        .visitPixels(&f)
        {
            let params = cast(*#decltype(f)) userData!
            let min    = Math.min(pix[0], pix[1], pix[2])
            let max    = Math.max(pix[0], pix[1], pix[2])
            let lum    = cast(u8) ((cast(s32) max + cast(s32) min) / 2)

            let precalc = params.precalc + (cast(s32) lum * 3)
            pix[0] = cast(u8) Math.lerp(cast(f32) pix[0], precalc[0], params.st)
            pix[1] = cast(u8) Math.lerp(cast(f32) pix[1], precalc[1], params.st)
            pix[2] = cast(u8) Math.lerp(cast(f32) pix[2], precalc[2], params.st)
        }
    }
}
