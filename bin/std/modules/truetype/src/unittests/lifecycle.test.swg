#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func assertFixtureFontLoads(fileName: string, expectedStyle: StyleFlag)
{
    var scope: FaceScope
    scope.init(fileName)
    let face = notnull scope.face

    @assert(scope.bytes.count > 0)
    @assert(face.glyphCount > 0)
    @assert(!face.familyName.isEmpty())
    @assert(!face.styleName.isEmpty())
    @assert((face.style & (.Bold | .Italic)) == expectedStyle)

    let glyphA = face.glyphIndex('A')
    @assert(glyphA > 0)

    discard catch face.setPixelSize(0, 18) as err
    @assert(err == null)
    discard catch face.loadGlyph(glyphA, .Render) as err2
    @assert(err2 == null)
    @assert(face.glyph.bitmap.width > 0)
    @assert(face.glyph.bitmap.rows > 0)
    @assert(countBitmapCoverage(&face.glyph.bitmap) > 0)
}

#test
{
    let badFace0: #null *Face = catch Face.load(BrokenFontBytes) as err3
    @assert(err3 != null)

    var empty:    Array'u8
    let badFace1: #null *Face = catch Face.load(empty.toSlice()) as err4
    @assert(err4 != null)
}

#test
{
    var scope: FaceScope
    scope.init()
    let face = notnull scope.face

    @assert(scope.bytes.count > 0)
    @assert(face.glyphCount > 0)
    @assert(!face.familyName.isEmpty())
    @assert(!face.styleName.isEmpty())
    @assert(face.unitsPerEm > 0)
    @assert(face.ascender > 0)
    @assert(face.descender < 0)
    @assert(face.maxAdvanceWidth > 0)

    discard catch face.setPixelSize(0, 16) as err6
    @assert(err6 == null)
    @assert(face.size.metrics.xPpem == 16)
    @assert(face.size.metrics.yPpem == 16)
    @assert(face.size.metrics.ascender > 0)
    @assert(face.size.metrics.descender < 0)
    @assert(face.size.metrics.maxAdvance > 0)

    discard catch face.setPixelSize(24, 0) as err7
    @assert(err7 == null)
    @assert(face.size.metrics.xPpem == 24)
    @assert(face.size.metrics.yPpem == 24)

    discard catch face.setPixelSize(0, 0) as err8
    @assert(err8 != null)

    discard catch face.setPixelSize(Swag.U16.Max + 1, 16) as err9
    @assert(err9 != null)

    @assert(face.hasChar('A'))
    @assert(!face.hasChar(0x10FFFF))
}

#test
{
    assertFixtureFontLoads("arial.ttf", .None)
    assertFixtureFontLoads("arialbd.ttf", .Bold)
    assertFixtureFontLoads("ariali.ttf", .Italic)
    assertFixtureFontLoads("arialbi.ttf", .Bold | .Italic)
}
