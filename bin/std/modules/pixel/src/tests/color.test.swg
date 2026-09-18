#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    let red = Color.fromHsl(0, 1, 0.5)
    Swag.assert(red == Color.fromArgb(255, 255, 0, 0))

    var translucent = Color.fromArgb(73, 255, 0, 0)
    translucent.setHsl(1.0 / 3.0, 1, 0.5)
    Swag.assert(translucent == Color.fromArgb(73, 0, 255, 0))
}

#test
{
    let gray = Color.fromRgb(100, 50, 0).grayscale()
    Swag.assert(gray.a == 255)
    Swag.assert(gray.r == 59)
    Swag.assert(gray.g == gray.r and gray.b == gray.r)
}

#test
{
    let red = Color.fromRgb(255, 0, 0)
    Swag.assert(red.rotateHue(120 + 360 * 4) == Color.fromRgb(0, 255, 0))
    Swag.assert(red.rotateHue(-120 - 360 * 4) == Color.fromRgb(0, 0, 255))
}

#test
{
    Swag.assert(Color.lerp(Argb.Black, Argb.White, -1) == Argb.Black)
    Swag.assert(Color.lerp(Argb.Black, Argb.White, 2) == Argb.White)
}

// A color reads from text as a packed hexadecimal value or four decimal bytes, and a lone digit is incomplete.
#test
{
    var packed: Color
    discard expect StrConv.parseValue(&packed, Color, " 0xFF102030")
    Swag.assert(packed.argb == 0xFF102030)

    var bytes: Color
    discard expect StrConv.parseValue(&bytes, Color, " 255 16 32 48")
    Swag.assert(bytes.a == 255 and bytes.r == 16 and bytes.g == 32 and bytes.b == 48)

    var single: Color
    discard catch StrConv.parseValue(&single, Color, "0") as incomplete
    Swag.assert(incomplete != null)
}
