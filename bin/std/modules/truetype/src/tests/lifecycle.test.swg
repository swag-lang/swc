#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

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
