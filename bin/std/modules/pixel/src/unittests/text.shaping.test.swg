#global #if #command == Swag.CompilerCommand.Test

using Swag, Core

func makeShapingTestFont()->*Font
{
    var face: *TypeFace = undefined
    catch loadTestTypeFace(&face, getTestDataPath("segoeui.ttf"))
    @assert(@err == null)
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
    @assert(shaped.hasInk)
    @assert(shaped.inkBounds.width > 0)
    @assert(shaped.inkBounds.height > 0)
    @assert(shaped.inkBounds.x <= shaped.metrics.width)

    let glyphA = font.getGlyphDescByIndex(font.glyphIndex('A'))
    @assert(shaped.glyphs[0].desc == glyphA)
    @assert(font.getGlyphDesc('A') == glyphA)

    let measured = Painter.measureString(text, font)
    @assert(Math.isEqualEpsilon(measured.width, shaped.metrics.width, 0.001))
    @assert(Math.isEqualEpsilon(measured.height, shaped.metrics.height, 0.001))

    let normalABC = Painter.shapeRun("ABC", font)
    let spacedABC = Painter.shapeRun("ABC", font, 4, 1.5'f32)
    let measuredSpacedABC = Painter.measureString("ABC", font, 4, 1.5'f32)
    @assert(spacedABC.metrics.width > normalABC.metrics.width + 2.9)
    @assert(Math.isEqualEpsilon(measuredSpacedABC.width, spacedABC.metrics.width, 0.001))
    @assert(spacedABC.letterSpacing == 1.5'f32)

    let spaces = Painter.shapeRun("    ", font)
    let tab = Painter.shapeRun("\t", font)
    @assert(tab.glyphs.count == 1)
    @assert(tab.glyphs[0].isTab)
    @assert(!tab.hasInk)
    @assert(Math.isEqualEpsilon(tab.metrics.width, spaces.metrics.width, 0.001))

    var tab8 = Painter.shapeRun("\t", font, 8)
    @assert(tab8.metrics.width > tab.metrics.width)

    let msdfFont = Font.create(font.cache.typeFace, 32, .Msdf)
    let reshaped = Painter.shapeRunForFont(&shaped, msdfFont)
    @assert(reshaped.font == msdfFont)
    @assert(reshaped.glyphs.count == shaped.glyphs.count)
    @assert(reshaped.glyphs[0].glyphIndex == shaped.glyphs[0].glyphIndex)
    @assert(reshaped.glyphs[1].cluster == shaped.glyphs[1].cluster)

    let reshapedTab = Painter.shapeRunForFont(&tab8, msdfFont)
    @assert(reshapedTab.tabSize == 8)
    @assert(reshapedTab.glyphs[0].isTab)

    let largeFont = Font.create(font.cache.typeFace, 48, .Bitmap)
    var richText: RichString = "<b>A</b>\nA"
    var format:   RichStringFormat
    format.font.regular = font
    format.font.bold    = largeFont
    format.lineGap      = 3

    richText.compute()
    Painter.computeLayout({0, 0, 300, 300}, &richText, format)
    @assert(richText.boundRect.height >= largeFont.height + font.height + format.lineGap)
    @assert(richText.chunks[0].pos.y < richText.chunks[richText.chunks.count - 1].pos.y)

    var paragraphText:   RichString = "A\nB\nC"
    var paragraphFormat: RichStringFormat
    paragraphFormat.font.regular  = font
    paragraphFormat.lineGap       = 2
    paragraphFormat.paragraphGap  = 7
    paragraphFormat.minLineHeight = font.height + 6.0
    paragraphFormat.maxLines      = 2

    paragraphText.compute()
    Painter.computeLayout({0, 0, 300, 300}, &paragraphText, paragraphFormat)
    @assert(paragraphText.boundRect.height >= paragraphFormat.minLineHeight * 2 + cast(f32) paragraphFormat.lineGap + cast(f32) paragraphFormat.paragraphGap)

    var visibleChunks = 0
    for &chunk in paragraphText.chunks
    {
        if chunk.visible and !chunk.isEol do
            visibleChunks += 1
    }

    @assert(visibleChunks == 2)
    @assert(!paragraphText.chunks[paragraphText.chunks.count - 1].visible)

    var forced: RichString = "<b>A</b>"
    forced.compute()
    forced.chunks.clear()
    forced.compute(true)
    @assert(forced.chunks.count != 0)
    @assert(forced.chunks[0].fontStyle == .Bold)

    var lineBreaks: RichString = "A\r\nB\rC\nD"
    lineBreaks.compute()
    var eolCount = 0
    var spaceCount = 0
    for &chunk in lineBreaks.chunks
    {
        if chunk.isEol do
            eolCount += 1
        if chunk.isSpace do
            spaceCount += 1
    }

    @assert(eolCount == 3)
    @assert(spaceCount == 0)

    var styledUrl: RichString = "<url>A<b>B</b><p1>C</p></url>D"
    styledUrl.compute()
    @assert(styledUrl.hasUrl)
    @assert(styledUrl.chunks.count == 4)
    @assert(styledUrl.chunks[0].isUrl)
    @assert(styledUrl.chunks[1].isUrl)
    @assert(styledUrl.chunks[1].fontStyle == .Bold)
    @assert(styledUrl.chunks[2].isUrl)
    @assert(styledUrl.chunks[2].colorIdx == 1)
    @assert(!styledUrl.chunks[3].isUrl)

    var urlFormat: RichStringFormat
    urlFormat.font.regular = font
    urlFormat.font.bold    = largeFont
    Painter.computeLayout({0, 0, 300, 100}, &styledUrl, urlFormat)
    let hotChunk = styledUrl.getUrlChunkAt({styledUrl.chunks[1].pos.x + styledUrl.chunks[1].boundRect.width * 0.5, styledUrl.chunks[1].pos.y + styledUrl.chunks[1].boundRect.height * 0.5})
    @assert(hotChunk != null)
}
