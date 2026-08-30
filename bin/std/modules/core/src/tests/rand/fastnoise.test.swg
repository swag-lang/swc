#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertFastNoise(value, expected: f32)
{
    Swag.assert(Math.isEqualEpsilon(value, expected, 0.00001'f32))
    Swag.assert(value >= -1'f32 and value <= 1'f32)
}

func initFastNoise()->Noise.FastNoise
{
    var noise: retval
    noise.seed       = 42
    noise.frequency  = 0.125
    noise.octaves    = 3
    noise.lacunarity = 2.25
    noise.gain       = 0.4
    return noise
}

#test
{
    Swag.assert(Noise.FastNoiseKind.count == 8)

    var noise: Noise.FastNoise
    Swag.assert(noise.kind == .Perlin)
    Swag.assert(noise.seed == 1337)
    Swag.assert(noise.octaves == 3)
    Swag.assert(Math.isEqualEpsilon(noise.frequency, 0.01'f32, 0.00001'f32))
    Swag.assert(Math.isEqualEpsilon(noise.lacunarity, 2'f32, 0.00001'f32))
    Swag.assert(Math.isEqualEpsilon(noise.gain, 0.5'f32, 0.00001'f32))
    noise = initFastNoise()

    noise.kind = .Perlin
    assertFastNoise(noise.sample(3.5, -2.25), -0.55220836'f32)

    noise.kind = .PerlinFractalFbm
    let perlinFbm = noise.sample(3.5, -2.25)
    Swag.assert(perlinFbm >= -1 and perlinFbm <= 1)

    noise.kind = .PerlinFractalBillow
    let perlinBillow = noise.sample(3.5, -2.25)
    Swag.assert(perlinBillow >= -1 and perlinBillow <= 1)

    noise.kind = .PerlinFractalRigidMulti
    let perlinRigid = noise.sample(3.5, -2.25)
    Swag.assert(perlinRigid >= -1 and perlinRigid <= 1)

    noise.kind = .Value
    assertFastNoise(noise.sample(3.5, -2.25), 0.10376967'f32)

    noise.kind = .ValueFractalFbm
    let valueFbm = noise.sample(3.5, -2.25)
    Swag.assert(valueFbm >= -1 and valueFbm <= 1)

    noise.kind = .ValueFractalBillow
    let valueBillow = noise.sample(3.5, -2.25)
    Swag.assert(valueBillow >= -1 and valueBillow <= 1)

    noise.kind = .ValueFractalRigidMulti
    let valueRigid = noise.sample(3.5, -2.25)
    Swag.assert(valueRigid >= -1 and valueRigid <= 1)

    noise.kind = .PerlinFractalFbm
    let withGain = noise.sample(3.5, -2.25)
    noise.gain = 0
    let noGain = noise.sample(3.5, -2.25)
    Swag.assert(!Math.isEqualEpsilon(withGain, noGain, 0.00001'f32))

    noise.octaves = 1
    Swag.assert(noise.sample(3.5, -2.25) >= -1)
}
