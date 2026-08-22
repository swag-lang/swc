#global internal

using Core, Pixel

// One parsed CSS color.
//
// `matched` separates "this text is not a color" from "this text is `transparent`", which are
// different answers: the first leaves the cascade alone and the second sets a fully transparent
// paint.
#[Swag.NoDoc]
public struct HtmlColorValue
{
    color:   Color
    matched: bool
    current: bool
}

// Maps a CSS named color to its opaque ARGB value.
//
// `matched` is false for a name outside the list, which keeps `htmlParseColor` from turning a
// keyword such as `inherit` into black.
private func htmlNamedColor(name: string)->{ argb: u32, matched: bool }
{
    var result: retval
    result.matched = true
    switch name
    {
    case "aliceblue":                        result.argb = 0xFFF0F8FF
    case "antiquewhite":                     result.argb = 0xFFFAEBD7
    case "aqua":                             result.argb = 0xFF00FFFF
    case "aquamarine":                       result.argb = 0xFF7FFFD4
    case "azure":                            result.argb = 0xFFF0FFFF
    case "beige":                            result.argb = 0xFFF5F5DC
    case "bisque":                           result.argb = 0xFFFFE4C4
    case "black":                            result.argb = 0xFF000000
    case "blanchedalmond":                   result.argb = 0xFFFFEBCD
    case "blue":                             result.argb = 0xFF0000FF
    case "blueviolet":                       result.argb = 0xFF8A2BE2
    case "brown":                            result.argb = 0xFFA52A2A
    case "burlywood":                        result.argb = 0xFFDEB887
    case "cadetblue":                        result.argb = 0xFF5F9EA0
    case "chartreuse":                       result.argb = 0xFF7FFF00
    case "chocolate":                        result.argb = 0xFFD2691E
    case "coral":                            result.argb = 0xFFFF7F50
    case "cornflowerblue":                   result.argb = 0xFF6495ED
    case "cornsilk":                         result.argb = 0xFFFFF8DC
    case "crimson":                          result.argb = 0xFFDC143C
    case "cyan":                             result.argb = 0xFF00FFFF
    case "darkblue":                         result.argb = 0xFF00008B
    case "darkcyan":                         result.argb = 0xFF008B8B
    case "darkgoldenrod":                    result.argb = 0xFFB8860B
    case "darkgray", "darkgrey":             result.argb = 0xFFA9A9A9
    case "darkgreen":                        result.argb = 0xFF006400
    case "darkkhaki":                        result.argb = 0xFFBDB76B
    case "darkmagenta":                      result.argb = 0xFF8B008B
    case "darkolivegreen":                   result.argb = 0xFF556B2F
    case "darkorange":                       result.argb = 0xFFFF8C00
    case "darkorchid":                       result.argb = 0xFF9932CC
    case "darkred":                          result.argb = 0xFF8B0000
    case "darksalmon":                       result.argb = 0xFFE9967A
    case "darkseagreen":                     result.argb = 0xFF8FBC8F
    case "darkslateblue":                    result.argb = 0xFF483D8B
    case "darkslategray", "darkslategrey":   result.argb = 0xFF2F4F4F
    case "darkturquoise":                    result.argb = 0xFF00CED1
    case "darkviolet":                       result.argb = 0xFF9400D3
    case "deeppink":                         result.argb = 0xFFFF1493
    case "deepskyblue":                      result.argb = 0xFF00BFFF
    case "dimgray", "dimgrey":               result.argb = 0xFF696969
    case "dodgerblue":                       result.argb = 0xFF1E90FF
    case "firebrick":                        result.argb = 0xFFB22222
    case "floralwhite":                      result.argb = 0xFFFFFAF0
    case "forestgreen":                      result.argb = 0xFF228B22
    case "fuchsia":                          result.argb = 0xFFFF00FF
    case "gainsboro":                        result.argb = 0xFFDCDCDC
    case "ghostwhite":                       result.argb = 0xFFF8F8FF
    case "gold":                             result.argb = 0xFFFFD700
    case "goldenrod":                        result.argb = 0xFFDAA520
    case "gray", "grey":                     result.argb = 0xFF808080
    case "green":                            result.argb = 0xFF008000
    case "greenyellow":                      result.argb = 0xFFADFF2F
    case "honeydew":                         result.argb = 0xFFF0FFF0
    case "hotpink":                          result.argb = 0xFFFF69B4
    case "indianred":                        result.argb = 0xFFCD5C5C
    case "indigo":                           result.argb = 0xFF4B0082
    case "ivory":                            result.argb = 0xFFFFFFF0
    case "khaki":                            result.argb = 0xFFF0E68C
    case "lavender":                         result.argb = 0xFFE6E6FA
    case "lavenderblush":                    result.argb = 0xFFFFF0F5
    case "lawngreen":                        result.argb = 0xFF7CFC00
    case "lemonchiffon":                     result.argb = 0xFFFFFACD
    case "lightblue":                        result.argb = 0xFFADD8E6
    case "lightcoral":                       result.argb = 0xFFF08080
    case "lightcyan":                        result.argb = 0xFFE0FFFF
    case "lightgoldenrodyellow":             result.argb = 0xFFFAFAD2
    case "lightgray", "lightgrey":           result.argb = 0xFFD3D3D3
    case "lightgreen":                       result.argb = 0xFF90EE90
    case "lightpink":                        result.argb = 0xFFFFB6C1
    case "lightsalmon":                      result.argb = 0xFFFFA07A
    case "lightseagreen":                    result.argb = 0xFF20B2AA
    case "lightskyblue":                     result.argb = 0xFF87CEFA
    case "lightslategray", "lightslategrey": result.argb = 0xFF778899
    case "lightsteelblue":                   result.argb = 0xFFB0C4DE
    case "lightyellow":                      result.argb = 0xFFFFFFE0
    case "lime":                             result.argb = 0xFF00FF00
    case "limegreen":                        result.argb = 0xFF32CD32
    case "linen":                            result.argb = 0xFFFAF0E6
    case "magenta":                          result.argb = 0xFFFF00FF
    case "maroon":                           result.argb = 0xFF800000
    case "mediumaquamarine":                 result.argb = 0xFF66CDAA
    case "mediumblue":                       result.argb = 0xFF0000CD
    case "mediumorchid":                     result.argb = 0xFFBA55D3
    case "mediumpurple":                     result.argb = 0xFF9370DB
    case "mediumseagreen":                   result.argb = 0xFF3CB371
    case "mediumslateblue":                  result.argb = 0xFF7B68EE
    case "mediumspringgreen":                result.argb = 0xFF00FA9A
    case "mediumturquoise":                  result.argb = 0xFF48D1CC
    case "mediumvioletred":                  result.argb = 0xFFC71585
    case "midnightblue":                     result.argb = 0xFF191970
    case "mintcream":                        result.argb = 0xFFF5FFFA
    case "mistyrose":                        result.argb = 0xFFFFE4E1
    case "moccasin":                         result.argb = 0xFFFFE4B5
    case "navajowhite":                      result.argb = 0xFFFFDEAD
    case "navy":                             result.argb = 0xFF000080
    case "oldlace":                          result.argb = 0xFFFDF5E6
    case "olive":                            result.argb = 0xFF808000
    case "olivedrab":                        result.argb = 0xFF6B8E23
    case "orange":                           result.argb = 0xFFFFA500
    case "orangered":                        result.argb = 0xFFFF4500
    case "orchid":                           result.argb = 0xFFDA70D6
    case "palegoldenrod":                    result.argb = 0xFFEEE8AA
    case "palegreen":                        result.argb = 0xFF98FB98
    case "paleturquoise":                    result.argb = 0xFFAFEEEE
    case "palevioletred":                    result.argb = 0xFFDB7093
    case "papayawhip":                       result.argb = 0xFFFFEFD5
    case "peachpuff":                        result.argb = 0xFFFFDAB9
    case "peru":                             result.argb = 0xFFCD853F
    case "pink":                             result.argb = 0xFFFFC0CB
    case "plum":                             result.argb = 0xFFDDA0DD
    case "powderblue":                       result.argb = 0xFFB0E0E6
    case "purple":                           result.argb = 0xFF800080
    case "rebeccapurple":                    result.argb = 0xFF663399
    case "red":                              result.argb = 0xFFFF0000
    case "rosybrown":                        result.argb = 0xFFBC8F8F
    case "royalblue":                        result.argb = 0xFF4169E1
    case "saddlebrown":                      result.argb = 0xFF8B4513
    case "salmon":                           result.argb = 0xFFFA8072
    case "sandybrown":                       result.argb = 0xFFF4A460
    case "seagreen":                         result.argb = 0xFF2E8B57
    case "seashell":                         result.argb = 0xFFFFF5EE
    case "sienna":                           result.argb = 0xFFA0522D
    case "silver":                           result.argb = 0xFFC0C0C0
    case "skyblue":                          result.argb = 0xFF87CEEB
    case "slateblue":                        result.argb = 0xFF6A5ACD
    case "slategray", "slategrey":           result.argb = 0xFF708090
    case "snow":                             result.argb = 0xFFFFFAFA
    case "springgreen":                      result.argb = 0xFF00FF7F
    case "steelblue":                        result.argb = 0xFF4682B4
    case "tan":                              result.argb = 0xFFD2B48C
    case "teal":                             result.argb = 0xFF008080
    case "thistle":                          result.argb = 0xFFD8BFD8
    case "tomato":                           result.argb = 0xFFFF6347
    case "turquoise":                        result.argb = 0xFF40E0D0
    case "violet":                           result.argb = 0xFFEE82EE
    case "wheat":                            result.argb = 0xFFF5DEB3
    case "white":                            result.argb = 0xFFFFFFFF
    case "whitesmoke":                       result.argb = 0xFFF5F5F5
    case "yellow":                           result.argb = 0xFFFFFF00
    case "yellowgreen":                      result.argb = 0xFF9ACD32
    default:                                 result.matched = false
    }

    return result
}

