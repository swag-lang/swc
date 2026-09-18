#global public

using Swag, Core, Core.Errors, Core.StrConv

// Represents a straight-alpha color with 8-bit ARGB components.
//
// The four components overlay `argb`, which reads as the packed `0xAARRGGBB` value on every platform.
// A color converts implicitly from an [[Pixel.Argb]] name, and the factory functions build one
// from bytes, normalized floats, HSL, or a [[Core.Math.Vector4]].
#[ConstExpr, Core.Serialization.Final]
struct Color
{
    public
    {
        #static if Core.BIG_ENDIAN
        {
            a, r, g, b: u8     // Alpha, red, green, blue components (0-255)
            #[Offset("a")]
            argb: u32     // 32-bit ARGB representation
        }
        else
        {
            b, g, r, a: u8     // Blue, green, red, alpha components (0-255)
            #[Offset("b")]
            argb: u32     // 32-bit ARGB representation
        }
    }
}

impl Color
{
    // Orders colors by their packed 32-bit ARGB representation.
    #[Inline]
    mtd const opCompare(other: Color)->s32 => .argb <=> other.argb

    // Assigns a packed `0xAARRGGBB` value.
    #[FullInit, Inline, ConstExpr]
    mtd opSet(argb: u32)
    {
        .argb = argb
    }

    // Assigns a named color.
    #[FullInit, Inline, Implicit, ConstExpr]
    mtd opSet(argb: Argb)
    {
        .argb = cast(u32) argb
    }

    // Assigns the named color spelled by `name`, or black when no name matches.
    #[FullInit, Inline, ConstExpr]
    mtd opSet(name: string)
    {
        .argb = cast(u32) Argb.fromName(name)
    }

    // Returns whether the packed value equals `argb`.
    #[Inline]
    mtd const opEquals(argb: u32) => .argb == argb

    // Returns whether the color equals a named color.
    #[Inline]
    mtd const opEquals(argb: Argb) => .argb == cast(u32) argb

    // Returns whether both colors have the same four components.
    #[Inline]
    mtd const opEquals(other: Color) => .argb == other.argb

    // Returns whether alpha is 255.
    #[Inline]
    mtd const isOpaque() => .a == 255

    // Sets the four components from bytes.
    #[Inline]
    mtd setArgb(a, r, g, b: u8)
    {
        .a = a
        .r = r
        .g = g
        .b = b
    }

    // Sets the four components from normalized values, clamped to [0, 1].
    #[Inline]
    mtd setArgbF32(a, r, g, b: f32)
    {
        .a = cast() (Math.saturate(a) * 255)
        .r = cast() (Math.saturate(r) * 255)
        .g = cast() (Math.saturate(g) * 255)
        .b = cast() (Math.saturate(b) * 255)
    }

    // Sets the color components from bytes and makes the color opaque.
    #[Inline]
    mtd setRgb(r, g, b: u8)
    {
        .a = 255
        .r = r
        .g = g
        .b = b
    }

    // Copies the color components of `rgb`, keeping the current alpha.
    #[Inline]
    mtd setRgb(rgb: Color)
    {
        .r = rgb.r
        .g = rgb.g
        .b = rgb.b
    }

    // Sets the color components from normalized values, clamped to [0, 1], and makes the color opaque.
    #[Inline]
    mtd setRgbF32(r, g, b: f32)
    {
        .a = 255
        .r = cast() (Math.saturate(r) * 255)
        .g = cast() (Math.saturate(g) * 255)
        .b = cast() (Math.saturate(b) * 255)
    }

    // Returns the four components normalized to [0, 1].
    #[Inline, ConstExpr]
    mtd const toArgbF32()->{ a: f32, r: f32, g: f32, b: f32 }
    {
        var result: retval
        result.a = .a / 255.0
        result.r = .r / 255.0
        result.g = .g / 255.0
        result.b = .b / 255.0
        return result
    }

