#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

func makeShapingTestFont()->*Font
{
    let face = assume TypeFace.load(getTestDataPath("segoeui.ttf"))
    return Font.create(face, 32, .Bitmap)
}

#test
{
    let font = makeShapingTestFont()
    let text = "A\u00E9"
    var shaped = Painter.shapeRun(text, font)

    @assert(shaped.font == font)
    @assert(shaped.glyphs.count == 2)
    @assert(shaped.glyphs[0].cluster == 0)
    @assert(shaped.glyphs[1].cluster == 1)
    @assert(shaped.glyphs[0].glyphIndex == font.glyphIndex('A'))
    @assert(shaped.glyphs[1].glyphIndex == font.glyphIndex('\u00E9''rune))
    @assert(shaped.metrics.width > 0)

    let glyphA = font.getGlyphDescByIndex(font.glyphIndex('A'))
    @assert(shaped.glyphs[0].desc == glyphA)
    @assert(font.getGlyphDesc('A') == glyphA)

    let measured = Painter.measureString(text, font)
    @assert(Math.isEqualEpsilon(measured.width, shaped.metrics.width, 0.001))
    @assert(Math.isEqualEpsilon(measured.height, shaped.metrics.height, 0.001))

    let msdfFont = Font.create(font.cache.typeFace, 32, .Msdf)
    let reshaped = Painter.shapeRunForFont(&shaped, msdfFont)
    @assert(reshaped.font == msdfFont)
    @assert(reshaped.glyphs.count == shaped.glyphs.count)
    @assert(reshaped.glyphs[0].glyphIndex == shaped.glyphs[0].glyphIndex)
    @assert(reshaped.glyphs[1].cluster == shaped.glyphs[1].cluster)
}