// Reads one `rgb()` or `hsl()` component, which is a number, a percentage, or `none`.
private func htmlColorComponent(text: string, scale: f32)->f32
{
    let trimmed = Latin1.trim(text)
    let number  = htmlParseNumber(trimmed)
    if !number.eat do
        return 0
    if Latin1.trim(trimmed[number.eat to ]) == "%" do
        return number.value * scale / 100
    return number.value
}

// Reads the alpha component, which is a number in 0..1 or a percentage.
private func htmlColorAlpha(text: string)->f32
{
    let trimmed = Latin1.trim(text)
    let number  = htmlParseNumber(trimmed)
    if !number.eat do
        return 1
    if Latin1.trim(trimmed[number.eat to ]) == "%" do
        return Math.clamp(number.value / 100, 0, 1)
    return Math.clamp(number.value, 0, 1)
}

// Converts CSS `hsl()` components, whose hue is in degrees and whose other components are
// percentages, to the unit range [[Pixel.Color.fromHsl]] expects.
private func htmlColorFromHsl(hue, saturation, lightness, alpha: f32)->Color
{
    var turns = hue / 360
    turns -= Math.floor(turns)

    var result = Color.fromHsl(turns, Math.clamp(saturation / 100, 0, 1), Math.clamp(lightness / 100, 0, 1))
    result.a = cast(u8) Math.round(Math.clamp(alpha, 0, 1) * 255)
    return result
}

