#global public

using Core

// Selects the paint source represented by a [[Pixel.Brush]].
enum BrushType
{
    SolidColor         // A uniform color.
    Texture            // A renderer-owned texture modulated by the brush tint.
    Hatch              // A repeating built-in monochrome pattern.
    LinearGradient     // A gradient along a line segment.
    RadialGradient     // A gradient between two concentric radii.
    SweepGradient      // An angular gradient around a center.
}

// Selects how a gradient behaves outside its normalized `[0, 1]` interval.
enum GradientSpread
{
    Clamp      // Extend the nearest endpoint color.
    Repeat     // Restart the gradient at every integer interval.
    Mirror     // Alternate forward and reversed intervals.
}

// Associates a normalized gradient position with a straight-alpha color.
struct GradientStop
{
    public
    {
        offset: f32       // Position in `[0, 1]`.
        color:  Color     // Color sampled at `offset`.
    }
}

// Describes a reusable fill source for painter shapes.
//
// Construct brushes with the `create...` functions, then optionally add sorted
// color stops or apply a tint. Gradient geometry is expressed in painter
// path-space coordinates.
//
// ## Example
//
// ```swag
// var brush = Brush.createLinearGradient({0, 0}, {160, 0},
//                                        Color.fromArgb(Argb.DodgerBlue),
//                                        Color.fromArgb(Argb.DeepPink))
// brush.addGradientStop(0.5, Color.fromArgb(Argb.White))
// ```
struct Brush
{
    public
    {
        color:   Color      = Color.fromArgb(Argb.White)     // Color or multiplicative tint.
        type:    BrushType  = SolidColor                     // Active paint-source variant.
        hatch:   HatchStyle = Dot                            // Built-in hatch used by `.Hatch`.
        texture: Texture                                     // Texture used by `.Texture`.
        uvMode:  UVMode     = Fill                           // Texture coverage mode.
        uvRect:  Math.Rectangle                              // Source texel rectangle used by `.FillSubRect`.

        gradientStart:   Math.Vector2               // Linear start point or radial/sweep center.
        gradientEnd:     Math.Vector2               // Linear end point or secondary radial center.
        gradientRadius0: f32                        // Inner radial radius, in pixels.
        gradientRadius1: f32                        // Outer radial radius, in pixels.
        gradientAngle0:  f32                        // Sweep start angle, in radians.
        gradientAngle1:  f32                        // Sweep end angle, in radians.
        gradientSpread:  GradientSpread = Clamp     // Sampling outside the endpoint interval.
        gradientStops:   Array'GradientStop         // Stops sorted by increasing offset, without a format-specific fixed limit.
    }
}

impl Brush
{
    // Reports whether the brush can contribute nonzero alpha.
    mtd const hasVisibleAlpha()->bool
    {
        switch #complete .type
        {
        case .SolidColor, .Texture, .Hatch:
            return .color.a != 0

        case .LinearGradient, .RadialGradient, .SweepGradient:
            if .color.a == 0 do
                return false

            for stop in .gradientStops
            {
                if stop.color.a do
                    return true
            }

            return false
        }
    }

    // Reports whether every color produced by the brush is fully opaque.
    mtd const isOpaque()->bool
    {
        switch #complete .type
        {
        case .SolidColor, .Hatch:
            return .color.a == 255

        case .Texture:
            return .color.a == 255 and !.texture.pixelFormat.hasAlpha()

        case .LinearGradient, .RadialGradient, .SweepGradient:
            if .color.a != 255 do
                return false

            for stop in .gradientStops
            {
                if stop.color.a != 255 do
                    return false
            }

            return true
        }
    }

    // Inserts a gradient stop in increasing offset order.
    //
    // `offset` is clamped to `[0, 1]`. Stops at the same offset retain their
    // insertion order, which preserves hard transitions.
    mtd addGradientStop(offset: f32, color: Color)
    {
        let clamped       = Math.saturate(offset)
        var insertAt: u64 = .gradientStops.count
        for i in .gradientStops.count
        {
            if clamped < .gradientStops[i].offset
            {
                insertAt = i
                break
            }
        }

        .gradientStops.insertAt(insertAt, GradientStop{clamped, color})
    }

    // Set the paint color multiplier used by textures, hatches and gradients.
    mtd setTint(color: Color)
    {
        .color = color
    }

    // Multiply the current paint color multiplier.
    mtd multiplyTint(color: Color)
    {
        .color = Color.multiply(.color, color)
    }

    // Set the paint opacity while preserving the current tint.
    mtd setOpacity(alpha: u8)
    {
        .color = .color.withAlpha(alpha)
    }

