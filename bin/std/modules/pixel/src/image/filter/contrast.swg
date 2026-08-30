using Core

public impl Image
{
    // Change the contrast. 'factor' is [-1, 1]
    mtd contrast(factor: f32 = 0.5)
    {
        if !.pixelFormat.isPacked() do
            return

        let level = Math.clamp(factor, -1.0, 1.0) + 1.0
        if .pixelFormat.isGrayscale() or .pixelFormat.bitDepth() != 8 or .alphaMode == .Premultiplied
        {
            var context = level
            .transformLogicalPixels(&context)
            {
                let adjustment = userData![as f32]
                value.r = (value.r - 0.5) * adjustment + 0.5
                value.g = (value.g - 0.5) * adjustment + 0.5
                value.b = (value.b - 0.5) * adjustment + 0.5
            }

            return
        }

        var convArr: [256] u8 = undefined
        for i in 256 do
            convArr[i] = cast(u8) Math.clamp(((cast(f32) i - 128.0) * level) + 128.0, 0.0, 255.0)

        let table = cast(const [*] u8) &convArr[0]
        .applyColorLuts(table, table, table)
    }
}
