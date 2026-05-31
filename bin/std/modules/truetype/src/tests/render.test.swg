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

    discard catch scope.face.setPixelSize(0, 20)
    @assert(@err == null)

    discard catch scope.face.loadChar('A', .Default)
    @assert(@err == null)
    discard catch scope.face.renderGlyph(.Mono)
    @assert(@err != null)

    discard catch scope.face.loadGlyph(scope.face.glyphCount + 1, .Default)
    @assert(@err != null)
}
