#global #if #command == Swag.CompilerCommand.Test

using Swag, Core

func makeFastNoise()->Noise.FastNoise
{
    var noise: retval
    noise.seed       = 42
    noise.frequency  = 0.125
    noise.octaves    = 3
    noise.lacunarity = 2.25
    noise.gain       = 0.4
    noise.update()
    return noise
}

func makeNoiseColor(noise: &Noise.FastNoise, x, y: s32, alpha: u8)->Color
{
    let value = noise.noise(cast(f32) x, cast(f32) y)
    let light = cast(u8) Math.map(value, -1.0, 1.0, 0, 255.0)
    return Color.fromArgb(alpha, light, light, light)
}

#test
{
    const pixels = [
        10'u8, 20'u8, 30'u8, 40'u8,      50'u8, 60'u8, 70'u8, 80'u8,
        90'u8, 100'u8, 110'u8, 120'u8,   130'u8, 140'u8, 150'u8, 160'u8,
        ]

    var img   = makeImage(2, 2, .BGRA8, pixels)
    var noise = makeFastNoise()
    img.noise(&noise)
    assertImage(img, 2, 2, .BGRA8)

    assertPixel(img, 0, 1, makeNoiseColor(&noise, 0, 0, 40))
    assertPixel(img, 1, 1, makeNoiseColor(&noise, 1, 0, 80))
    assertPixel(img, 0, 0, makeNoiseColor(&noise, 0, 1, 120))
    assertPixel(img, 1, 0, makeNoiseColor(&noise, 1, 1, 160))
}
