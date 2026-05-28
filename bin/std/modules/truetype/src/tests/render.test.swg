#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    withFace(func(_, _, face)
    {
        discard catch FT_Set_Pixel_Sizes(face, 0, 20)
        @assert(@err == null)

        let glyphIndex = FT_Get_Char_Index(face, 'A''u32)
        discard catch FT_Load_Glyph(face, glyphIndex, FT_LOAD_RENDER)
        @assert(@err == null)
        @assert(face.glyph.bitmap.width > 0)
        @assert(face.glyph.bitmap.rows > 0)
        @assert(face.glyph.bitmap.pitch == cast(s32) face.glyph.bitmap.width)
        @assert(countBitmapCoverage(&face.glyph.bitmap) > 0)

        discard catch FT_Load_Char(face, ' ''u32, FT_LOAD_DEFAULT)
        @assert(@err == null)
        discard catch FT_Render_Glyph(face.glyph, .FT_RENDER_MODE_NORMAL)
        @assert(@err == null)
        @assert(countBitmapCoverage(&face.glyph.bitmap) == 0)
    })
}

#test
{
    withFace(func(_, _, face)
    {
        discard catch FT_Set_Pixel_Sizes(face, 0, 20)
        @assert(@err == null)

        discard catch FT_Load_Char(face, 'A''u32, FT_LOAD_DEFAULT)
        @assert(@err == null)
        discard catch FT_Render_Glyph(face.glyph, .FT_RENDER_MODE_MONO)
        @assert(@err != null)

        discard catch FT_Load_Glyph(face, cast(FT_UInt) face.num_glyphs + 1, FT_LOAD_DEFAULT)
        @assert(@err != null)
    })
}
