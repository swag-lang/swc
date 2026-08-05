using Core

impl Image
{
    // Replaces the color of every fully transparent pixel with `color`, leaving alpha alone.
    //
    // A pixel nothing covers still carries a color, and every operation that averages
    // neighbors pulls that color into the visible edge beside it: a linear sampler
    // minifying the image, a box downsample, a tint. Black behind a shape is exactly what
    // gives a scaled-down sprite its dark halo, so an atlas or an icon usually wants white
    // there, or the color of the art around it. Only pixels at alpha zero change, so what
    // the image actually shows is untouched.
    //
    // A format without an alpha channel has no fully transparent pixel and is left as is.
    public mtd setTransparentColor(color: Color)
    {
        if .pixelFormat != .BGRA8 and .pixelFormat != .RGBA8 do
            return

        var replacement: [3] u8 = undefined
        if .pixelFormat == .BGRA8 do
            replacement = [color.b, color.g, color.r]
        else do
            replacement = [color.r, color.g, color.b]

        let f = &replacement[0]
        .visitPixels(f)
        {
            if pix[3] == 0
            {
                let src = cast([*] u8) userData!
                pix[0] = src[0]
                pix[1] = src[1]
                pix[2] = src[2]
            }
        }
    }
}