// Reads a hue component, converting the CSS angle units to degrees. A bare number is degrees.
private func htmlColorHue(text: string)->f32
{
    let trimmed = Latin1.trim(text)
    let number  = htmlParseNumber(trimmed)
    if !number.eat do
        return 0

    switch Latin1.trim(trimmed[number.eat to])
    {
    case "turn": return number.value * 360
    case "rad":  return number.value * 180 / Math.ConstF32.Pi
    case "grad": return number.value * 0.9
    }

    return number.value
}

// Encodes one linear-light component to the sRGB transfer curve, clamped into gamut.
private func htmlLinearToSrgb(value: f32)->u8
{
    let linear  = Math.clamp(value, 0, 1)
    let encoded = linear <= 0.0031308 ? linear * 12.92 : 1.055 * Math.pow(linear, 1.0 / 2.4) - 0.055
    return cast(u8) Math.round(Math.clamp(encoded, 0, 1) * 255)
}

private func htmlColorFromLinearRgb(red, green, blue, alpha: f32)->Color
{
    return Color.fromArgb(cast(u8) Math.round(Math.clamp(alpha, 0, 1) * 255), htmlLinearToSrgb(red), htmlLinearToSrgb(green), htmlLinearToSrgb(blue))
}

// Converts OKLab coordinates to sRGB, out-of-gamut components clamping to the gamut edge.
private func htmlColorFromOklab(lightness, aAxis, bAxis, alpha: f32)->Color
{
    let l = lightness + 0.3963377774 * aAxis + 0.2158037573 * bAxis
    let m = lightness - 0.1055613458 * aAxis - 0.0638541728 * bAxis
    let s = lightness - 0.0894841775 * aAxis - 1.2914855480 * bAxis

    let l3 = l * l * l
    let m3 = m * m * m
    let s3 = s * s * s

    let red   = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
    let green = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
    let blue  = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
    return htmlColorFromLinearRgb(red, green, blue, alpha)
}

