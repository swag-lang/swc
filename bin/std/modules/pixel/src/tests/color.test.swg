#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    let red = Color.fromHsl(0, 1, 0.5)
    @assert(red == Color.fromArgb(255, 255, 0, 0))

    var translucent = Color.fromArgb(73, 255, 0, 0)
    translucent.setHsl(1.0 / 3.0, 1, 0.5)
    @assert(translucent == Color.fromArgb(73, 0, 255, 0))
}

#test
{
    let gray = Color.fromRgb(100, 50, 0).grayscale()
    @assert(gray.a == 255)
    @assert(gray.r == 59)
    @assert(gray.g == gray.r and gray.b == gray.r)
}

#test
{
    let red = Color.fromRgb(255, 0, 0)
    @assert(red.rotateHue(120 + 360 * 4) == Color.fromRgb(0, 255, 0))
    @assert(red.rotateHue(-120 - 360 * 4) == Color.fromRgb(0, 0, 255))
}

#test
{
    @assert(Color.lerp(Argb.Black, Argb.White, -1) == Argb.Black)
    @assert(Color.lerp(Argb.Black, Argb.White, 2) == Argb.White)
}
