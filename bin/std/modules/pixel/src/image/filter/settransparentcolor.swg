using Core

public impl Image
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
    mtd setTransparentColor(color: Color)
    {
        if !.pixelFormat.hasAlpha() or !.pixelFormat.isPacked() do
            return

        if .alphaMode == .Premultiplied do
            .convertAlphaTo(.Straight)

        if .pixelFormat != .BGRA8 and .pixelFormat != .RGBA8
        {
            var context = colorPixelValue(color)
            .transformLogicalPixels(&context)
            {
                let replacement = userData![as PixelValue]
                if value.a == 0
                {
                    value.r = replacement.r
                    value.g = replacement.g
                    value.b = replacement.b
                }
            }

            return
        }

        var replacement = .pixelFormat == .BGRA8 ? cast(u32) color.b | (cast(u32) color.g << 8) | (cast(u32) color.r << 16) : cast(u32) color.r | (cast(u32) color.g << 8) | (cast(u32) color.b << 16)
        .visitVectorBytes(&replacement) #code(block, data)
        {
            let replacementWord = cast(*u32) data!
            let pixels          = Math.Simd.load(cast([*] u32) block)
            let replaceMask     = (pixels & Math.Simd.splat(0xFF00_0000'u32)) == Math.Simd.splat(0'u32)
            let result          = (pixels & ~replaceMask) | (Math.Simd.splat(replacementWord[]) & replaceMask)
            Math.Simd.store(cast([*] u32) block, result)
        }

        let pixels = cast([*] u32) .pixels.buffer!
        let count  = .byteCount / 4
        var offset = (.byteCount - .byteCount % 16) / 4
        while offset < count
        {
            if pixels[offset] >> 24 == 0
            {
                pixels[offset] = replacement
            }

            offset += 1
        }
    }
}