// Converts CIE Lab coordinates, whose CSS white point is D50, to sRGB.
private func htmlColorFromLab(lightness, aAxis, bAxis, alpha: f32)->Color
{
    const Epsilon = 216.0 / 24389.0
    const Kappa   = 24389.0 / 27.0

    let fy = (lightness + 16) / 116
    let fx = fy + aAxis / 500
    let fz = fy - bAxis / 200

    let fx3 = fx * fx * fx
    let fz3 = fz * fz * fz
    let xr  = fx3 > Epsilon ? fx3 : (116 * fx - 16) / Kappa
    let yr  = lightness > Kappa * Epsilon ? Math.pow((lightness + 16) / 116, 3) : lightness / Kappa
    let zr  = fz3 > Epsilon ? fz3 : (116 * fz - 16) / Kappa

    // D50 reference white, then the D50-adapted XYZ-to-sRGB matrix.
    let x = xr * 0.96422
    let y = yr
    let z = zr * 0.82521

    let red   = 3.1338561 * x - 1.6168667 * y - 0.4906146 * z
    let green = -0.9787684 * x + 1.9161415 * y + 0.0334540 * z
    let blue  = 0.0719453 * x - 0.2289914 * y + 1.4052427 * z
    return htmlColorFromLinearRgb(red, green, blue, alpha)
}

// Converts `hwb()`, which tints and shades the pure hue with whiteness and blackness.
private func htmlColorFromHwb(hue, whiteness, blackness, alpha: f32)->Color
{
    var white = Math.clamp(whiteness / 100, 0, 1)
    var black = Math.clamp(blackness / 100, 0, 1)
    if white + black >= 1
    {
        let gray = cast(u8) Math.round(white / (white + black) * 255)
        return Color.fromArgb(cast(u8) Math.round(Math.clamp(alpha, 0, 1) * 255), gray, gray, gray)
    }

    let pure  = htmlColorFromHsl(hue, 100, 50, 1)
    let scale = 1 - white - black
    let red   = cast(u8) Math.round((cast(f32) pure.r / 255 * scale + white) * 255)
    let green = cast(u8) Math.round((cast(f32) pure.g / 255 * scale + white) * 255)
    let blue  = cast(u8) Math.round((cast(f32) pure.b / 255 * scale + white) * 255)
    return Color.fromArgb(cast(u8) Math.round(Math.clamp(alpha, 0, 1) * 255), red, green, blue)
}

