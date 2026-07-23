#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertFastNoise(value, expected: f32)
{
    @assert(Math.isEqualEpsilon(value, expected, 0.00001'f32))
    @assert(value >= -1'f32 and value <= 1'f32)
}

func initFastNoise()->Noise.FastNoise
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

#test
{
    @assert(@countof(Noise.FastNoiseKind) == 8)

    var noise: Noise.FastNoise
    @assert(noise.kind == .Perlin)
    @assert(noise.seed == 1337)
    @assert(noise.octaves == 3)
    @assert(Math.isEqualEpsilon(noise.frequency, 0.01'f32, 0.00001'f32))
    @assert(Math.isEqualEpsilon(noise.lacunarity, 2'f32, 0.00001'f32))
    @assert(Math.isEqualEpsilon(noise.gain, 0.5'f32, 0.00001'f32))
    @assert(Math.isEqualEpsilon(noise.fractalBounding, 1'f32, 0.00001'f32))

    noise = initFastNoise()
    @assert(Math.isEqualEpsilon(noise.fractalBounding, 0.64102566'f32, 0.00001'f32))

    noise.kind = .Perlin
    assertFastNoise(noise.noise(3.5, -2.25), -0.55220836'f32)

    noise.kind = .PerlinFractalFBM
    assertFastNoise(noise.noise(3.5, -2.25), -0.40943402'f32)

    noise.kind = .PerlinFractalBillow
    assertFastNoise(noise.noise(3.5, -2.25), -0.20360079'f32)

    noise.kind = .PerlinFractalRigidMulti
    assertFastNoise(noise.noise(3.5, -2.25), 0.62231326'f32)

    noise.kind = .Value
    assertFastNoise(noise.noise(3.5, -2.25), 0.10376967'f32)

    noise.kind = .ValueFractalFBM
    assertFastNoise(noise.noise(3.5, -2.25), -0.04323952'f32)

    noise.kind = .ValueFractalBillow
    assertFastNoise(noise.noise(3.5, -2.25), -0.68847048'f32)

    noise.kind = .ValueFractalRigidMulti
    assertFastNoise(noise.noise(3.5, -2.25), 0.86474812'f32)

    noise.octaves = 1
    noise.update()
    @assert(Math.isEqualEpsilon(noise.fractalBounding, 1'f32, 0.00001'f32))
}
