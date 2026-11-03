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

#test
{
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
