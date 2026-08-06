using Core

impl Image
{
    // Turns the flat `ground` of a two-color mark into transparency, keeping the glyph.
    //
    // A product mark ships flattened — one glyph over one ground — because that is what a
    // taskbar, a file list, and an installer need. Drawn over a surface that already has a
    // ground of its own, that tile reads as a box around the glyph rather than as the mark.
    //
    // Every pixel is read as a blend of the two declared colors: how far it has travelled
    // from `ground` towards `foreground` becomes its alpha, and its color becomes
    // `foreground`. The antialiased rim of the glyph therefore survives as a soft edge
    // instead of collapsing into a staircase. A pixel that is neither — a mark that carries
    // a third color — keeps whatever share of the two it projects onto, which is the most
    // an operation with two colors to go on can honestly say.
    //
    // A format without an alpha channel has nowhere to put the result and is left as is.
    public mtd keyOutGround(ground, foreground: Color)
    {
        if .pixelFormat != .BGRA8 and .pixelFormat != .RGBA8 do
            return

        // The axis the two colors span, and the inverse of its squared length, so the
        // projection of a pixel onto it is one dot product per pixel.
        let dr   = cast(f32) foreground.r - cast(f32) ground.r
        let dg   = cast(f32) foreground.g - cast(f32) ground.g
        let db   = cast(f32) foreground.b - cast(f32) ground.b
        let len2 = dr * dr + dg * dg + db * db
        if len2 <= 0 do
            return

        let bgra          = .pixelFormat == .BGRA8
        var axis: [8] f32 = undefined
        axis[0] = cast(f32) (bgra ? ground.b : ground.r)
        axis[1] = cast(f32) ground.g
        axis[2] = cast(f32) (bgra ? ground.r : ground.b)
        axis[3] = bgra ? db : dr
        axis[4] = dg
        axis[5] = bgra ? dr : db
        axis[6] = 1.0 / len2
        axis[7] = cast(f32) (bgra ? foreground.b : foreground.r)

        var front: [3] u8 = undefined
        front[0] = bgra ? foreground.b : foreground.r
        front[1] = foreground.g
        front[2] = bgra ? foreground.r : foreground.b

        var params = {axis: axis, front: front}
        .visitPixels(&params)
        {
            let p = cast(*#decltype(params)) userData!
            let t = ((cast(f32) pix[0] - p.axis[0]) * p.axis[3] +
                     (cast(f32) pix[1] - p.axis[1]) * p.axis[4] +
                     (cast(f32) pix[2] - p.axis[2]) * p.axis[5]) * p.axis[6]

            pix[0] = p.front[0]
            pix[1] = p.front[1]
            pix[2] = p.front[2]
            pix[3] = cast(u8) (Math.saturate(t) * cast(f32) pix[3])
        }
    }
}
