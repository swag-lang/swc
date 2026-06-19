#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func assertNoise(value, expected: f32)
{
    @assert(Math.isEqualEpsilon(value, expected, 0.00001'f32))
    @assert(value >= -1'f32 and value <= 1'f32)
}

#test
{
    assertNoise(Noise.perlin(0.25, 0.75, 1337), -0.20206681'f32)
    assertNoise(Noise.perlin(-1.25, 2.5, -42), 0.11906130'f32)
    assertNoise(Noise.perlin(0.25, 0.75, 1.5, 1337), 0.15634045'f32)
    assertNoise(Noise.perlin(-1.25, 2.5, -3.75, -42), 0.59066623'f32)

    assertNoise(Noise.value(0.25, 0.75, 1337), -0.09263688'f32)
    assertNoise(Noise.value(-1.25, 2.5, -42), 0.06757706'f32)
    assertNoise(Noise.value(0.25, 0.75, 1.5, 1337), 0.01064112'f32)
    assertNoise(Noise.value(-1.25, 2.5, -3.75, -42), 0.05278684'f32)

    @assert(Noise.perlin(0'f32, 0'f32, 1337) == 0'f32)
    @assert(Noise.perlin(0'f32, 0'f32, 0'f32, 1337) == 0'f32)
}
