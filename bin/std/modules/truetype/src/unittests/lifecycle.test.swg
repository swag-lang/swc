#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

func assertFixtureFontLoads(fileName: #nonull string, expectedStyle: StyleFlag)
{
    var scope: FaceScope
    scope.init(fileName)

    @assert(scope.bytes.count > 0)
    @assert(scope.face.faceCount == 1)
    @assert(scope.face.faceIndex == 0)
    @assert(scope.face.glyphCount > 0)
    @assert(!scope.face.familyName.isEmpty())
    @assert(!scope.face.styleName.isEmpty())
    @assert((scope.face.style & (.Bold | .Italic)) == expectedStyle)

    let glyphA = scope.face.glyphIndex('A')
    @assert(glyphA > 0)

    discard catch scope.face.setPixelSize(0, 18)
    @assert(@err == null)
    discard catch scope.face.loadGlyph(glyphA, .Render)
    @assert(@err == null)
    @assert(scope.face.glyph.bitmap.width > 0)
    @assert(scope.face.glyph.bitmap.rows > 0)
    @assert(countBitmapCoverage(&scope.face.glyph.bitmap) > 0)
}

#test
{
    let badFace0: #null *Face = catch Face.load(BrokenFontBytes)
    @assert(@err != null)

    var empty: Array'u8
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

    @assert(scope.bytes.count > 0)
    @assert(scope.face.glyphCount > 0)
    @assert(!scope.face.familyName.isEmpty())
    @assert(!scope.face.styleName.isEmpty())
    @assert(scope.face.unitsPerEm > 0)
    @assert(scope.face.ascender > 0)
    @assert(scope.face.descender < 0)
    @assert(scope.face.maxAdvanceWidth > 0)

    discard catch scope.face.setPixelSize(0, 16)
    @assert(@err == null)
    @assert(scope.face.size.metrics.xPpem == 16)
    @assert(scope.face.size.metrics.yPpem == 16)
    @assert(scope.face.size.metrics.ascender > 0)
    @assert(scope.face.size.metrics.descender < 0)
    @assert(scope.face.size.metrics.maxAdvance > 0)

    discard catch scope.face.setPixelSize(24, 0)
    @assert(@err == null)
    @assert(scope.face.size.metrics.xPpem == 24)
    @assert(scope.face.size.metrics.yPpem == 24)

    discard catch scope.face.setPixelSize(0, 0)
    @assert(@err != null)
}

#test
{
    assertFixtureFontLoads("arial.ttf", .None)
    assertFixtureFontLoads("arialbd.ttf", .Bold)
    assertFixtureFontLoads("ariali.ttf", .Italic)
    assertFixtureFontLoads("arialbi.ttf", .Bold | .Italic)
}
