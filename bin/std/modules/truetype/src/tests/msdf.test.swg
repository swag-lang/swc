#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Counts the texels whose multi-channel median falls on the other side of the glyph than
// their true signed distance does.
private func countMsdfSignMismatches(bitmap: const *Bitmap)->u32
{
    var result: u32
    let buf = bitmap.buffer!
    for i in cast(u64) bitmap.width * bitmap.rows
    {
        let p      = i * 4
        let median = Math.max(Math.min(buf[p], buf[p + 1]), Math.min(Math.max(buf[p], buf[p + 1]), buf[p + 2]))
        let alpha  = buf[p + 3]
        if (alpha > 128 and median < 128) or (alpha < 128 and median > 128) do
            result += 1
    }

    return result
}

// One texel of a rendered field.
private struct MsdfTexel
{
    median: u8
    alpha:  u8
}

// Renders a glyph made of axis-aligned squares, each wound like a TrueType outer contour, and
// returns the texel whose center is at `(x, y)` pixels.
//
// A square is `[left, bottom, right, top]` in 26.6 units.
private func renderSquares(face: *Face, squares: const [..] [4] s32, x, y: f64)->MsdfTexel
{
    var points:   Array'Vector
    var tags:     Array'u8
    var contours: Array's16
    for sq in squares
    {
        points.add(Vector{sq[0], sq[1]})
        points.add(Vector{sq[0], sq[3]})
        points.add(Vector{sq[2], sq[3]})
        points.add(Vector{sq[2], sq[1]})
        for 4 do
            tags.add(CURVE_TAG_ON)
        contours.add(cast(s16) points.count - 1)
    }

    // Loading any glyph leaves the slot holding an outline, which the view then replaces.
    discard expect face.loadChar('A')
    face.glyph.outline.setView(points.buffer, tags.buffer, contours.buffer, cast(s16) points.count, cast(s16) contours.count)
    discard expect face.renderGlyphMsdf(8)

    let bitmap = &face.glyph.bitmap
    Swag.assert(countMsdfSignMismatches(bitmap) == 0)

    let col = cast(u64) (x - face.glyph.bitmapLeft)
    let row = cast(u64) (face.glyph.bitmapTop - y)
    let buf = bitmap.buffer!
    let p   = (row * bitmap.width + col) * 4

    var result: retval
    result.median = Math.max(Math.min(buf[p], buf[p + 1]), Math.min(Math.max(buf[p], buf[p + 1]), buf[p + 2]))
    result.alpha  = buf[p + 3]
    return result
}

// A synthetic bold closes the narrow notches of a glyph over themselves: the two sides of the
// notch between a stem and a diagonal cross, and run on inside the ink. The field must still
// agree with the fill everywhere instead of opening holes beside them.
#test
{
    var scope: FaceScope
    scope.init()
    let face = scope.face!

    discard expect face.setPixelSize(0, 40)
    for c in "MWkx"
    {
        discard expect face.loadChar(cast(rune) c)
        discard expect face.glyph.outline.embolden(3 * 64)
        discard expect face.renderGlyphMsdf(8)
        Swag.assert(countMsdfSignMismatches(&face.glyph.bitmap) == 0)
    }
}

// Overlapping contours fill their union, whose boundary is the only thing a distance measures.
// At (15.5, 15.5), inside both squares, the union's nearest boundary is the corner at (10, 20),
// 7.1 pixels away; the edges of either square that run through the other are 4.5 pixels away
// and must not count.
#test
{
    var scope: FaceScope
    scope.init()
    let face = scope.face!

    let squares: [2] [4] s32 = [[0, 0, 1280, 1280], [640, 640, 1920, 1920]]
    let texel = renderSquares(face, squares, 15.5, 15.5)
    Swag.assert(texel.median > 128)
    Swag.assert(texel.alpha >= 239)
}

// A contour nested inside another, wound the same way, adds nothing to the fill and bounds
// nothing either. At (4.5, 10.5), half a pixel outside the inner square, the nearest boundary
// is the outer square's left side, 4.5 pixels away.
#test
{
    var scope: FaceScope
    scope.init()
    let face = scope.face!

    let squares: [2] [4] s32 = [[0, 0, 1280, 1280], [320, 320, 960, 960]]
    let texel = renderSquares(face, squares, 4.5, 10.5)
    Swag.assert(texel.median > 128)
    Swag.assert(texel.alpha >= 198)
}