    // Returns the normalized components as a vector whose `w` is alpha and `x`, `y`, `z` are red, green, blue.
    #[Inline, ConstExpr]
    mtd const toVector4()->Math.Vector4
    {
        var result: retval
        result.w = .a / 255.0
        result.x = .r / 255.0
        result.y = .g / 255.0
        result.z = .b / 255.0
        return result
    }

    // Returns the color components normalized to [0, 1].
    #[Inline, ConstExpr]
    mtd const toRgbF32()->{ r: f32, g: f32, b: f32 }
    {
        var result: retval
        result.r = .r / 255.0
        result.g = .g / 255.0
        result.b = .b / 255.0
        return result
    }

    // Creates an opaque color from byte components.
    #[Inline, ConstExpr]
    func fromRgb(r, g, b: u8)->Color
    {
        var result: retval
        result.setRgb(r, g, b)
        return result
    }

    // Creates an opaque color from normalized components, clamped to [0, 1].
    #[Inline, ConstExpr]
    func fromRgbF32(r, g, b: f32)->Color
    {
        var result: retval
        result.setRgbF32(r, g, b)
        return result
    }

    // Creates a color from byte components, alpha first.
    #[Inline, ConstExpr]
    func fromArgb(a, r, g, b: u8)->Color
    {
        var result: retval
        result.setArgb(a, r, g, b)
        return result
    }

    // Creates a color from a named color.
    #[Inline, ConstExpr]
    func fromArgb(argb: Argb)->Color
    {
        let result: retval = argb
        return result
    }

    // Creates a named color with its alpha replaced by `alpha`.
    #[Inline, ConstExpr]
    func fromArgb(alpha: u8, argb: Argb)->Color
    {
        var result: retval = argb
        result.a = alpha
        return result
    }

    // Creates a color from a packed `0xAARRGGBB` value.
    #[Inline, ConstExpr]
    func fromArgb(argb: u32)->Color
    {
        let result: retval = argb
        return result
    }

    // Creates a color from a packed `0xAABBGGRR` value.
    #[Inline, ConstExpr]
    func fromAbgr(abgr: u32)->Color
    {
        var result: retval
        result.a = cast() (abgr >> 24)
        result.b = cast() ((abgr >> 16) & 0xFF)
        result.g = cast() ((abgr >> 8) & 0xFF)
        result.r = cast() (abgr & 0xFF)
        return result
    }

    // Creates a color from normalized components, alpha first, clamped to [0, 1].
    #[Inline, ConstExpr]
    func fromArgbF32(a, r, g, b: f32)->Color
    {
        var result: retval
        result.setArgbF32(a, r, g, b)
        return result
    }

    // Creates a color from a normalized vector whose `w` is alpha and `x`, `y`, `z` are red, green, blue.
    #[Inline, ConstExpr]
    func fromVector4(vec: Math.Vector4)->Color
    {
        var result: retval
        result.setArgbF32(vec.w, vec.x, vec.y, vec.z)
        return result
    }

    // Creates an opaque color from hue, saturation, and lightness, each clamped to [0, 1].
    #[Inline, ConstExpr]
    func fromHsl(h, s, l: f32)->Color
    {
        var result: retval
        result.a = 255
        result.setHsl(h, s, l)
        return result
    }

    // Sets the color components from hue, saturation, and lightness, each clamped to [0, 1].
    //
    // Alpha is unchanged.
    mtd setHsl(h, s, l: f32)
    {
        // Convert hue component to RGB color value.
        func hueToCol(m1, m2, hue: f32)->u8
        {
            var h = hue
            if h < 0 do
                h += 1
            if h > 1 do
                h -= 1

            var v: f32
            if 6 * h < 1 do
                v = m1 + (m2 - m1) * h * 6
            elif 2 * h < 1 do
                v = m2
            elif 3 * h < 2 do
                v = m1 + (m2 - m1) * ((2.0 / 3.0) - h) * 6
            else do
                v = m1

            return cast(u8) (v * 255)
        }

        var _h = Math.saturate(h)
        var _l = Math.saturate(l)
        var _s = Math.saturate(s)

        if _s == 0
        {
            .r = cast(u8) (255 * _l)
            .g = .r
            .b = .r
        }
        else
        {
            let m2 = _l < 0.5 ? _l * (1 + _s) : (_l + _s) - (_l * _s)
            let m1 = 2 * _l - m2
            .r = hueToCol(m1, m2, _h + (1.0 / 3.0))
            .g = hueToCol(m1, m2, _h)
            .b = hueToCol(m1, m2, _h - (1.0 / 3.0))
        }
    }

