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
