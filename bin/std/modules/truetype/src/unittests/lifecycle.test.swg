#global #if #command == Swag.CompilerCommand.Test

using Swag, Core

func assertFixtureFontLoads(fileName: string, expectedStyle: StyleFlag)
{
    var scope: FaceScope
    scope.init(fileName)
    let face = notnull scope.face

    @assert(scope.bytes.count > 0)
    @assert(face.faceCount == 1)
    @assert(face.faceIndex == 0)
    @assert(face.glyphCount > 0)
    @assert(!face.familyName.isEmpty())
    @assert(!face.styleName.isEmpty())
    @assert((face.style & (.Bold | .Italic)) == expectedStyle)

    let glyphA = face.glyphIndex('A')
    @assert(glyphA > 0)

    discard catch face.setPixelSize(0, 18)
    @assert(@err == null)
    discard catch face.loadGlyph(glyphA, .Render)
    @assert(@err == null)
    @assert(face.glyph.bitmap.width > 0)
    @assert(face.glyph.bitmap.rows > 0)
    @assert(countBitmapCoverage(&face.glyph.bitmap) > 0)
}

#test
{
    let badFace0: #null *Face = catch Face.load(BrokenFontBytes)
    @assert(@err != null)

    var empty:    Array'u8
    let badFace1: #null *Face = catch Face.load(empty.toSlice())
    @assert(@err != null)

    let bytes = loadFontBytes()
    let badFace2: #null *Face = catch Face.load(bytes.toSlice(), 1)
    @assert(@err != null)
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

    discard catch face.setPixelSize(0, 16)
    @assert(@err == null)
    @assert(face.size.metrics.xPpem == 16)
    @assert(face.size.metrics.yPpem == 16)
    @assert(face.size.metrics.ascender > 0)
    @assert(face.size.metrics.descender < 0)
    @assert(face.size.metrics.maxAdvance > 0)

    discard catch face.setPixelSize(24, 0)
    @assert(@err == null)
    @assert(face.size.metrics.xPpem == 24)
    @assert(face.size.metrics.yPpem == 24)

    discard catch face.setPixelSize(0, 0)
    @assert(@err != null)
}

#test
{
    assertFixtureFontLoads("arial.ttf", .None)
    assertFixtureFontLoads("arialbd.ttf", .Bold)
    assertFixtureFontLoads("ariali.ttf", .Italic)
    assertFixtureFontLoads("arialbi.ttf", .Bold | .Italic)
}
