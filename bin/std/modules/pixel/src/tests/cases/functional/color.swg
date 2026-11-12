#global if #command == Swag.CompilerCommand.Test

using Swag, Core

private func checkColorValue(color: *Color, text: string) fail { discard try StrConv.parseValue(color, Color, text) }

// Packed ABGR uses byte significance, including during constant evaluation.
#test
{
    const Packed = Color.fromAbgr(0x12_34_56_78)
    #assert(Packed.a == 0x12 and Packed.b == 0x34 and Packed.g == 0x56 and Packed.r == 0x78)
    Swag.require(Packed.argb == 0x12_78_56_34)
}

// Values on both sides of the sRGB threshold round-trip with their alpha intact.
#test
{
    for value in [0'u8, 10, 11, 128, 255]
    {
        let original = Color.fromArgb(73, value, value, value)
        Swag.require(Color.fromLinear(original.toLinear()) == original)
    }
}

// Relative luminance uses linear-light BT.709 weights, and WCAG contrast is symmetric.
#test
{
    let black = Color.fromRgb(0, 0, 0)
    let white = Color.fromRgb(255, 255, 255)
    let red   = Color.fromRgb(255, 0, 0)
    let green = Color.fromRgb(0, 255, 0)
    let blue  = Color.fromRgb(0, 0, 255)

    Swag.require(black.relativeLuminance() == 0 and white.relativeLuminance() == 1)
    Swag.require(Math.abs(red.relativeLuminance() - 0.2126) < 0.00001)
    Swag.require(Math.abs(green.relativeLuminance() - 0.7152) < 0.00001)
    Swag.require(Math.abs(blue.relativeLuminance() - 0.0722) < 0.00001)
    Swag.require(Math.abs(black.contrastRatio(white) - 21) < 0.0001)
    Swag.require(Math.abs(white.contrastRatio(black) - 21) < 0.0001)
    Swag.require(Math.abs(red.contrastRatio(black) - 5.252) < 0.001)
}

#test
{
    // Canonical HSL wheel points stay exact after quantizing RGB to bytes.
    let yellow  = Color.fromHsl(1.0 / 6.0, 1, 0.5)
    let cyan    = Color.fromHsl(0.5, 1, 0.5)
    let blue    = Color.fromHsl(2.0 / 3.0, 1, 0.5)
    let magenta = Color.fromHsl(5.0 / 6.0, 1, 0.5)
    Swag.require(yellow == Color.fromRgb(255, 255, 0) and
                 cyan == Color.fromRgb(0, 255, 255) and
                 blue == Color.fromRgb(0, 0, 255) and
                 magenta == Color.fromRgb(255, 0, 255))

    // Intermediate hues round to their nearest byte rather than truncating float residue.
    Swag.require(Color.fromHsl(0.25, 0.5, 0.4) == Color.fromRgb(102, 153, 51))
    Swag.require(Color.fromHsl(0.123, 0.7, 0.37) == Color.fromRgb(160, 126, 28))

    let red = Color.fromHsl(0, 1, 0.5)
    Swag.require(red == Color.fromArgb(255, 255, 0, 0))

    var translucent = Color.fromArgb(73, 255, 0, 0)
    translucent.setHsl(1.0 / 3.0, 1, 0.5)
    Swag.require(translucent == Color.fromArgb(73, 0, 255, 0))
}

#test
{
    let gray = Color.fromRgb(100, 50, 0).grayscale()
    Swag.require(gray.a == 255)
    Swag.require(gray.r == 59)
    Swag.require(gray.g == gray.r and gray.b == gray.r)
}

#test
{
    let red = Color.fromRgb(255, 0, 0)
    Swag.require(red.rotateHue(120 + 360 * 4) == Color.fromRgb(0, 255, 0))
    Swag.require(red.rotateHue(-120 - 360 * 4) == Color.fromRgb(0, 0, 255))
}

#test
{
    Swag.require(Color.lerp(Argb.Black, Argb.White, -1) == Argb.Black)
    Swag.require(Color.lerp(Argb.Black, Argb.White, 2) == Argb.White)
}

// A color reads from text as a packed hexadecimal value or four decimal bytes, and a lone digit is incomplete.
#test
{
    var packed: Color
    discard expect StrConv.parseValue(&packed, Color, " 0xFF102030")
    Swag.require(packed.argb == 0xFF102030)

    var bytes: Color
    discard expect StrConv.parseValue(&bytes, Color, " 255 16 32 48")
    Swag.require(bytes.a == 255 and bytes.r == 16 and bytes.g == 32 and bytes.b == 48)

    var single: Color
    var incompleteOutcome: Swag.Error
    catch checkColorValue(&single, "0") as incompleteOutcome
    let incomplete = incompleteOutcome.value()
    Swag.require(incomplete != null)
}
