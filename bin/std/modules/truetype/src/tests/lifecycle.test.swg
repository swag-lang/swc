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
    withLibrary(func(library)
    {
        discard catch FT_Library_SetLcdFilter(library, .FT_LCD_FILTER_DEFAULT)
        @assert(@err == null)

        let weights: [5] u8 = [0x08, 0x4D, 0x56, 0x4D, 0x08]
        discard catch FT_Library_SetLcdFilterWeights(library, &weights[0])
        @assert(@err == null)

        discard catch FT_Library_SetLcdFilterWeights(library, null)
        @assert(@err != null)
    })
}

#test
{
    withFace(func(bytes, _, face)
    {
        @assert(bytes.count > 0)
        @assert(face.num_glyphs > 0)
        @assert(face.family_name != null)
        @assert(face.style_name != null)
        @assert(face.units_per_EM > 0)
        @assert(face.ascender > 0)
        @assert(face.descender < 0)
        @assert(face.max_advance_width > 0)
        @assert(face.glyph != null)
        @assert(face.size != null)
        @assert(face.charmap != null)

        discard catch FT_Set_Pixel_Sizes(face, 0, 16)
        @assert(@err == null)
        @assert(face.size.metrics.x_ppem == 16)
        @assert(face.size.metrics.y_ppem == 16)
        @assert(face.size.metrics.ascender > 0)
        @assert(face.size.metrics.descender < 0)
        @assert(face.size.metrics.max_advance > 0)

        discard catch FT_Set_Pixel_Sizes(face, 24, 0)
        @assert(@err == null)
        @assert(face.size.metrics.x_ppem == 24)
        @assert(face.size.metrics.y_ppem == 24)

        discard catch FT_Set_Pixel_Sizes(face, 0, 0)
        @assert(@err != null)
    })
}
