// @LICENCE: MIT
// @ORIGIN: FastNoise Legacy, https://github.com/Auburn/FastNoiseLite/tree/FastNoise-Legacy
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#fastnoise

#global namespace Noise
#global #[Swag.Safety(.All, false)]

// The kinds of noise a [[Core.Noise.FastNoise]] can sample.
public enum FastNoiseKind
{
    Perlin                      // Basic Perlin noise.
    PerlinFractalFbm            // Fractal Brownian motion using Perlin noise.
    PerlinFractalBillow         // Billow-style fractal using Perlin noise.
    PerlinFractalRigidMulti     // Rigid multifractal using Perlin noise.
    Value                       // Basic value noise.
    ValueFractalFbm             // Fractal Brownian motion using value noise.
    ValueFractalBillow          // Billow-style fractal using value noise.
    ValueFractalRigidMulti      // Rigid multifractal using value noise.
}

// A 2D noise generator that combines a noise kind with fractal layering settings.
//
// [[Core.Noise.FastNoise.sample]] scales the coordinates by `frequency` and returns the configured
// kind; the fractal methods sample the coordinates as given.
public struct FastNoise
{
    public
    {
        kind:       FastNoiseKind = .Perlin     // Type of noise to generate.
        seed:       s32 = 1337                  // Seed value for noise generation.
        octaves:    u32 = 3                     // The number of sampled layers; must be at least one.
        frequency:  f32 = 0.01                  // Coordinate scale applied before sampling.
        lacunarity: f32 = 2.0                   // Frequency multiplier between successive layers.
        gain:       f32 = 0.5                   // Amplitude multiplier between successive layers.
    }
}

impl FastNoise
{
    private mtd const validateFractalParameters()
    {
        Swag.assert(.octaves > 0)
        Swag.assert(.lacunarity > 0)
        Swag.assert(.gain >= 0)
    }

    mtd const fractalBounding()->f32
    {
        if .octaves <= 1 do
            return 1

        var amp        = .gain
        var ampFractal = 1.0

        for .octaves - 1
        {
            ampFractal += amp
            amp        *= .gain
        }

        return 1.0 / ampFractal
    }

    // Returns fractal Brownian motion built from Perlin noise at (`x`, `y`).
    public mtd const perlinFractalFbm(x, y: f32)->f32
    {
        .validateFractalParameters()
        var xi  = x
        var yi  = y
        var sum = perlin(xi, yi, .seed)
        var amp = 1.0

        for .octaves - 1
        {
            xi, yi *= .lacunarity
            amp    *= .gain
            sum    += perlin(xi, yi, .seed) * amp
        }

        return sum * .fractalBounding()
    }

    // Returns a billow fractal built from Perlin noise at (`x`, `y`).
    public mtd const perlinFractalBillow(x, y: f32)->f32
    {
        .validateFractalParameters()
        var xi  = x
        var yi  = y
        var sum = Math.abs(perlin(xi, yi, .seed)) * 2 - 1
        var amp = 1.0

        for .octaves - 1
        {
            xi, yi *= .lacunarity
            amp    *= .gain
            sum    += (Math.abs(perlin(xi, yi, .seed)) * 2 - 1) * amp
        }

        return sum * .fractalBounding()
    }

    // Returns a rigid multifractal built from Perlin noise at (`x`, `y`).
    public mtd const perlinFractalRigidMulti(x, y: f32)->f32
    {
        .validateFractalParameters()
        var xi  = x
        var yi  = y
        var sum = 1 - Math.abs(perlin(xi, yi, .seed))
        var amp = 1.0

        for .octaves - 1
        {
            xi, yi *= .lacunarity
            amp    *= .gain
            sum    += (1 - Math.abs(perlin(xi, yi, .seed))) * amp
        }

        return sum * .fractalBounding()
    }

    // Returns fractal Brownian motion built from value noise at (`x`, `y`).
    public mtd const valueFractalFbm(x, y: f32)->f32
    {
        .validateFractalParameters()
        var xi  = x
        var yi  = y
        var sum = Noise.value(xi, yi, .seed)
        var amp = 1.0

        for .octaves - 1
        {
            xi, yi *= .lacunarity
            amp    *= .gain
            sum    += Noise.value(xi, yi, .seed) * amp
        }

        return sum * .fractalBounding()
    }

    // Returns a billow fractal built from value noise at (`x`, `y`).
    public mtd const valueFractalBillow(x, y: f32)->f32
    {
        .validateFractalParameters()
        var xi  = x
        var yi  = y
        var sum = Math.abs(Noise.value(xi, yi, .seed)) * 2 - 1
        var amp = 1.0

        for .octaves - 1
        {
            xi, yi *= .lacunarity
            amp    *= .gain
            sum    += (Math.abs(Noise.value(xi, yi, .seed)) * 2 - 1) * amp
        }

        return sum * .fractalBounding()
    }

    // Returns a rigid multifractal built from value noise at (`x`, `y`).
    public mtd const valueFractalRigidMulti(x, y: f32)->f32
    {
        .validateFractalParameters()
        var xi  = x
        var yi  = y
        var sum = 1 - Math.abs(Noise.value(xi, yi, .seed))
        var amp = 1.0

        for .octaves - 1
        {
            xi, yi *= .lacunarity
            amp    *= .gain
            sum    += (1 - Math.abs(Noise.value(xi, yi, .seed))) * amp
        }

        return sum * .fractalBounding()
    }

    // Returns the configured kind of noise at (`x`, `y`) scaled by `frequency`, in the range -1 to 1.
    public mtd const sample(x, y: f32)->f32
    {
        Swag.assert(.octaves > 0)
        Swag.assert(.frequency >= 0)
        Swag.assert(.lacunarity > 0)
        Swag.assert(.gain >= 0)

        var result: f32

        let xi = x * .frequency
        let yi = y * .frequency

        switch #complete .kind
        {
        case .Perlin:                  result = Noise.perlin(xi, yi, .seed)
        case .PerlinFractalFbm:        result = .perlinFractalFbm(xi, yi)
        case .PerlinFractalBillow:     result = .perlinFractalBillow(xi, yi)
        case .PerlinFractalRigidMulti: result = .perlinFractalRigidMulti(xi, yi)
        case .Value:                   result = Noise.value(xi, yi, .seed)
        case .ValueFractalFbm:         result = .valueFractalFbm(xi, yi)
        case .ValueFractalBillow:      result = .valueFractalBillow(xi, yi)
        case .ValueFractalRigidMulti:  result = .valueFractalRigidMulti(xi, yi)
        }

        return Math.clamp(result, -1.0, 1.0)
    }
}
