#global #if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var scope: FaceScope
    scope.init("arial.ttf")
    let face = notnull scope.face

    let glyphA = face.glyphIndex('A')
    let glyphV = face.glyphIndex('V')
    @assert(glyphA > 0)
    @assert(glyphV > 0)

    discard catch face.setPixelSize(0, 100)
    @assert(@err == null)

    // 'AV' is a classic negative kerning pair (glyphs tucked closer together).
    let kern100 = catch face.getKerning(glyphA, glyphV)
    @assert(@err == null)
    @assert(kern100.x < 0)

    // Kerning is scaled to the pixel size, so it grows with the size.
    discard catch face.setPixelSize(0, 200)
    let kern200 = catch face.getKerning(glyphA, glyphV)
    @assert(@err == null)
    @assert(kern200.x < kern100.x)

    // A missing glyph yields no kerning.
    let none = catch face.getKerning(glyphA, 0)
    @assert(@err == null)
    @assert(none.x == 0)
}
