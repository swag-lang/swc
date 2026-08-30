#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var linear = Brush.createLinearGradient(0, 0, 10, 0, Color.fromArgb(0'u8, Argb.Red), Color.fromArgb(Argb.Blue), .Repeat)
    Swag.assert(linear.type == .LinearGradient)
    Swag.assert(linear.gradientSpread == .Repeat)
    Swag.assert(linear.gradientStops.count == 2)
    Swag.assert(linear.gradientStops[0].offset == 0)
    Swag.assert(linear.gradientStops[1].offset == 1)
    Swag.assert(linear.hasVisibleAlpha())
    Swag.assert(!linear.isOpaque())

    linear.addGradientStop(0.5, Argb.Green)
    Swag.assert(linear.gradientStops.count == 3)
    Swag.assert(linear.gradientStops[0].offset == 0)
    Swag.assert(linear.gradientStops[1].offset == 0.5)
    Swag.assert(linear.gradientStops[2].offset == 1)

    let radial = Brush.createRadialGradient(12, 14, 20, Argb.White, Argb.Black, .Mirror)
    Swag.assert(radial.type == .RadialGradient)
    Swag.assert(radial.gradientSpread == .Mirror)
    Swag.assert(radial.gradientStart == Math.Vector2{12, 14})
    Swag.assert(radial.gradientRadius0 == 0)
    Swag.assert(radial.gradientRadius1 == 20)
    Swag.assert(radial.isOpaque())

    let sweep = Brush.createSweepGradient(Math.Vector2{4, 6}, -90.0'deg, 270.0'deg, Argb.DeepSkyBlue, Argb.Crimson, .Repeat)
    Swag.assert(sweep.type == .SweepGradient)
    Swag.assert(sweep.gradientSpread == .Repeat)
    Swag.assert(sweep.gradientStart == Math.Vector2{4, 6})
    Swag.assert(Math.isEqualEpsilon(sweep.gradientAngle0, -Math.ConstF32.PiBy2, 0.001))
    Swag.assert(Math.isEqualEpsilon(sweep.gradientAngle1, Math.ConstF32.TwoPi - Math.ConstF32.PiBy2, 0.001))
    Swag.assert(sweep.isOpaque())

    var tinted = sweep
    tinted.multiplyTint(Color.fromArgb(128'u8, Argb.White))
    Swag.assert(tinted.color.a == 128)
    Swag.assert(tinted.hasVisibleAlpha())
    Swag.assert(!tinted.isOpaque())

    var transparent = radial
    transparent.setOpacityF32(0)
    Swag.assert(!transparent.hasVisibleAlpha())
    Swag.assert(!transparent.isOpaque())

    let hidden = Brush.createLinearGradient(0, 0, 1, 1, Color.fromArgb(0'u8, Argb.White), Color.fromArgb(0'u8, Argb.Black))
    Swag.assert(!hidden.hasVisibleAlpha())
}

// Gradient storage grows with authored content and preserves every sorted stop.
#test
{
    var gradient = Brush.createLinearGradient(0, 0, 1, 0, Argb.Black, Argb.White)
    for i in 32 do
        gradient.addGradientStop(cast(f32) (31 - i) / 31.0, Color.fromRgb(cast(u8) i, 0, 0))

    Swag.assert(gradient.gradientStops.count == 34)
    for var i = 1'u64; i < gradient.gradientStops.count; i += 1 do
        Swag.assert(gradient.gradientStops[i - 1].offset <= gradient.gradientStops[i].offset)
}
