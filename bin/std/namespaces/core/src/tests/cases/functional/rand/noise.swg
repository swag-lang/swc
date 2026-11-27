#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertNoise(value, expected: f32)
{
    Swag.require(Math.isEqualEpsilon(value, expected, 0.00001_f32))
    Swag.require(value >= -1_f32 and value <= 1_f32)
}

#test
{
    assertNoise(Noise.perlin(0.25, 0.75, 1337), -0.20206681_f32)
    assertNoise(Noise.perlin(-1.25, 2.5, -42), 0.11906130_f32)
    assertNoise(Noise.perlin(0.25, 0.75, 1.5, 1337), 0.15634045_f32)
    assertNoise(Noise.perlin(-1.25, 2.5, -3.75, -42), 0.59066623_f32)

    assertNoise(Noise.value(0.25, 0.75, 1337), -0.09263688_f32)
    assertNoise(Noise.value(-1.25, 2.5, -42), 0.06757706_f32)
    assertNoise(Noise.value(0.25, 0.75, 1.5, 1337), 0.01064112_f32)
    assertNoise(Noise.value(-1.25, 2.5, -3.75, -42), 0.05278684_f32)

    Swag.require(Noise.perlin(0_f32, 0_f32, 1337) == 0_f32)
    Swag.require(Noise.perlin(0_f32, 0_f32, 0_f32, 1337) == 0_f32)
}
