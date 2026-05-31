#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    let glyphA = catch lookupCMap4(Cmap4Fixture, 'A''u32)
    @assert(@err == null)
    @assert(glyphA == 3)

    let glyphB = catch lookupCMap4(Cmap4Fixture, 'B''u32)
    @assert(@err == null)
    @assert(glyphB == 0)
}

#test
{
    let glyph0 = catch lookupCMap12(Cmap12Fixture, 0x00010000)
    @assert(@err == null)
    @assert(glyph0 == 7)

    let glyph1 = catch lookupCMap12(Cmap12Fixture, 0x00010001)
    @assert(@err == null)
    @assert(glyph1 == 0)
}

#test
{
    var scope: FaceScope
    scope.init()

    let glyphA = scope.face.glyphIndex('A')
    let glyphE = scope.face.glyphIndex(0x00E9)
    let glyphMissing = scope.face.glyphIndex(0x10FFFF)

    @assert(glyphA > 0)
    @assert(glyphE > 0)
    @assert(glyphMissing == 0)
}
