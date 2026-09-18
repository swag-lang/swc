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
// var brush = Brush.createLinearGradient({0, 0}, {160, 0}, Color.fromArgb(Argb.DodgerBlue), Color.fromArgb(Argb.DeepPink))
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

        // Path-space rectangle the paint source covers, when the brush states one.
        //
        // Set it with [[Pixel.Brush.mapOver]]. Without it a texture, hatch, or gradient covers the
        // bounds of the shape being painted, so the same brush lands differently on two shapes.
        paintRect:    Math.Rectangle
        hasPaintRect: bool     // Whether [[Pixel.Brush.paintRect]] replaces the painted shape's bounds; false by default.

        gradientStart:   Math.Vector2               // Linear start point or radial/sweep center.
        gradientEnd:     Math.Vector2               // Linear end point; unused by radial and sweep sampling.
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
            return .color.a == 255 and not .texture.pixelFormat.hasAlpha()

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

    // Anchors the paint source over a path-space rectangle instead of the painted shape.
    //
    // Two shapes filled with the same anchored brush sample one continuous image, which is what
    // masking a group of marks through a single coverage image requires; the mask must not
    // stretch to whatever shape happens to be sampling it.
    mtd mapOver(rect: Math.Rectangle)
    {
        .paintRect    = rect
        .hasPaintRect = true
    }

    // Sets the tint, the color that multiplies what textures, hatches, and gradients paint.
    mtd setTint(color: Color)
    {
        .color = color
    }

    // Multiplies the tint by `color`, component by component.
    mtd multiplyTint(color: Color)
    {
        .color = Color.multiply(.color, color)
    }

    // Replaces the alpha of the tint, keeping its color components.
    mtd setOpacity(alpha: u8)
    {
        .color = .color.withAlpha(alpha)
    }

    // Replaces the alpha of the tint with a normalized value, clamped to [0, 1].
    mtd setOpacityF32(alpha: f32)
    {
        .color = .color.withAlphaF32(alpha)
    }

    // Multiplies the alpha of the tint by `alpha`, clamped to [0, 1].
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
        result.type    = .Texture
        result.texture = texture
        result.uvMode  = .Fill
        return result
    }

    // Creates an untinted brush that repeats the texture.
    func createTiled(texture: Texture)->Brush
    {
        var result: retval
        result.color   = Color.fromArgb(Argb.White)
        result.type    = .Texture
        result.texture = texture
        result.uvMode  = .Tile
        return result
    }

    // Creates a repeating built-in hatch with the specified color.
    func createHatch(style: HatchStyle, color: Color)->Brush
    {
        var result: retval
        result.color  = color
        result.type   = .Hatch
        result.hatch  = style
        result.uvMode = .Tile
        return result
    }

    // Creates a two-stop linear gradient between path-space points.
    func createLinearGradient(start, end: Math.Vector2, color0, color1: Color, spread: GradientSpread = .Clamp)->Brush
    {
        with var result: retval
        {
            .color          = Color.fromArgb(Argb.White)
            .type           = .LinearGradient
            .gradientStart  = start
            .gradientEnd    = end
            .gradientSpread = spread
            .addGradientStop(0, color0)
            .addGradientStop(1, color1)
        }

        return result
    }

    // Creates a two-stop linear gradient from path-space coordinates.
    func createLinearGradient(x0, y0, x1, y1: f32, color0, color1: Color, spread: GradientSpread = .Clamp)->Brush => createLinearGradient(Math.Vector2{x0, y0}, Math.Vector2{x1, y1}, color0, color1, spread)

    // Creates a two-stop radial gradient from radius zero to `radius`.
    func createRadialGradient(center: Math.Vector2, radius: f32, color0, color1: Color, spread: GradientSpread = .Clamp)->Brush
    {
        with var result: retval
        {
            .color           = Color.fromArgb(Argb.White)
            .type            = .RadialGradient
            .gradientStart   = center
            .gradientEnd     = center
            .gradientRadius0 = 0
            .gradientRadius1 = radius
            .gradientSpread  = spread
            .addGradientStop(0, color0)
            .addGradientStop(1, color1)
        }

        return result
    }

    // Creates a two-stop radial gradient from center coordinates.
    func createRadialGradient(centerX, centerY, radius: f32, color0, color1: Color, spread: GradientSpread = .Clamp)->Brush => createRadialGradient(Math.Vector2{centerX, centerY}, radius, color0, color1, spread)

    // Creates a two-stop angular gradient over the specified angle interval.
    func createSweepGradient(center: Math.Vector2, startAngle, endAngle: Math.Angle, color0, color1: Color, spread: GradientSpread = .Repeat)->Brush
    {
        with var result: retval
        {
            .color          = Color.fromArgb(Argb.White)
            .type           = .SweepGradient
            .gradientStart  = center
            .gradientEnd    = center
            .gradientAngle0 = startAngle.radians
            .gradientAngle1 = endAngle.radians
            .gradientSpread = spread
            .addGradientStop(0, color0)
            .addGradientStop(1, color1)
        }

        return result
    }

    // Creates a two-stop sweep gradient covering one full turn.
    func createSweepGradient(center: Math.Vector2, color0, color1: Color, spread: GradientSpread = .Repeat)->Brush => createSweepGradient(center, 0.0'deg, 360.0'deg, color0, color1, spread)

    // Creates a two-stop full-turn sweep gradient from center coordinates.
    func createSweepGradient(centerX, centerY: f32, color0, color1: Color, spread: GradientSpread = .Repeat)->Brush => createSweepGradient(Math.Vector2{centerX, centerY}, color0, color1, spread)
}
