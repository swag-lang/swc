using Core

impl Image
{
    // Change the contrast. 'factor' is [-1, 1]
    public mtd contrast(factor: f32 = 0.5)
    {
        // unsupported pixel format
        if .pf.channels() < 3 or .pf.bitDepth() != 8 do
            return

        let level    = Math.clamp(factor, -1.0, 1.0) + 1.0
        var convArr: [256] u8 = undefined
        for i in 256 do
            convArr[i] = cast(u8) Math.clamp(((cast(f32) i - 128.0) * level) + 128.0, 0.0, 255.0)

        let f = &convArr[0]
        .visitPixels(f)
        {
            let arr = cast([*] u8) (assume userData)
            pix[0] = arr[pix[0]]
            pix[1] = arr[pix[1]]
            pix[2] = arr[pix[2]]
        }
    }
}
