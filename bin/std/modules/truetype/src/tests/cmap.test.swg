#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    let glyphA = catch FreeTypePriv.lookupCMap4(Cmap4Fixture, 'A''u32)
    @assert(@err == null)
    @assert(glyphA == 3)

    let glyphB = catch FreeTypePriv.lookupCMap4(Cmap4Fixture, 'B''u32)
    @assert(@err == null)
    @assert(glyphB == 0)
}

#test
{
    let glyph0 = catch FreeTypePriv.lookupCMap12(Cmap12Fixture, 0x00010000)
    @assert(@err == null)
    @assert(glyph0 == 7)

    let glyph1 = catch FreeTypePriv.lookupCMap12(Cmap12Fixture, 0x00010001)
    @assert(@err == null)
    @assert(glyph1 == 0)
}

#test
{
    withFace(func(_, _, face)
    {
        let glyphA = FT_Get_Char_Index(face, 'A''u32)
        let glyphE = FT_Get_Char_Index(face, 0x00E9)
        let glyphMissing = FT_Get_Char_Index(face, 0x10FFFF)

        @assert(glyphA > 0)
        @assert(glyphE > 0)
        @assert(glyphMissing == 0)
    })
}
