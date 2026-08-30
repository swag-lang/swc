using Core

public impl Image
{
    // Replaces the image's RGB channels with samples from `generator`.
    mtd fillNoise(generator: *Noise.FastNoise)
    {
        if !.pixelFormat.isPacked() do
            return
        if .pixelFormat.isGrayscale() or .pixelFormat.bitDepth() != 8 or .alphaMode == .Premultiplied
        {
            .transformLogicalPixels(generator)
            {
                let params = cast(*Noise.FastNoise) userData!
                let light  = Math.map(params.sample(x, y), -1.0, 1.0, 0.0, 1.0)
                value.r = light
                value.g = light
                value.b = light
            }

            return
        }

        .visitPixels(generator)
        {
            let params = cast(*Noise.FastNoise) userData!
            let v      = params.sample(x, y)
            let light  = cast(u8) Math.map(v, -1.0, 1.0, 0, 255.0)
            pix[0] = light
            pix[1] = light
            pix[2] = light
        }
    }
}
