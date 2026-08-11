#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var linear = Brush.createLinearGradient(0, 0, 10, 0, Color.fromArgb(0'u8, Argb.Red), Color.fromArgb(Argb.Blue), .Repeat)
    @assert(linear.type == .LinearGradient)
    @assert(linear.gradientSpread == .Repeat)
    @assert(linear.gradientStops.count == 2)
    @assert(linear.gradientStops[0].offset == 0)
    @assert(linear.gradientStops[1].offset == 1)
    @assert(linear.hasVisibleAlpha())
    @assert(!linear.isOpaque())

    linear.addGradientStop(0.5, Argb.Green)
    @assert(linear.gradientStops.count == 3)
    @assert(linear.gradientStops[0].offset == 0)
    @assert(linear.gradientStops[1].offset == 0.5)
    @assert(linear.gradientStops[2].offset == 1)

    let radial = Brush.createRadialGradient(12, 14, 20, Argb.White, Argb.Black, .Mirror)
    @assert(radial.type == .RadialGradient)
    @assert(radial.gradientSpread == .Mirror)
    @assert(radial.gradientStart == Math.Vector2{12, 14})
    @assert(radial.gradientRadius0 == 0)
    @assert(radial.gradientRadius1 == 20)
    @assert(radial.isOpaque())

    let sweep = Brush.createSweepGradient(Math.Vector2{4, 6}, -90.0'deg, 270.0'deg, Argb.DeepSkyBlue, Argb.Crimson, .Repeat)
    @assert(sweep.type == .SweepGradient)
    @assert(sweep.gradientSpread == .Repeat)
    @assert(sweep.gradientStart == Math.Vector2{4, 6})
    @assert(Math.isEqualEpsilon(sweep.gradientAngle0, -Math.ConstF32.PiBy2, 0.001))
    @assert(Math.isEqualEpsilon(sweep.gradientAngle1, Math.ConstF32.TwoPi - Math.ConstF32.PiBy2, 0.001))
    @assert(sweep.isOpaque())

    var tinted = sweep
    tinted.multiplyTint(Color.fromArgb(128'u8, Argb.White))
    @assert(tinted.color.a == 128)
    @assert(tinted.hasVisibleAlpha())
    @assert(!tinted.isOpaque())

    var transparent = radial
    transparent.setOpacityF32(0)
    @assert(!transparent.hasVisibleAlpha())
    @assert(!transparent.isOpaque())

    let hidden = Brush.createLinearGradient(0, 0, 1, 1, Color.fromArgb(0'u8, Argb.White), Color.fromArgb(0'u8, Argb.Black))
    @assert(!hidden.hasVisibleAlpha())
}

// Gradient storage grows with authored content and preserves every sorted stop.
#test
{
    var gradient = Brush.createLinearGradient(0, 0, 1, 0, Argb.Black, Argb.White)
    for i in 32 do
        gradient.addGradientStop(cast(f32) (31 - i) / 31.0, Color.fromRgb(cast(u8) i, 0, 0))

    @assert(gradient.gradientStops.count == 34)
    for var i = 1'u64; i < gradient.gradientStops.count; i += 1 do
        @assert(gradient.gradientStops[i - 1].offset <= gradient.gradientStops[i].offset)
}