    // Returns the hue, saturation, and lightness of the color, each in [0, 1].
    mtd const toHsl()->{ h: f32, s: f32, l: f32 }
    {
        var result: retval

        let {rf, gf, bf} = .toRgbF32()
        let max = Math.max(rf, gf, bf)
        let min = Math.min(rf, gf, bf)
        result.l = (max + min) * 0.5
        let delta = max - min
        if delta == 0
        {
            result.s = 0
            result.h = 0
            return result
        }

        if result.l < 0.5 do
            result.s = delta / (max + min)
        else do
            result.s = delta / (2 - max - min)

        let delr = (((max - rf) / 6) + (delta * 0.5)) / delta
        let delg = (((max - gf) / 6) + (delta * 0.5)) / delta
        let delb = (((max - bf) / 6) + (delta * 0.5)) / delta

        if rf == max do
            result.h = delb - delg
        elif gf == max do
            result.h = (1.0 / 3.0) + delr - delb
        else do
            result.h = (2.0 / 3.0) + delg - delr

        if result.h < 0 do
            result.h += 1
        if result.h > 1 do
            result.h -= 1

        return result
    }

    // Converts the color to a linear-light [[Core.Math.Vector4]].
    //
    // Components are normalized to [0, 1], with gamma-correct sRGB → linear conversion applied.
    // Useful for rendering, lighting, and blending operations where
    // linear color space is required instead of gamma-encoded sRGB.
    #[ConstExpr]
    mtd const toLinear()->Math.Vector4
    {
        // Convert a normalized sRGB channel [0,1] to linear light.
        func srgbToLinear(c: f32)->f32 => c <= 0.04045 ? (c / 12.92) : Math.pow((c + 0.055) / 1.055, 2.4)

        var result: retval
        result.w = .a / 255.0                   // alpha channel
        result.x = srgbToLinear(.r / 255.0)     // red channel
        result.y = srgbToLinear(.g / 255.0)     // green channel
        result.z = srgbToLinear(.b / 255.0)     // blue channel
        return result
    }

    // Creates a color from a linear-light [[Core.Math.Vector4]].
    //
    // Components are expected to be normalized in [0, 1].
    // Performs gamma correction (linear → sRGB) on the RGB channels.
    // Useful for reconstructing an 8-bit Color after doing math in linear space.
    #[ConstExpr]
    func fromLinear(vec: Math.Vector4)->Color
    {
        // Convert a linear-light channel [0,1] to gamma-encoded sRGB.
        func linearToSrgb(c: f32)->f32 => c <= 0.0031308 ? (c * 12.92) : (1.055 * Math.pow(c, 1.0 / 2.4) - 0.055)

        var result: retval
        result.a = cast(u8) Math.round(Math.saturate(vec.w) * 255.0)
        result.r = cast(u8) Math.round(Math.saturate(linearToSrgb(vec.x)) * 255.0)
        result.g = cast(u8) Math.round(Math.saturate(linearToSrgb(vec.y)) * 255.0)
        result.b = cast(u8) Math.round(Math.saturate(linearToSrgb(vec.z)) * 255.0)
        return result
    }

    // Returns the relative luminance of the color in linear light, in [0, 1].
    //
    // The channels are linearized by [[Pixel.Color.toLinear]] and weighted with the BT.709
    // coefficients WCAG 2.x uses: `0.2126 * r + 0.7152 * g + 0.0722 * b`.
    mtd const relativeLuminance()->f32
    {
        let lin = .toLinear()
        return lin.x * 0.2126 + lin.y * 0.7152 + lin.z * 0.0722
    }

