#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    var linear = Brush.createLinearGradient(0, 0, 10, 0, Color.fromArgb(0'u8, Argb.Red), Color.fromArgb(Argb.Blue), .Repeat)
    @assert(linear.type == .LinearGradient)
    @assert(linear.gradientSpread == .Repeat)
    @assert(linear.gradientStopCount == 2)
    @assert(linear.gradientStops[0].offset == 0)
    @assert(linear.gradientStops[1].offset == 1)
    @assert(linear.hasVisibleAlpha())
    @assert(!linear.isOpaque())

    linear.addGradientStop(0.5, Argb.Green)
    @assert(linear.gradientStopCount == 3)
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

    let hidden = Brush.createLinearGradient(0, 0, 1, 1, Color.fromArgb(0'u8, Argb.White), Color.fromArgb(0'u8, Argb.Black))
    @assert(!hidden.hasVisibleAlpha())
}
