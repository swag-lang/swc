using Core

impl Image
{
    // Replaces the image's RGB channels with samples from `generator`.
    public mtd fillNoise(generator: *Noise.FastNoise)
    {
        .visitPixels(generator)
        {
            let params = cast(*Noise.FastNoise) (notnull userData)
            let v      = params.sample(x, y)
            let light  = cast(u8) Math.map(v, -1.0, 1.0, 0, 255.0)
            pix[0] = light
            pix[1] = light
            pix[2] = light
        }
    }
}
