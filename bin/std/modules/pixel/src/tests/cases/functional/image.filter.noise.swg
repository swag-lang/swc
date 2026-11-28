#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func makeFastNoise()->Noise.FastNoise
{
    var noise: #returntype
    noise.seed       = 42
    noise.frequency  = 0.125
    noise.octaves    = 3
    noise.lacunarity = 2.25
    noise.gain       = 0.4
    return noise
}

func makeNoiseColor(noise: *Noise.FastNoise, x, y: s32, alpha: u8)->Color
{
    let value = noise.sample(cast(f32, x), cast(f32, y))
    let light = cast(u8, Math.map(value, -1.0, 1.0, 0, 255.0))
    return Color.fromArgb(alpha, light, light, light)
}

#test
{
    const pixels = [
        10_u8, 20_u8, 30_u8, 40_u8, 50_u8, 60_u8, 70_u8, 80_u8,
        90_u8, 100_u8, 110_u8, 120_u8, 130_u8, 140_u8, 150_u8, 160_u8]

    var img   = makeImage(2, 2, .BGRA8, pixels)
    var noise = makeFastNoise()
    img.fillNoise(&noise)
    assertImage(img, 2, 2, .BGRA8)

    assertPixel(img, 0, 1, makeNoiseColor(&noise, 0, 0, 40))
    assertPixel(img, 1, 1, makeNoiseColor(&noise, 1, 0, 80))
    assertPixel(img, 0, 0, makeNoiseColor(&noise, 0, 1, 120))
    assertPixel(img, 1, 0, makeNoiseColor(&noise, 1, 1, 160))
}
