using Core

public impl Image
{
    // Change the gamma.
    mtd gamma(level: f32 = 2.2)
    {
        // unsupported pixel format
        if .pixelFormat.channels() < 3 or .pixelFormat.bitDepth() != 8 do
            return

        let g = 1.0 / Math.clamp(level, Math.ConstF32.Epsilon, 5.0)

        var convArr: [256] u8 = undefined
        for i in 256 do
            convArr[i] = cast(u8) (Math.pow(i / 255.0, g) * 255)

        let table = cast(const [*] u8) &convArr[0]
        .applyColorLuts(table, table, table)
    }
}