// Converts the `color()` function's supported spaces. Display-P3 goes through its linear
// matrix to sRGB, so a P3 color keeps its hue and clamps only what the narrower gamut loses.
private func htmlColorFromColorSpace(space: string, c1, c2, c3, alpha: f32)->{ color: Color, matched: bool }
{
    var result: retval
    result.matched = true
    switch space
    {
    case "srgb":
        result.color = Color.fromArgb(cast(u8) Math.round(Math.clamp(alpha, 0, 1) * 255), cast(u8) Math.round(Math.clamp(c1, 0, 1) * 255), cast(u8) Math.round(Math.clamp(c2, 0, 1) * 255), cast(u8) Math.round(Math.clamp(c3, 0, 1) * 255))

    case "srgb-linear":
        result.color = htmlColorFromLinearRgb(c1, c2, c3, alpha)

    case "display-p3":
        let r     = Math.clamp(c1, 0, 1)
        let g     = Math.clamp(c2, 0, 1)
        let b     = Math.clamp(c3, 0, 1)
        let lr    = r <= 0.04045 ? r / 12.92 : Math.pow((r + 0.055) / 1.055, 2.4)
        let lg    = g <= 0.04045 ? g / 12.92 : Math.pow((g + 0.055) / 1.055, 2.4)
        let lb    = b <= 0.04045 ? b / 12.92 : Math.pow((b + 0.055) / 1.055, 2.4)
        let red   = 1.2249401763 * lr - 0.2249401763 * lg
        let green = -0.0420569547 * lr + 1.0420569547 * lg
        let blue  = -0.0196375546 * lr - 0.0786360456 * lg + 1.0982735901 * lb
        result.color = htmlColorFromLinearRgb(red, green, blue, alpha)

    default:
        result.matched = false
    }

    return result
}

private func htmlHexDigit(character: u8)->{ value: u32, matched: bool }
{
    var result: retval
    result.matched = true
    switch
    {
    case character >= '0' and character <= '9': result.value = cast(u32) (character - '0')
    case character >= 'a' and character <= 'f': result.value = cast(u32) (character - 'a') + 10
    case character >= 'A' and character <= 'F': result.value = cast(u32) (character - 'A') + 10
    default: result.matched = false
    }

    return result
}

// Parses a hexadecimal color in its three, four, six, and eight digit forms.
private func htmlParseHexColor(text: string)->HtmlColorValue
{
    var result: retval
    var digits: [8] u32 = undefined
    let count           = @countof(text)
    if count != 3 and count != 4 and count != 6 and count != 8 do
        return result

    for index in count
    {
        let digit = htmlHexDigit(text[index])
        if !digit.matched do
            return result
        digits[index] = digit.value
    }

    var r, g, b: u32
    var a = 255'u32
    if count <= 4
    {
        r = digits[0] * 17
        g = digits[1] * 17
        b = digits[2] * 17
        if count == 4 do
            a = digits[3] * 17
    }
    else
    {
        r = digits[0] * 16 + digits[1]
        g = digits[2] * 16 + digits[3]
        b = digits[4] * 16 + digits[5]
        if count == 8 do
            a = digits[6] * 16 + digits[7]
    }

    result.color   = Color.fromArgb(cast(u8) a, cast(u8) r, cast(u8) g, cast(u8) b)
    result.matched = true
    return result
}

