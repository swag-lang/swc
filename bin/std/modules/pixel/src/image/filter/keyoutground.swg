using Core

public impl Image
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
    mtd keyOutGround(ground, foreground: Color)
    {
        if !.pixelFormat.hasAlpha() or !.pixelFormat.isPacked() do
            return

        // The axis the two colors span, and the inverse of its squared length, so the
        // projection of a pixel onto it is one dot product per pixel.
        let dr   = cast(f32) foreground.r - cast(f32) ground.r
        let dg   = cast(f32) foreground.g - cast(f32) ground.g
        let db   = cast(f32) foreground.b - cast(f32) ground.b
        let len2 = dr * dr + dg * dg + db * db
        if len2 <= 0 do
            return

        let legacy = (.pixelFormat == .BGRA8 or .pixelFormat == .RGBA8) and .alphaMode == .Straight
        if !legacy
        {
            let groundValue     = colorPixelValue(ground)
            let foregroundValue = colorPixelValue(foreground)
            var context         = {
                ground: groundValue,
                foreground: foregroundValue,
                dr: foregroundValue.r - groundValue.r,
                dg: foregroundValue.g - groundValue.g,
                db: foregroundValue.b - groundValue.b,
                inverseLength: 1.0 / ((foregroundValue.r - groundValue.r) * (foregroundValue.r - groundValue.r) +
                                      (foregroundValue.g - groundValue.g) * (foregroundValue.g - groundValue.g) +
                                      (foregroundValue.b - groundValue.b) * (foregroundValue.b - groundValue.b))}
            .transformLogicalPixels(&context)
            {
                let params = userData![as #decltype(context)]
                let amount = ((value.r - params.ground.r) * params.dr +
                              (value.g - params.ground.g) * params.dg +
                              (value.b - params.ground.b) * params.db) * params.inverseLength
                value.r = params.foreground.r
                value.g = params.foreground.g
                value.b = params.foreground.b
                value.a *= Math.saturate(amount)
            }

            return
        }

        let bgra = .pixelFormat == .BGRA8
        var axis: [8] f32
        axis[0] = cast(f32) (bgra ? ground.b : ground.r)
        axis[1] = cast(f32) ground.g
        axis[2] = cast(f32) (bgra ? ground.r : ground.b)
        axis[3] = bgra ? db : dr
        axis[4] = dg
        axis[5] = bgra ? dr : db
        axis[6] = 1.0 / len2
        axis[7] = cast(f32) (bgra ? foreground.b : foreground.r)

        var front: [3] u8
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