    // Set the paint opacity while preserving the current tint.
    mtd setOpacityF32(alpha: f32)
    {
        .color = .color.withAlphaF32(alpha)
    }

    // Multiply the current paint opacity while preserving the current tint.
    mtd multiplyOpacity(alpha: f32)
    {
        let factor = Math.saturate(alpha)
        .color = .color.withAlphaF32((cast(f32) .color.a / 255.0) * factor)
    }

    // Creates a uniform straight-alpha color brush.
    func createSolid(color: Color)->Brush
    {
        var result: retval
        result.color = color
        result.type  = .SolidColor
        return result
    }

    // Creates an untinted brush that stretches the complete texture.
    func createTexture(texture: Texture)->Brush
    {
        var result: retval
        result.color   = Color.fromArgb(Argb.White)
        result.type    = BrushType.Texture
        result.texture = texture
        result.uvMode  = .Fill
        return result
    }

    // Creates an untinted brush that repeats the texture.
    func createTiled(texture: Texture)->Brush
    {
        var result: retval
        result.color   = Color.fromArgb(Argb.White)
        result.type    = BrushType.Texture
        result.texture = texture
        result.uvMode  = .Tile
        return result
    }

    // Creates a repeating built-in hatch with the specified color.
    func createHatch(style: HatchStyle, color: Color)->Brush
    {
        var result: retval
        result.color  = color
        result.type   = BrushType.Hatch
        result.hatch  = style
        result.uvMode = .Tile
        return result
    }

    // Creates a two-stop linear gradient between path-space points.
    func createLinearGradient(start, end: Math.Vector2, color0, color1: Color, spread: GradientSpread = .Clamp)->Brush
    {
        var result: retval
        result.color          = Color.fromArgb(Argb.White)
        result.type           = .LinearGradient
        result.gradientStart  = start
        result.gradientEnd    = end
        result.gradientSpread = spread
        result.addGradientStop(0, color0)
        result.addGradientStop(1, color1)
        return result
    }

    // Creates a two-stop linear gradient from path-space coordinates.
    func createLinearGradient(x0, y0, x1, y1: f32, color0, color1: Color, spread: GradientSpread = .Clamp)->Brush
    {
        return createLinearGradient(Math.Vector2{x0, y0}, Math.Vector2{x1, y1}, color0, color1, spread)
    }

    // Creates a two-stop radial gradient from radius zero to `radius`.
    func createRadialGradient(center: Math.Vector2, radius: f32, color0, color1: Color, spread: GradientSpread = .Clamp)->Brush
    {
        var result: retval
        result.color           = Color.fromArgb(Argb.White)
        result.type            = .RadialGradient
        result.gradientStart   = center
        result.gradientEnd     = center
        result.gradientRadius0 = 0
        result.gradientRadius1 = radius
        result.gradientSpread  = spread
        result.addGradientStop(0, color0)
        result.addGradientStop(1, color1)
        return result
    }

    // Creates a two-stop radial gradient from center coordinates.
    func createRadialGradient(centerX, centerY, radius: f32, color0, color1: Color, spread: GradientSpread = .Clamp)->Brush
    {
        return createRadialGradient(Math.Vector2{centerX, centerY}, radius, color0, color1, spread)
    }

    // Creates a two-stop angular gradient over the specified angle interval.
    func createSweepGradient(center: Math.Vector2, startAngle, endAngle: Math.Angle, color0, color1: Color, spread: GradientSpread = .Repeat)->Brush
    {
        var result: retval
        result.color          = Color.fromArgb(Argb.White)
        result.type           = .SweepGradient
        result.gradientStart  = center
        result.gradientEnd    = center
        result.gradientAngle0 = startAngle.radians
        result.gradientAngle1 = endAngle.radians
        result.gradientSpread = spread
        result.addGradientStop(0, color0)
        result.addGradientStop(1, color1)
        return result
    }

    // Creates a two-stop sweep gradient covering one full turn.
    func createSweepGradient(center: Math.Vector2, color0, color1: Color, spread: GradientSpread = .Repeat)->Brush
    {
        return createSweepGradient(center, 0.0'deg, 360.0'deg, color0, color1, spread)
    }

    // Creates a two-stop full-turn sweep gradient from center coordinates.
    func createSweepGradient(centerX, centerY: f32, color0, color1: Color, spread: GradientSpread = .Repeat)->Brush
    {
        return createSweepGradient(Math.Vector2{centerX, centerY}, color0, color1, spread)
    }
}
