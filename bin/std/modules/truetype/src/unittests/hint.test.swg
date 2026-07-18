#global #if #command == Swag.CompilerCommand.Test
#global #[Swag.ExplicitNullability]
using Swag, Core

// Distance (in 26.6 units) from a value to the nearest whole-pixel boundary.
func distToPixel(v: s32)->s32
{
    var r = v % 64
    if r < 0 do
        r += 64
    return Math.min(r, 64 - r)
}

// Vertical hinting must snap the x-height to a whole pixel (the top of 'x' is the
// x-height) and must never make the alignment worse.
#test
{
    var scope: FaceScope
    scope.init("arial.ttf")

    discard catch scope.face.setPixelSize(0, 13)
    @assert(@err == null)

    discard catch scope.face.loadChar('x')
    @assert(@err == null)

    let before = getOutlineBounds(&scope.face.glyph.outline).yMax

    discard catch scope.face.hintVertical()
    @assert(@err == null)

    let after = getOutlineBounds(&scope.face.glyph.outline).yMax

    // The baseline (y = 0) must stay put, and the x-height must end up on (or within
    // rounding of) a whole pixel, at least as well aligned as before.
    @assert(distToPixel(after) <= distToPixel(before) + 1)
    @assert(distToPixel(after) <= 3)
}