    // Interpolates the color components from `start` to `end`, keeping the alpha of `start`.
    //
    // `factor` is clamped to [0, 1].
    #[ConstExpr]
    func lerpRgb(start, end: Color, factor: f32)->Color
    {
        var result: retval
        let t = Math.saturate(factor)
        result.a = start.a
        result.r = cast(u8) Math.lerp(cast(f32) start.r, cast(f32) end.r, t)
        result.g = cast(u8) Math.lerp(cast(f32) start.g, cast(f32) end.g, t)
        result.b = cast(u8) Math.lerp(cast(f32) start.b, cast(f32) end.b, t)
        return result
    }

    // Interpolates all four components from `start` to `end`.
    //
    // `factor` is clamped to [0, 1].
    #[ConstExpr]
    func lerp(start, end: Color, factor: f32)->Color
    {
        var result: retval
        let t = Math.saturate(factor)
        result.a = cast(u8) Math.lerp(cast(f32) start.a, cast(f32) end.a, t)
        result.r = cast(u8) Math.lerp(cast(f32) start.r, cast(f32) end.r, t)
        result.g = cast(u8) Math.lerp(cast(f32) start.g, cast(f32) end.g, t)
        result.b = cast(u8) Math.lerp(cast(f32) start.b, cast(f32) end.b, t)
        return result
    }

    // Returns `color` blended toward black by `factor`, keeping its alpha.
    #[ConstExpr]
    func darker(color: Color, factor: f32)->Color => color.lerpRgb(Color.fromArgb(Argb.Black), factor)

    // Returns `color` blended toward white by `factor`, keeping its alpha.
    #[ConstExpr]
    func lighter(color: Color, factor: f32)->Color => color.lerpRgb(Color.fromArgb(Argb.White), factor)

    // Returns the Euclidean distance between the color components of two colors, normalized to [0, 1].
    mtd const rgbDistanceTo(other: Color)->f32
    {
        let x1   = cast(f32) .r - other.r
        let x2   = cast(f32) .g - other.g
        let x3   = cast(f32) .b - other.b
        var dist = Math.sqrt((x1 * x1) + (x2 * x2) + (x3 * x3))
        dist /= Math.sqrt(cast(f32) (255.0 * 255.0 * 3.0))     // Normalize to [0, 1]
        return dist
    }

    // Returns whether [[Pixel.Color.grayscaleValue]] is below one half.
    #[Inline]
    mtd const isDark()->bool => .grayscaleValue() < 0.5

    // Returns whether [[Pixel.Color.grayscaleValue]] is at least one half.
    #[Inline]
    mtd const isLight()->bool => .grayscaleValue() >= 0.5

    // Returns white for a dark color and black for a light one, for readable text over it.
    #[Inline, ConstExpr]
    mtd const contrasting()->Color => .isDark() ? Color.fromArgb(Argb.White) : Color.fromArgb(Argb.Black)

    // Returns the perceived brightness in [0, 1], using BT.601 luma weights on the gamma-encoded components.
    #[Inline, ConstExpr]
    mtd const grayscaleValue()->f32 => (cast(f32) .r * 0.299 + cast(f32) .g * 0.587 + cast(f32) .b * 0.114) / 255.0

    // Returns the gray of the same perceived brightness, keeping alpha.
    #[Inline, ConstExpr]
    mtd const grayscale()->Color
    {
        let gray = cast(u8) Math.round(.grayscaleValue() * 255)
        return Color.fromArgb(.a, gray, gray, gray)
    }

    // Returns the WCAG contrast ratio between this color and `against`, from 1 to 21.
    //
    // The ratio is `(l1 + 0.05) / (l2 + 0.05)`, where `l1` is the larger relative luminance.
    mtd const contrastRatio(against: Color)->f32
    {
        let l1 = Math.max(.relativeLuminance(), against.relativeLuminance())
        let l2 = Math.min(.relativeLuminance(), against.relativeLuminance())
        return (l1 + 0.05) / (l2 + 0.05)
    }