// Splits the components of a color function, accepting both the legacy comma grammar and the
// modern one, where components are separated by spaces and the alpha follows a slash.
private func htmlColorFunctionParts(value: string, name, alternate: string)->{ parts: Array'String, matched: bool }
{
    var call = htmlFunctionArguments(value, name)
    if !call.matched do
        call = htmlFunctionArguments(value, alternate)

    var result: retval
    if !call.matched do
        return result

    result.matched = true
    var flat: String
    for &argument in call.arguments
    {
        if !flat.isEmpty() do
            flat += " "
        for character in argument.toString()
        {
            if character == '/' do
                flat += " "
            else do
                flat.append(character)
        }
    }

    result.parts = htmlSplitValue(flat.toString())
    return result
}

private func htmlColorMixStop(value: string)->{ color: Color, weight: f32 = -1, matched: bool }
{
    var result: retval
    let parts = htmlSplitValue(value)
    if parts.isEmpty() do
        return result

    let color = htmlParseColor(parts[0].toString())
    if !color.matched or color.current do
        return result
    result.color   = color.color
    result.matched = true

    if parts.count < 2 do
        return result
    let percent = parts[1].toString()
    if !Utf8.endsWith(percent, "%") do
        return result
    let number = htmlParseNumber(percent[0 until @countof(percent) - 1])
    if number.eat do
        result.weight = Math.max(number.value / 100, 0)
    return result
}

// Mixes two sRGB colors through premultiplied alpha. Keeping the channels premultiplied until the
// final division is what makes a color mixed with `transparent` retain its hue instead of turning
// into a dark translucent fringe.
private func htmlParseColorMix(value: string)->HtmlColorValue
{
    var result: retval
    let call = htmlFunctionArguments(value, "color-mix")
    if !call.matched or call.arguments.count != 3 or Latin1.trim(call.arguments[0].toString()) != "in srgb" do
        return result

    let first  = htmlColorMixStop(call.arguments[1].toString())
    let second = htmlColorMixStop(call.arguments[2].toString())
    if !first.matched or !second.matched do
        return result

    var firstWeight  = first.weight
    var secondWeight = second.weight
    if firstWeight < 0 and secondWeight < 0
    {
        firstWeight  = 0.5
        secondWeight = 0.5
    }
    elif firstWeight < 0 do
        firstWeight = Math.max(1 - secondWeight, 0)
    elif secondWeight < 0 do
        secondWeight = Math.max(1 - firstWeight, 0)

    let total = firstWeight + secondWeight
    if total <= 0 do
        return result
    let alphaScale = Math.min(total, 1)
    firstWeight  /= total
    secondWeight /= total

    let firstAlpha  = cast(f32) first.color.a / 255
    let secondAlpha = cast(f32) second.color.a / 255
    let alpha       = firstAlpha * firstWeight + secondAlpha * secondWeight
    var red, green, blue: f32
    if alpha > 0
    {
        red   = (cast(f32) first.color.r * firstAlpha * firstWeight + cast(f32) second.color.r * secondAlpha * secondWeight) / alpha
        green = (cast(f32) first.color.g * firstAlpha * firstWeight + cast(f32) second.color.g * secondAlpha * secondWeight) / alpha
        blue  = (cast(f32) first.color.b * firstAlpha * firstWeight + cast(f32) second.color.b * secondAlpha * secondWeight) / alpha
    }

    result.color   = Color.fromArgb(cast(u8) Math.round(alpha * alphaScale * 255), cast(u8) Math.round(red), cast(u8) Math.round(green), cast(u8) Math.round(blue))
    result.matched = true
    return result
}

// Parses any color notation a document uses.
//
// `currentColor` is reported rather than resolved, because the value it refers to is only known
// once the cascade has settled the element's own `color`.
func htmlParseColor(text: string)->HtmlColorValue
{
    var result: retval
    let trimmed = Latin1.trim(text)
    if !@countof(trimmed) do
        return result

    if trimmed[0] == '#' do
        return htmlParseHexColor(trimmed[1 to])

    let lower = String.from(trimmed).toLower()
    switch lower.toString()
    {
    case "transparent":
        result.matched = true
        return result

    case "currentcolor":
        result.matched = true
        result.current = true
        return result
    }

    let mixed = htmlParseColorMix(lower.toString())
    if mixed.matched do
        return mixed

    let rgb = htmlColorFunctionParts(lower.toString(), "rgb", "rgba")
    if rgb.matched and rgb.parts.count >= 3
    {
        let r = Math.clamp(htmlColorComponent(rgb.parts[0].toString(), 255), 0, 255)
        let g = Math.clamp(htmlColorComponent(rgb.parts[1].toString(), 255), 0, 255)
        let b = Math.clamp(htmlColorComponent(rgb.parts[2].toString(), 255), 0, 255)
        let a = rgb.parts.count >= 4 ? htmlColorAlpha(rgb.parts[3].toString()) : 1.0
        result.color   = Color.fromArgb(cast(u8) Math.round(a * 255), cast(u8) Math.round(r), cast(u8) Math.round(g), cast(u8) Math.round(b))
        result.matched = true
        return result
    }

    let hsl = htmlColorFunctionParts(lower.toString(), "hsl", "hsla")
    if hsl.matched and hsl.parts.count >= 3
    {
        let h = htmlColorHue(hsl.parts[0].toString())
        let s = htmlColorComponent(hsl.parts[1].toString(), 100)
        let l = htmlColorComponent(hsl.parts[2].toString(), 100)
        let a = hsl.parts.count >= 4 ? htmlColorAlpha(hsl.parts[3].toString()) : 1.0
        result.color   = htmlColorFromHsl(h, s, l, a)
        result.matched = true
        return result
    }

    let hwb = htmlColorFunctionParts(lower.toString(), "hwb", "hwb")
    if hwb.matched and hwb.parts.count >= 3
    {
        let h = htmlColorHue(hwb.parts[0].toString())
        let w = htmlColorComponent(hwb.parts[1].toString(), 100)
        let b = htmlColorComponent(hwb.parts[2].toString(), 100)
        let a = hwb.parts.count >= 4 ? htmlColorAlpha(hwb.parts[3].toString()) : 1.0
        result.color   = htmlColorFromHwb(h, w, b, a)
        result.matched = true
        return result
    }

    // The OK family: a percentage lightness maps to 0..1, a percentage chroma or axis to the
    // reference ranges the specification gives them.
    let oklch = htmlColorFunctionParts(lower.toString(), "oklch", "oklch")
    if oklch.matched and oklch.parts.count >= 3
    {
        let l = htmlColorComponent(oklch.parts[0].toString(), 1)
        let c = htmlColorComponent(oklch.parts[1].toString(), 0.4)
        let h = htmlColorHue(oklch.parts[2].toString()) * Math.ConstF32.Pi / 180
        let a = oklch.parts.count >= 4 ? htmlColorAlpha(oklch.parts[3].toString()) : 1.0
        result.color   = htmlColorFromOklab(l, c * Math.cos(h), c * Math.sin(h), a)
        result.matched = true
        return result
    }

    let oklab = htmlColorFunctionParts(lower.toString(), "oklab", "oklab")
    if oklab.matched and oklab.parts.count >= 3
    {
        let l     = htmlColorComponent(oklab.parts[0].toString(), 1)
        let aAxis = htmlColorComponent(oklab.parts[1].toString(), 0.4)
        let bAxis = htmlColorComponent(oklab.parts[2].toString(), 0.4)
        let a     = oklab.parts.count >= 4 ? htmlColorAlpha(oklab.parts[3].toString()) : 1.0
        result.color   = htmlColorFromOklab(l, aAxis, bAxis, a)
        result.matched = true
        return result
    }

    let lch = htmlColorFunctionParts(lower.toString(), "lch", "lch")
    if lch.matched and lch.parts.count >= 3
    {
        let l = htmlColorComponent(lch.parts[0].toString(), 100)
        let c = htmlColorComponent(lch.parts[1].toString(), 150)
        let h = htmlColorHue(lch.parts[2].toString()) * Math.ConstF32.Pi / 180
        let a = lch.parts.count >= 4 ? htmlColorAlpha(lch.parts[3].toString()) : 1.0
        result.color   = htmlColorFromLab(l, c * Math.cos(h), c * Math.sin(h), a)
        result.matched = true
        return result
    }

    let lab = htmlColorFunctionParts(lower.toString(), "lab", "lab")
    if lab.matched and lab.parts.count >= 3
    {
        let l     = htmlColorComponent(lab.parts[0].toString(), 100)
        let aAxis = htmlColorComponent(lab.parts[1].toString(), 125)
        let bAxis = htmlColorComponent(lab.parts[2].toString(), 125)
        let a     = lab.parts.count >= 4 ? htmlColorAlpha(lab.parts[3].toString()) : 1.0
        result.color   = htmlColorFromLab(l, aAxis, bAxis, a)
        result.matched = true
        return result
    }

    let spaced = htmlColorFunctionParts(lower.toString(), "color", "color")
    if spaced.matched and spaced.parts.count >= 4
    {
        let c1        = htmlColorComponent(spaced.parts[1].toString(), 1)
        let c2        = htmlColorComponent(spaced.parts[2].toString(), 1)
        let c3        = htmlColorComponent(spaced.parts[3].toString(), 1)
        let a         = spaced.parts.count >= 5 ? htmlColorAlpha(spaced.parts[4].toString()) : 1.0
        let converted = htmlColorFromColorSpace(spaced.parts[0].toString(), c1, c2, c3, a)
        if converted.matched
        {
            result.color   = converted.color
            result.matched = true
            return result
        }
    }

    let named = htmlNamedColor(lower.toString())
    if named.matched
    {
        result.color   = Color.fromArgb(named.argb)
        result.matched = true
    }

    return result
}
