#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    var scope: FaceScope
    scope.init()

    discard catch FT_Set_Pixel_Sizes(scope.face, 0, 20)
    @assert(@err == null)

    let glyphIndex = FT_Get_Char_Index(scope.face, 'A''u32)
    discard catch FT_Load_Glyph(scope.face, glyphIndex, FT_LOAD_RENDER)
    @assert(@err == null)
    @assert(scope.face.glyph.bitmap.width > 0)
    @assert(scope.face.glyph.bitmap.rows > 0)
    @assert(scope.face.glyph.bitmap.pitch == cast(s32) scope.face.glyph.bitmap.width)
    @assert(countBitmapCoverage(&scope.face.glyph.bitmap) > 0)

    discard catch FT_Load_Char(scope.face, ' ''u32, FT_LOAD_DEFAULT)
    @assert(@err == null)
    discard catch FT_Render_Glyph(scope.face.glyph, .FT_RENDER_MODE_NORMAL)
    @assert(@err == null)
    @assert(countBitmapCoverage(&scope.face.glyph.bitmap) == 0)
}

#test
{
    var scope: FaceScope
    scope.init()

    discard catch FT_Set_Pixel_Sizes(scope.face, 0, 20)
    @assert(@err == null)

    discard catch FT_Load_Char(scope.face, 'A''u32, FT_LOAD_DEFAULT)
    @assert(@err == null)
    discard catch FT_Render_Glyph(scope.face.glyph, .FT_RENDER_MODE_MONO)
    @assert(@err != null)

    discard catch FT_Load_Glyph(scope.face, cast(FT_UInt) scope.face.num_glyphs + 1, FT_LOAD_DEFAULT)
    @assert(@err != null)
}
