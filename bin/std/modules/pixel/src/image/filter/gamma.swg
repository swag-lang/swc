using Core

public impl Image
{
    // Applies gamma correction to the color channels.
    //
    // Each normalized channel is raised to `1 / level`, with `level` clamped to (0, 5]; values
    // above one brighten the image. Alpha is unchanged.
    mtd gamma(level: f32 = 2.2)
    {
        if not .pixelFormat.isPacked() do
            return

        let inverseGamma = 1.0 / Math.clamp(level, Math.ConstF32.Epsilon, 5.0)
        if .pixelFormat.isGrayscale() or .pixelFormat.bitDepth() != 8 or .alphaMode == .Premultiplied
        {
            var context = inverseGamma
            .transformLogicalPixels(&context)
            {
                let exponent = cast(const *f32, userData!)[]
                value.r = Math.pow(Math.max(value.r, 0.0), exponent)
                value.g = Math.pow(Math.max(value.g, 0.0), exponent)
                value.b = Math.pow(Math.max(value.b, 0.0), exponent)
            }

            return
        }

        var channelLut: [256] u8
        for i in 256 do
            channelLut[i] = cast(u8, (Math.pow(i / 255.0, inverseGamma) * 255))

        let table = cast(const [*] u8, &channelLut[0])
        .applyColorLuts(table, table, table)
    }
}
