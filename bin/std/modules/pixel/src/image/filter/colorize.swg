using Core

public impl Image
{
    // Tints the image with a hue and saturation while keeping each pixel's lightness.
    //
    // `hue`, `saturation`, and `strength` are clamped to [0, 1]. `strength` blends from the
    // original pixel at zero to the fully colorized one at one. Alpha is unchanged.
    #[Swag.Safety(.All, false)]
    mtd colorize(hue, saturation: f32, strength = 1.0)
    {
        if not .pixelFormat.isPacked() do
            return

        let clampedHue        = Math.clamp(hue, 0.0, 1.0)
        let clampedSaturation = Math.clamp(saturation, 0.0, 1.0)
        let clampedStrength   = Math.clamp(strength, 0.0, 1.0)
        if not .hasStraightByteColors()
        {
            var context = {hue: clampedHue, saturation: clampedSaturation, strength: clampedStrength}
            .transformLogicalPixels(&context)
            {
                let params    = cast(const *#decltype(context), userData!)[]
                let lightness = (Math.min(value.r, value.g, value.b) + Math.max(value.r, value.g, value.b)) * 0.5
                let colorized = hslPixelValue(params.hue, params.saturation, lightness)
                value.r = Math.lerp(value.r, colorized.r, params.strength)
                value.g = Math.lerp(value.g, colorized.g, params.strength)
                value.b = Math.lerp(value.b, colorized.b, params.strength)
            }

            return
        }

        // Precompute each lightness in the image's stored channel order.
        var colorByLightness: [256, 3] f32

        if .pixelFormat == .BGR8 or .pixelFormat == .BGRA8
        {
            for i in 256
            {
                let color = Color.fromHsl(clampedHue, clampedSaturation, i / 255.0)
                colorByLightness[i, 0] = cast(f32, color.b)
                colorByLightness[i, 1] = cast(f32, color.g)
                colorByLightness[i, 2] = cast(f32, color.r)
            }
        }
        elif .pixelFormat == .RGB8 or .pixelFormat == .RGBA8
        {
            for i in 256
            {
                let color = Color.fromHsl(clampedHue, clampedSaturation, i / 255.0)
                colorByLightness[i, 0] = cast(f32, color.r)
                colorByLightness[i, 1] = cast(f32, color.g)
                colorByLightness[i, 2] = cast(f32, color.b)
            }
        }

        var context = {colors: cast([*] f32, &colorByLightness[0, 0]), strength: clampedStrength}
        .visitPixels(&context)
        {
            let params    = cast(*#decltype(context), userData!)
            let lowest    = Math.min(pix[0], pix[1], pix[2])
            let highest   = Math.max(pix[0], pix[1], pix[2])
            let lightness = cast(u8, ((cast(s32, highest) + cast(s32, lowest)) / 2))

            let colors = params.colors + (cast(s32, lightness) * 3)
            pix[0] = cast(u8, Math.lerp(cast(f32, pix[0]), colors[0], params.strength))
            pix[1] = cast(u8, Math.lerp(cast(f32, pix[1]), colors[1], params.strength))
            pix[2] = cast(u8, Math.lerp(cast(f32, pix[2]), colors[2], params.strength))
        }
    }
}
