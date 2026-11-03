#global if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    let full = strokeDarkness(1)
    Swag.assert(full > 0)

    // Half a pixel is half the ink of a whole one, and a quarter is a quarter of it.
    let half    = strokeDarkness(0.5)
    let quarter = strokeDarkness(0.25)
    Swag.assert(half > 0 and quarter > 0)
    Swag.assert(Math.abs(cast(f32, half) - cast(f32, quarter) * 2) < cast(f32, quarter) * 0.2)

    // The measure is device pixels, so a hairline on a display that scales up is a whole pixel
    // and keeps its full weight.
    let scaledUp = strokeDarkness(0.5, 2)
    Swag.assert(cast(f32, scaledUp) > cast(f32, half) * 3)

    // A pen with no width at all still draws nothing.
    Swag.assert(strokeDarkness(0) == 0)
}
