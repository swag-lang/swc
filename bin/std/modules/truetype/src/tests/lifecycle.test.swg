#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

func assertFixtureFontLoads(fileName: string, expectedFlags: FT_Long)
{
    var scope: FaceScope
    scope.init(fileName)

    @assert(scope.bytes.count > 0)
    @assert(scope.face.num_faces == 1)
    @assert(scope.face.face_index == 0)
    @assert(scope.face.num_glyphs > 0)
    @assert(scope.face.family_name != null)
    @assert(scope.face.style_name != null)
    @assert((scope.face.style_flags & (FT_STYLE_FLAG_BOLD | FT_STYLE_FLAG_ITALIC)) == expectedFlags)

    let glyphA = FT_Get_Char_Index(scope.face, 'A''u32)
    @assert(glyphA > 0)

    discard catch FT_Set_Pixel_Sizes(scope.face, 0, 18)
    @assert(@err == null)
    discard catch FT_Load_Glyph(scope.face, glyphA, FT_LOAD_RENDER)
    @assert(@err == null)
    @assert(scope.face.glyph.bitmap.width > 0)
    @assert(scope.face.glyph.bitmap.rows > 0)
    @assert(countBitmapCoverage(&scope.face.glyph.bitmap) > 0)
}

#test
{
    discard catch FT_Init_FreeType(null)
    @assert(@err != null)

    discard catch FT_Done_FreeType(null)
    @assert(@err != null)
}

#test
{
    var scope: LibraryScope
    scope.init()

    discard catch FT_Library_SetLcdFilter(scope.library, .FT_LCD_FILTER_DEFAULT)
    @assert(@err == null)

    let weights: [5] u8 = [0x08, 0x4D, 0x56, 0x4D, 0x08]
    discard catch FT_Library_SetLcdFilterWeights(scope.library, &weights[0])
    @assert(@err == null)

    discard catch FT_Library_SetLcdFilterWeights(scope.library, null)
    @assert(@err != null)
}

#test
{
    var scope: FaceScope
    scope.init()

    @assert(scope.bytes.count > 0)
    @assert(scope.face.num_glyphs > 0)
    @assert(scope.face.family_name != null)
    @assert(scope.face.style_name != null)
    @assert(scope.face.units_per_EM > 0)
    @assert(scope.face.ascender > 0)
    @assert(scope.face.descender < 0)
    @assert(scope.face.max_advance_width > 0)
    @assert(scope.face.glyph != null)
    @assert(scope.face.size != null)
    @assert(scope.face.charmap != null)

    discard catch FT_Set_Pixel_Sizes(scope.face, 0, 16)
    @assert(@err == null)
    @assert(scope.face.size.metrics.x_ppem == 16)
    @assert(scope.face.size.metrics.y_ppem == 16)
    @assert(scope.face.size.metrics.ascender > 0)
    @assert(scope.face.size.metrics.descender < 0)
    @assert(scope.face.size.metrics.max_advance > 0)

    discard catch FT_Set_Pixel_Sizes(scope.face, 24, 0)
    @assert(@err == null)
    @assert(scope.face.size.metrics.x_ppem == 24)
    @assert(scope.face.size.metrics.y_ppem == 24)

    discard catch FT_Set_Pixel_Sizes(scope.face, 0, 0)
    @assert(@err != null)
}

#test
{
    assertFixtureFontLoads("arial.ttf", 0)
    assertFixtureFontLoads("arialbd.ttf", FT_STYLE_FLAG_BOLD)
    assertFixtureFontLoads("ariali.ttf", FT_STYLE_FLAG_ITALIC)
    assertFixtureFontLoads("arialbi.ttf", FT_STYLE_FLAG_BOLD | FT_STYLE_FLAG_ITALIC)
}
