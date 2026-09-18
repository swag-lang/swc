using Core

public impl Image
{
    // Scales the contrast of the color channels around mid gray.
    //
    // `factor` is clamped to [-1, 1]: zero leaves the image unchanged, -1 flattens it to mid
    // gray, and positive values increase contrast. Alpha is unchanged.
    mtd contrast(factor: f32 = 0.5)
    {
        if not .pixelFormat.isPacked() do
            return

        let level = Math.clamp(factor, -1.0, 1.0) + 1.0
        if .pixelFormat.isGrayscale() or .pixelFormat.bitDepth() != 8 or .alphaMode == .Premultiplied
        {
            var context = level
            .transformLogicalPixels(&context)
            {
                let adjustment = (cast(const *f32) userData!)[]
                value.r = (value.r - 0.5) * adjustment + 0.5
                value.g = (value.g - 0.5) * adjustment + 0.5
                value.b = (value.b - 0.5) * adjustment + 0.5
            }

            return
        }

        var convArr: [256] u8
        for i in 256 do
            convArr[i] = cast(u8) Math.clamp(((cast(f32) i - 128.0) * level) + 128.0, 0.0, 255.0)

        let table = cast(const [*] u8) &convArr[0]
        .applyColorLuts(table, table, table)
    }
}
