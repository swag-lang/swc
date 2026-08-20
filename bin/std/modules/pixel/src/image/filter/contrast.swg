using Core

public impl Image
{
    // Change the contrast. 'factor' is [-1, 1]
    mtd contrast(factor: f32 = 0.5)
    {
        // unsupported pixel format
        if .pixelFormat.channels() < 3 or .pixelFormat.bitDepth() != 8 do
            return

        let level             = Math.clamp(factor, -1.0, 1.0) + 1.0
        var convArr: [256] u8 = undefined
        for i in 256 do
            convArr[i] = cast(u8) Math.clamp(((cast(f32) i - 128.0) * level) + 128.0, 0.0, 255.0)

        let table = cast(const [*] u8) &convArr[0]
        .applyColorLuts(table, table, table)
    }
}
