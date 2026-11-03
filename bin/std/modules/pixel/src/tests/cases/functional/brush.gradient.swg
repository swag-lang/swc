#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var linear = Brush.createLinearGradient(0, 0, 10, 0, Color.fromArgb(0'u8, Argb.Red), Color.fromArgb(Argb.Blue), .Repeat)
    Swag.require(linear.type == .LinearGradient)
    Swag.require(linear.gradientSpread == .Repeat)
    Swag.require(linear.gradientStops.count == 2)
    Swag.require(linear.gradientStops[0].offset == 0)
    Swag.require(linear.gradientStops[1].offset == 1)
    Swag.require(linear.hasVisibleAlpha())
    Swag.require(not linear.isOpaque())

    linear.addGradientStop(0.5, Argb.Green)
    Swag.require(linear.gradientStops.count == 3)
    Swag.require(linear.gradientStops[0].offset == 0)
    Swag.require(linear.gradientStops[1].offset == 0.5)
    Swag.require(linear.gradientStops[2].offset == 1)

    let radial = Brush.createRadialGradient(12, 14, 20, Argb.White, Argb.Black, .Mirror)
    Swag.require(radial.type == .RadialGradient)
    Swag.require(radial.gradientSpread == .Mirror)
    Swag.require(radial.gradientStart == Math.Vector2{12, 14})
    Swag.require(radial.gradientRadius0 == 0)
    Swag.require(radial.gradientRadius1 == 20)
    Swag.require(radial.isOpaque())

    let sweep = Brush.createSweepGradient({4, 6}, -90.0'deg, 270.0'deg, Argb.DeepSkyBlue, Argb.Crimson, .Repeat)
    Swag.require(sweep.type == .SweepGradient)
    Swag.require(sweep.gradientSpread == .Repeat)
    Swag.require(sweep.gradientStart == Math.Vector2{4, 6})
    Swag.require(Math.isEqualEpsilon(sweep.gradientAngle0, -Math.ConstF32.PiBy2, 0.001))
    Swag.require(Math.isEqualEpsilon(sweep.gradientAngle1, Math.ConstF32.TwoPi - Math.ConstF32.PiBy2, 0.001))
    Swag.require(sweep.isOpaque())

    var tinted = sweep
    tinted.multiplyTint(Color.fromArgb(128'u8, Argb.White))
    Swag.require(tinted.color.a == 128)
    Swag.require(tinted.hasVisibleAlpha())
    Swag.require(not tinted.isOpaque())

    var transparent = radial
    transparent.setOpacityF32(0)
    Swag.require(not transparent.hasVisibleAlpha())
    Swag.require(not transparent.isOpaque())

    let hidden = Brush.createLinearGradient(0, 0, 1, 1, Color.fromArgb(0'u8, Argb.White), Color.fromArgb(0'u8, Argb.Black))
    Swag.require(not hidden.hasVisibleAlpha())
}

// Gradient storage grows with authored content and preserves every sorted stop.
#test
{
    var gradient = Brush.createLinearGradient(0, 0, 1, 0, Argb.Black, Argb.White)
    for i in 32 do
        gradient.addGradientStop(cast(f32, (31 - i)) / 31.0, Color.fromRgb(cast(u8, i), 0, 0))

    Swag.require(gradient.gradientStops.count == 34)
    for var i = 1'u64; i < gradient.gradientStops.count; i += 1 do
        Swag.require(gradient.gradientStops[i - 1].offset <= gradient.gradientStops[i].offset)
}
