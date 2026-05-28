#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    withFace(func(_, _, face)
    {
        let glyphIndex = FT_Get_Char_Index(face, 0x00E9)
        @assert(glyphIndex > 0)

        let faceData = getFaceData(face)
        let glyf = catch FreeTypePriv.getTableSlice(faceData, FreeTypePriv.TAG_GLYF, 0x10)
        @assert(@err == null)

        let glyphStart = faceData.glyphLocations[glyphIndex]
        let glyphEnd = faceData.glyphLocations[glyphIndex + 1]
        let glyphData = catch FreeTypePriv.getSlice(glyf, glyphStart, glyphEnd - glyphStart)
        @assert(@err == null)
        let contourCount = catch FreeTypePriv.readS16(glyphData, 0)
        @assert(@err == null)
        @assert(contourCount < 0)

        discard catch FT_Set_Pixel_Sizes(face, 0, 20)
        @assert(@err == null)
        discard catch FT_Load_Char(face, 0x00E9, FT_LOAD_NO_BITMAP)
        @assert(@err == null)
        @assert(face.glyph.glyph_index == glyphIndex)
        @assert(face.glyph.outline.n_points > 0)
        @assert(face.glyph.outline.n_contours > 0)

        discard catch FT_Render_Glyph(face.glyph, .FT_RENDER_MODE_NORMAL)
        @assert(@err == null)
        @assert(countBitmapCoverage(&face.glyph.bitmap) > 0)
    })
}