    // Returns the color with `factor` added to its HSL saturation, keeping alpha.
    //
    // -1 always gives gray, zero leaves the color unchanged, and one always gives full saturation.
    #[ConstExpr]
    mtd const adjustSaturation(factor: f32)->Color
    {
        let hsl    = .toHsl()
        let newS   = Math.clamp(hsl.s + factor, 0.0, 1.0)
        var result = Color.fromHsl(hsl.h, newS, hsl.l)
        result.a = .a     // Preserve alpha
        return result
    }

    // Returns the color with `factor` added to its HSL lightness, keeping alpha.
    //
    // -1 always gives black, zero leaves the color unchanged, and one always gives white.
    #[ConstExpr]
    mtd const adjustBrightness(factor: f32)->Color
    {
        let hsl    = .toHsl()
        let newL   = Math.clamp(hsl.l + factor, 0.0, 1.0)
        var result = Color.fromHsl(hsl.h, hsl.s, newL)
        result.a = .a     // Preserve alpha
        return result
    }

    // Lightens or darkens the color in place until it reaches a contrast ratio against `target`.
    //
    // `requiredContrast` is a WCAG contrast ratio between 1 and 21; the default 4.5 suits normal
    // text. A color that already meets it is left unchanged. Otherwise its HSL lightness moves by
    // the magnitude of `step` per iteration, in whichever direction raises the contrast more, for
    // at most `maxSteps` iterations, so the result can still fall short of the ratio.
    mtd ensureContrast(target: Color, requiredContrast: f32 = 4.5, step: f32 = 0.02, maxSteps: s32 = 64)
    {
        Swag.assert(requiredContrast >= 1 and requiredContrast <= 21)
        Swag.assert(step != 0)
        Swag.assert(maxSteps >= 0)

        let initialContrast = .contrastRatio(target)

        // If already meets the contrast requirement, return unchanged
        if initialContrast >= requiredContrast do
            return

        // Decide direction: should we go lighter or darker?
        // Try both directions and see which one increases contrast more.
        let astep             = Math.abs(step)
        let lighter           = .adjustBrightness(astep)
        let darker            = .adjustBrightness(-astep)
        let contrastIfLighter = lighter.contrastRatio(target)
        let contrastIfDarker  = darker.contrastRatio(target)

        // Direction that improves contrast more
        let direction: f32 = (contrastIfLighter > contrastIfDarker) ? astep : -astep

        var steps    = 0
        var contrast = initialContrast

        // Iterate until we reach or exceed required contrast
        while contrast < requiredContrast and steps < maxSteps
        {
            me[]     = .adjustBrightness(direction)
            contrast = .contrastRatio(target)
            steps    += 1
        }
    }

    // Returns the color with its hue rotated by `degrees` around the color wheel, keeping alpha.
    #[ConstExpr]
    mtd const rotateHue(degrees: f32)->Color
    {
        let hsl    = .toHsl()
        let newH   = Math.fract(hsl.h + (degrees / 360.0))
        var result = Color.fromHsl(newH, hsl.s, hsl.l)
        result.a = .a     // Preserve alpha
        return result
    }

    // Returns the color with its alpha replaced by `alpha`.
    #[Inline, ConstExpr]
    mtd const withAlpha(alpha: u8)->Color => fromArgb(alpha, .r, .g, .b)

    // Returns the color with its alpha replaced by a normalized value, clamped to [0, 1].
    #[Inline, ConstExpr]
    mtd const withAlphaF32(alpha: f32)->Color => fromArgb(cast(u8) (Math.clamp(alpha, 0.0, 1.0) * 255), .r, .g, .b)

    // Returns the color on the opposite side of the color wheel, keeping alpha.
    #[ConstExpr]
    mtd const complementary()->Color => .rotateHue(180.0)

