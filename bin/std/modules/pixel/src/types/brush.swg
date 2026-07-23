#global public

using Core

enum BrushType
{
    SolidColor
    Texture
    Hatch
    LinearGradient
    RadialGradient
    SweepGradient
}

enum GradientSpread
{
    Clamp
    Repeat
    Mirror
}

const MaxGradientStops = 8

struct GradientStop
{
    offset: f32
    color:  Color
}

struct Brush
{
    color:   Color = Color.fromArgb(Argb.White)
    type:    BrushType = SolidColor
    hatch:   HatchStyle = Dot
    texture: Texture
    uvMode:  UVMode = Fill
    uvRect:  Math.Rectangle

    gradientStart:     Math.Vector2
    gradientEnd:       Math.Vector2
    gradientRadius0:   f32
    gradientRadius1:   f32
    gradientAngle0:    f32
    gradientAngle1:    f32
    gradientSpread:    GradientSpread = Clamp
    gradientStops:     [MaxGradientStops] GradientStop
    gradientStopCount: u8
}

impl Brush
{
    mtd const hasVisibleAlpha()->bool
    {
        #[Swag.Complete]
        switch .type
        {
        case SolidColor, Texture, Hatch:
            return .color.a != 0
        case LinearGradient, RadialGradient, SweepGradient:
            if .color.a == 0 do
                return false

            for i in .gradientStopCount
            {
                if .gradientStops[i].color.a do
                    return true
            }

            return false
        }
    }

    mtd const isOpaque()->bool
    {
        #[Swag.Complete]
        switch .type
        {
        case SolidColor, Hatch:
            return .color.a == 255
        case Texture:
            return .color.a == 255 and !.texture.pf.hasAlpha()
        case LinearGradient, RadialGradient, SweepGradient:
            if .color.a != 255 do
                return false

            for i in .gradientStopCount
            {
                if .gradientStops[i].color.a != 255 do
                    return false
            }

            return true
        }
    }

    mtd addGradientStop(offset: f32, color: Color)
    {
        Debug.assert(.gradientStopCount < MaxGradientStops, "too many gradient stops")

        let clamped = Math.saturate(offset)
        var insertAt: u8 = .gradientStopCount
        for i in .gradientStopCount
        {
            if clamped < .gradientStops[i].offset
            {
                insertAt = i
                break
            }
        }

        var i = .gradientStopCount
        while i > insertAt
        {
            .gradientStops[i] = .gradientStops[i - 1]
            i                 -= 1
        }

        .gradientStops[insertAt] = {clamped, color}
        .gradientStopCount       += 1
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
    mtd setOpacityf(alpha: f32)
    {
        .color = .color.withAlphaf(alpha)
    }

    // Multiply the current paint opacity while preserving the current tint.
    mtd multiplyOpacity(alpha: f32)
    {
        let factor = Math.saturate(alpha)
        .color = .color.withAlphaf((cast(f32) .color.a / 255.0) * factor)
    }

    // Returns a solid color brush
    func createSolid(color: Color)->Brush
    {
        var result: retval
        result.color = color
        result.type  = .SolidColor
        return result
    }

    // Returns a full texture brush
    func createTexture(texture: Texture)->Brush
    {
        var result: retval
        result.color   = Color.fromArgb(Argb.White)
        result.type    = BrushType.Texture
        result.texture = texture
        result.uvMode  = .Fill
        return result
    }

    // Returns a tiled texture brush
    func createTiled(texture: Texture)->Brush
    {
        var result: retval
        result.color   = Color.fromArgb(Argb.White)
        result.type    = BrushType.Texture
        result.texture = texture
        result.uvMode  = .Tile
        return result
    }

    // Returns a hatch brush
    func createHatch(style: HatchStyle, color: Color)->Brush
    {
        var result: retval
        result.color  = color
        result.type   = BrushType.Hatch
        result.hatch  = style
        result.uvMode = .Tile
        return result
    }

    // Returns a linear gradient brush
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

    // Returns a linear gradient brush
    func createLinearGradient(x0, y0, x1, y1: f32, color0, color1: Color, spread: GradientSpread = .Clamp)->Brush
    {
        return createLinearGradient(Math.Vector2{x0, y0}, Math.Vector2{x1, y1}, color0, color1, spread)
    }

    // Returns a radial gradient brush
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

    // Returns a radial gradient brush
    func createRadialGradient(centerX, centerY, radius: f32, color0, color1: Color, spread: GradientSpread = .Clamp)->Brush
    {
        return createRadialGradient(Math.Vector2{centerX, centerY}, radius, color0, color1, spread)
    }

    // Returns a sweep gradient brush
    func createSweepGradient(center: Math.Vector2, startAngle, endAngle: Math.Angle, color0, color1: Color, spread: GradientSpread = .Repeat)->Brush
    {
        var result: retval
        result.color          = Color.fromArgb(Argb.White)
        result.type           = .SweepGradient
        result.gradientStart  = center
        result.gradientEnd    = center
        result.gradientAngle0 = startAngle.rad
        result.gradientAngle1 = endAngle.rad
        result.gradientSpread = spread
        result.addGradientStop(0, color0)
        result.addGradientStop(1, color1)
        return result
    }

    // Returns a full-turn sweep gradient brush
    func createSweepGradient(center: Math.Vector2, color0, color1: Color, spread: GradientSpread = .Repeat)->Brush
    {
        return createSweepGradient(center, 0.0'deg, 360.0'deg, color0, color1, spread)
    }

    // Returns a full-turn sweep gradient brush
    func createSweepGradient(centerX, centerY: f32, color0, color1: Color, spread: GradientSpread = .Repeat)->Brush
    {
        return createSweepGradient(Math.Vector2{centerX, centerY}, color0, color1, spread)
    }
}
