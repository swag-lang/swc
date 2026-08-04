#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var scope: FaceScope
    scope.init("arial.ttf")
    let face = scope.face!

    let glyphA = face.glyphIndex('A')
    let glyphV = face.glyphIndex('V')
    @assert(glyphA > 0)
    @assert(glyphV > 0)

    discard expect face.setPixelSize(0, 100)

    // 'AV' is a classic negative kerning pair (glyphs tucked closer together).
    let kern100 = face.getKerning(glyphA, glyphV)
    @assert(kern100.x < 0)

    // Kerning is scaled to the pixel size, so it grows with the size.
    discard catch face.setPixelSize(0, 200)
    let kern200 = face.getKerning(glyphA, glyphV)
    @assert(kern200.x < kern100.x)

    // A missing glyph yields no kerning.
    let none = face.getKerning(glyphA, 0)
    @assert(none.x == 0)
}
