#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var scope: FaceScope
    scope.init()
    let face = scope.face!

    discard expect face.setPixelSize(0, 20)
    let glyphIndex = face.glyphIndex('A')
    discard expect face.loadGlyph(glyphIndex, .Render)
    @assert(face.glyph.bitmap.width > 0)
    @assert(face.glyph.bitmap.rows > 0)
    @assert(face.glyph.bitmap.pitch == cast(s32) face.glyph.bitmap.width)
    @assert(face.glyph.bitmap.pixelMode.bytesPerPixel() == 1)
    @assert(countBitmapCoverage(&face.glyph.bitmap) > 0)

    discard expect face.loadChar(' ', .Default)
    discard expect face.renderGlyph()
    @assert(countBitmapCoverage(&face.glyph.bitmap) == 0)
}

#test
{
    var scope: FaceScope
    scope.init()
    let face = scope.face!

    discard expect face.setPixelSize(0, 32)
    discard expect face.loadChar('A', .Default)
    discard expect face.renderGlyph()
    let normal     = face.glyph.bitmap
    let normalLeft = face.glyph.bitmapLeft
    let normalTop  = face.glyph.bitmapTop

    discard expect face.renderGlyphSdf(8)
    let sdf = &face.glyph.bitmap
    @assert(sdf.width > normal.width)
    @assert(sdf.rows > normal.rows)
    @assert(sdf.pitch == cast(s32) sdf.width)
    @assert(face.glyph.bitmapLeft < normalLeft)
    @assert(face.glyph.bitmapTop > normalTop)

    var hasOutside = false
    var hasInside  = false
    let sdfBuf     = sdf.buffer!
    for cast(u64) sdf.width * sdf.rows
    {
        let value = sdfBuf[@index]
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
    let face = scope.face!

    discard expect face.setPixelSize(0, 40)
    discard expect face.loadChar('A', .Default)
    discard expect face.renderGlyph()
    let bmp = &face.glyph.bitmap
    @assert(bmp.width > 0)
    @assert(bmp.rows > 0)

    var hasZero    = false
    var hasFull    = false
    var hasPartial = false
    let bmpBuf     = bmp.buffer!
    for cast(u64) bmp.width * bmp.rows
    {
        let v = bmpBuf[@index]
        if v == 0 do
            hasZero = true
        elif v == 255 do
            hasFull = true
        else do
            hasPartial = true
    }

    @assert(hasZero)        // background corners
    @assert(hasFull)        // solid stems are fully covered
    @assert(hasPartial)     // anti-aliased edges
}

#test
{
    var scope: FaceScope
    scope.init()
    let face = scope.face!

    discard expect face.setPixelSize(0, 20)
    discard expect face.loadChar('A', .Default)
    discard catch face.loadGlyph(face.glyphCount + 1, .Default) as err15
    @assert(err15 != null)
}

// Multi-channel SDF: 3 bytes per pixel, padded like the single-channel SDF, and the
// per-pixel median must agree with the actual inside/outside of the glyph.
#test
{
    var scope: FaceScope
    scope.init()
    let face = scope.face!

    discard expect face.setPixelSize(0, 32)
    discard expect face.loadChar('A', .Default)
    discard expect face.renderGlyph()
    let normalWidth = face.glyph.bitmap.width
    let normalRows  = face.glyph.bitmap.rows
    let normalLeft  = face.glyph.bitmapLeft
    let normalTop   = face.glyph.bitmapTop

    let spread = 8'u32
    discard expect face.renderGlyphMsdf(spread)
    let msdf = &face.glyph.bitmap
    @assert(msdf.width > normalWidth)
    @assert(msdf.rows > normalRows)

    // MTSDF: 4 bytes per pixel (RGB multi-channel field + true SDF in alpha).
    @assert(msdf.pitch == cast(s32) msdf.width * 4)
    @assert(msdf.pixelMode.bytesPerPixel() == 4)
    @assert(face.glyph.bitmapLeft == normalLeft - cast(s32) spread)
    @assert(face.glyph.bitmapTop == normalTop + cast(s32) spread)

    // The padded border must be fully outside (median < 128), the glyph body must
    // contain inside pixels (median > 128), and channels must actually differ
    // somewhere (otherwise this degenerated into a plain single-channel SDF). The
    // alpha (true SDF) channel must also carry an inside/outside transition.
    var hasInside      = false
    var hasOutside     = false
    var channelsDiffer = false
    var hasInsideA     = false
    var hasOutsideA    = false
    let msdfBuf        = msdf.buffer!
    for y in msdf.rows
    {
        for x in msdf.width
        {
            let p = (cast(u64) y * msdf.width + x) * 4
            let r = msdfBuf[p + 0]
            let g = msdfBuf[p + 1]
            let b = msdfBuf[p + 2]
            let a = msdfBuf[p + 3]
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
    let corner = Math.max(Math.min(msdfBuf[0], msdfBuf[1]), Math.min(Math.max(msdfBuf[0], msdfBuf[1]), msdfBuf[2]))
    @assert(corner < 128)
}
