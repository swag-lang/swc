#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    var scope: FaceScope
    scope.init()

    discard catch scope.face.setPixelSize(0, 20)
    @assert(@err == null)

    let glyphIndex = scope.face.glyphIndex('A')
    discard catch scope.face.loadGlyph(glyphIndex, .Render)
    @assert(@err == null)
    @assert(scope.face.glyph.bitmap.width > 0)
    @assert(scope.face.glyph.bitmap.rows > 0)
    @assert(scope.face.glyph.bitmap.pitch == cast(s32) scope.face.glyph.bitmap.width)
    @assert(countBitmapCoverage(&scope.face.glyph.bitmap) > 0)

    discard catch scope.face.loadChar(' ', .Default)
    @assert(@err == null)
    discard catch scope.face.renderGlyph()
    @assert(@err == null)
    @assert(countBitmapCoverage(&scope.face.glyph.bitmap) == 0)
}

#test
{
    var scope: FaceScope
    scope.init()

    discard catch scope.face.setPixelSize(0, 32)
    @assert(@err == null)

    discard catch scope.face.loadChar('A', .Default)
    @assert(@err == null)
    discard catch scope.face.renderGlyph()
    @assert(@err == null)

    let normal = scope.face.glyph.bitmap
    let normalLeft = scope.face.glyph.bitmapLeft
    let normalTop  = scope.face.glyph.bitmapTop

    discard catch scope.face.renderGlyphSdf(8)
    @assert(@err == null)

    let sdf = &scope.face.glyph.bitmap
    @assert(sdf.width > normal.width)
    @assert(sdf.rows > normal.rows)
    @assert(sdf.pitch == cast(s32) sdf.width)
    @assert(scope.face.glyph.bitmapLeft < normalLeft)
    @assert(scope.face.glyph.bitmapTop > normalTop)

    var hasOutside = false
    var hasInside  = false
    for cast(u64) sdf.width * sdf.rows
    {
        let value = sdf.buffer[@index]
        if value < 128 do
            hasOutside = true
        if value > 128 do
            hasInside = true
    }

    @assert(hasOutside)
    @assert(hasInside)
}

// The analytic rasterizer must produce true anti-aliasing: fully-outside pixels (0),
// fully-covered interior pixels (255), and partially-covered edge pixels in between.
#test
{
    var scope: FaceScope
    scope.init()

    discard catch scope.face.setPixelSize(0, 40)
    @assert(@err == null)

    discard catch scope.face.loadChar('A', .Default)
    @assert(@err == null)
    discard catch scope.face.renderGlyph()
    @assert(@err == null)

    let bmp = &scope.face.glyph.bitmap
    @assert(bmp.width > 0)
    @assert(bmp.rows > 0)

    var hasZero    = false
    var hasFull    = false
    var hasPartial = false
    for cast(u64) bmp.width * bmp.rows
    {
        let v = bmp.buffer[@index]
        if v == 0 do
            hasZero = true
        elif v == 255 do
            hasFull = true
        else do
            hasPartial = true
    }

    @assert(hasZero)       // background corners
    @assert(hasFull)       // solid stems are fully covered
    @assert(hasPartial)    // anti-aliased edges
}

#test
{
    var scope: FaceScope
    scope.init()

    discard catch scope.face.setPixelSize(0, 20)
    @assert(@err == null)

    discard catch scope.face.loadChar('A', .Default)
    @assert(@err == null)
    discard catch scope.face.renderGlyph(.Mono)
    @assert(@err != null)

    discard catch scope.face.loadGlyph(scope.face.glyphCount + 1, .Default)
    @assert(@err != null)
}

// Multi-channel SDF: 3 bytes per pixel, padded like the single-channel SDF, and the
// per-pixel median must agree with the actual inside/outside of the glyph.
#test
{
    var scope: FaceScope
    scope.init()

    discard catch scope.face.setPixelSize(0, 32)
    @assert(@err == null)

    discard catch scope.face.loadChar('A', .Default)
    @assert(@err == null)
    discard catch scope.face.renderGlyph()
    @assert(@err == null)

    let normalWidth = scope.face.glyph.bitmap.width
    let normalRows  = scope.face.glyph.bitmap.rows
    let normalLeft  = scope.face.glyph.bitmapLeft
    let normalTop   = scope.face.glyph.bitmapTop

    let spread = 8'u32
    discard catch scope.face.renderGlyphMsdf(spread)
    @assert(@err == null)

    let msdf = &scope.face.glyph.bitmap
    @assert(msdf.width > normalWidth)
    @assert(msdf.rows > normalRows)
    // MTSDF: 4 bytes per pixel (RGB multi-channel field + true SDF in alpha).
    @assert(msdf.pitch == cast(s32) msdf.width * 4)
    @assert(scope.face.glyph.bitmapLeft == normalLeft - cast(s32) spread)
    @assert(scope.face.glyph.bitmapTop == normalTop + cast(s32) spread)

    // The padded border must be fully outside (median < 128), the glyph body must
    // contain inside pixels (median > 128), and channels must actually differ
    // somewhere (otherwise this degenerated into a plain single-channel SDF). The
    // alpha (true SDF) channel must also carry an inside/outside transition.
    var hasInside      = false
    var hasOutside     = false
    var channelsDiffer = false
    var hasInsideA     = false
    var hasOutsideA    = false
    for y in msdf.rows
    {
        for x in msdf.width
        {
            let p = (cast(u64) y * msdf.width + x) * 4
            let r = msdf.buffer[p + 0]
            let g = msdf.buffer[p + 1]
            let b = msdf.buffer[p + 2]
            let a = msdf.buffer[p + 3]
            let m = Math.max(Math.min(r, g), Math.min(Math.max(r, g), b))
            if m > 128 do
                hasInside = true
            if m < 128 do
                hasOutside = true
            if r != g or g != b do
                channelsDiffer = true
            if a > 128 do
                hasInsideA = true
            if a < 128 do
                hasOutsideA = true
        }
    }

    @assert(hasInside)
    @assert(hasOutside)
    @assert(channelsDiffer)
    @assert(hasInsideA)
    @assert(hasOutsideA)

    // Top-left corner of the padded bounding box is far outside the glyph.
    let corner = Math.max(Math.min(msdf.buffer[0], msdf.buffer[1]), Math.min(Math.max(msdf.buffer[0], msdf.buffer[1]), msdf.buffer[2]))
    @assert(corner < 128)
}