    // Returns the component-wise product of two colors, each component read as a fraction of 255.
    #[ConstExpr]
    func multiply(col0, col1: Color)->Color
    {
        var result: retval
        result.a = cast(u8) ((cast(u16) col0.a * col1.a) / 255)
        result.r = cast(u8) ((cast(u16) col0.r * col1.r) / 255)
        result.g = cast(u8) ((cast(u16) col0.g * col1.g) / 255)
        result.b = cast(u8) ((cast(u16) col0.b * col1.b) / 255)
        return result
    }

    // Returns the component-wise sum of two colors, saturated at 255.
    #[ConstExpr]
    func add(col0, col1: Color)->Color
    {
        var result: retval
        result.a = cast(u8) Math.min(cast(u16) col0.a + col1.a, 255)
        result.r = cast(u8) Math.min(cast(u16) col0.r + col1.r, 255)
        result.g = cast(u8) Math.min(cast(u16) col0.g + col1.g, 255)
        result.b = cast(u8) Math.min(cast(u16) col0.b + col1.b, 255)
        return result
    }

    // Returns `n` visually distinct opaque colors.
    //
    // Hues advance from `startHue` by the golden ratio conjugate, so each color is clearly
    // separated from the others, and the lightness alternates slightly around `lum` for good
    // contrast against white text. All values are HSL components in [0, 1].
    func generateDistinctColors(n: u32, startHue: f32 = 0.113, lum: f32 = 0.44, sat: f32 = 0.68)->Array'Color
    {
        var colors: retval
        if n == 0 do
            return colors

        const G    = 0.61803398875     // Golden ratio conjugate for low-discrepancy hue sampling
        const LVAR = 0.05              // tiny alternation to separate neighbors

        for i in n
        {
            // Evenly jump around the hue circle with the golden angle
            let h = Math.fract(startHue + cast(f32) i * G)

            // Slight alternating lightness to enhance contrast between adjacent colors
            let l = lum + ((i & 1) == 0 ? -LVAR : LVAR)

            colors.add(fromHsl(h, sat, l))
        }

        return colors
    }
}

// Parses a color from text.
impl Core.StrConv.IPokeValue for Color
{
    // Parses a color and returns the unread rest of `buf`.
    //
    // Accepts a packed hexadecimal value (`0xAARRGGBB`), four decimal bytes in alpha, red, green,
    // blue order, or an [[Pixel.Argb]] name. An unknown name reads as black.
    mtd impl poke(buf: string)->string fail
    {
        var eat: u64
        var ovf: bool

        var one = Tokenize.eatSpaces(buf)
        if one.count == 0 do
            fail SyntaxError{}

        if one.count >= 2 and one[0] == '0' and one[1] | 32 == 'x'
        {
            {.argb, eat, ovf} = try parseU32(one)
            if ovf do
                fail OverflowError{}
            one = Tokenize.eatCount(one, eat)
        }
        elif Latin1.isDigit(one[0])
        {
            {.a, eat, ovf} = try parseU8(one)
            if ovf do
                fail OverflowError{}
            one = Tokenize.eatCount(one, eat)

            one = Tokenize.eatSpaces(one)
            {.r, eat, ovf} = try parseU8(one)
            if ovf do
                fail OverflowError{}
            one = Tokenize.eatCount(one, eat)

            one = Tokenize.eatSpaces(one)
            {.g, eat, ovf} = try parseU8(one)
            if ovf do
                fail OverflowError{}
            one = Tokenize.eatCount(one, eat)

            one = Tokenize.eatSpaces(one)
            {.b, eat, ovf} = try parseU8(one)
            if ovf do
                fail OverflowError{}
            one = Tokenize.eatCount(one, eat)
        }
        else
        {
            let id = (try parseIdentifier(one)) orelse ""
            one   = Tokenize.eatCount(one, id.count)
            .argb = cast(u32) Argb.fromName(id)
        }

        return one
    }
}
