#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func makeShapingTestFont(cache: *FontCache)->*Font
{
    let face = expect loadTestTypeFace(getTestDataPath("segoeui.ttf"))!
    return cache.createFont(face, 32, .Bitmap)
}

// Typeface outline builders return complete values, including the rune advance.
#test
{
    let face  = expect loadTestTypeFace(getTestDataPath("segoeui.ttf"))!
    let glyph = expect face.buildRuneOutline('A', 32)
    @assert(glyph.outline.count() != 0)
    @assert(glyph.advance > 0)

    let text = expect face.buildStringOutline("AB", 32)
    @assert(text.count() >= glyph.outline.count())
}

#test
{
    var cache: FontCache
    let font   = makeShapingTestFont(&cache)
    let text   = "A\u00E9"
    var shaped = Painter.shapeRun(text, font)

    @assert(shaped.font == font)
    @assert(shaped.glyphs.count == 2)
    @assert(shaped.glyphs[0].cluster == 0)
    @assert(shaped.glyphs[1].cluster == 1)
    @assert(shaped.glyphs[0].glyphIndex == font.glyphIndex('A'))
    @assert(shaped.glyphs[1].glyphIndex == font.glyphIndex('\u00E9'rune))
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

    let normalABC         = Painter.shapeRun("ABC", font)
    let spacedABC         = Painter.shapeRun("ABC", font, 4, 1.5'f32)
    let measuredSpacedABC = Painter.measureString("ABC", font, 4, 1.5'f32)
    @assert(spacedABC.metrics.width > normalABC.metrics.width + 2.9)
    @assert(Math.isEqualEpsilon(measuredSpacedABC.width, spacedABC.metrics.width, 0.001))
    @assert(spacedABC.letterSpacing == 1.5'f32)

    let spaces = Painter.shapeRun("    ", font)
    let tab    = Painter.shapeRun("\t", font)
    @assert(tab.glyphs.count == 1)
    @assert(tab.glyphs[0].isTab)
    @assert(!tab.hasInk)
    @assert(Math.isEqualEpsilon(tab.metrics.width, spaces.metrics.width, 0.001))

    var tab8 = Painter.shapeRun("\t", font, 8)
    @assert(tab8.metrics.width > tab.metrics.width)

    let msdfFont = font.owner.createFont(font.cache.typeFace, 32, .Msdf)
    let reshaped = Painter.shapeRunForFont(&shaped, msdfFont)
    @assert(reshaped.font == msdfFont)
    @assert(reshaped.glyphs.count == shaped.glyphs.count)
    @assert(reshaped.glyphs[0].glyphIndex == shaped.glyphs[0].glyphIndex)
    @assert(reshaped.glyphs[1].cluster == shaped.glyphs[1].cluster)

    let reshapedTab = Painter.shapeRunForFont(&tab8, msdfFont)
    @assert(reshapedTab.tabSize == 8)
    @assert(reshapedTab.glyphs[0].isTab)

    let largeFont            = font.owner.createFont(font.cache.typeFace, 48, .Bitmap)
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
    var eolCount   = 0
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

// A run too wide to break keeps the line it opens, instead of being taken for a trailing space.
//
// Closing a line drops the space it would have ended on, and the flag saying so was only advanced
// on the chunks that reached the bottom of the loop. A chunk that wrapped left it describing the
// chunk before last, so the next wrap read a stale `true` and cut the run off the line it had just
// been given: a path or a URL standing between two spaces disappeared from the layout entirely.
#test
{
    var cache: FontCache
    let font = makeShapingTestFont(&cache)

    var format: RichStringFormat
    format.font.regular  = font
    format.horzAlignment = .Left
    format.flags         |= .WordWrap

    var text: RichString = "over abcdefghijklmnopqrstuvwxyz0123456789 now"
    text.compute()

    // Narrow enough that the middle run has to take a line of its own, and too narrow for it.
    Painter.computeLayout({0, 0, 120, 400}, &text, format)

    var longChunk: #null *RichChunk
    for &c in text.chunks where @countof(c.slice) > 20 do
        longChunk = c

    @assert(longChunk != null)
    @assert(longChunk.visible)

    // Every word survives the wrap, not only the one that could not break.
    var visibleWords = 0
    for &c in text.chunks where c.visible and !c.isSpace and !c.isEol do
        visibleWords += 1
    @assert(visibleWords == 3)
}

// A line wider than its rectangle is cut and finished with an ellipsis.
//
// Wrapping cannot break a run carrying no space — a path, a URL — so that run decided the width
// of everything measured against it, and a box sized from the measurement grew as wide as the
// text was long.
#test
{
    var cache: FontCache
    let font = makeShapingTestFont(&cache)

    var format: RichStringFormat
    format.font.regular  = font
    format.horzAlignment = .Left
    format.flags         |= .Ellipsis

    // One unbreakable run, laid out in a rectangle a fraction of its own width.
    let long = "abcdefghijklmnopqrstuvwxyz0123456789"
    let full = Painter.measureStringSnapped(long, font)

    var text: RichString = long
    text.compute()
    @assert(text.chunks.count == 1)

    let room = full * 0.4
    Painter.computeLayout({0, 0, room, 200}, &text, format)
    @assert(text.boundRect.width <= room)
    @assert(text.chunks[0].shaped.glyphs.count < @countof(long))

    // The mark is the last thing drawn, and the text it was cut from is left intact so the next
    // layout starts from the whole run again.
    let glyphs = text.chunks[0].shaped.glyphs
    @assert(glyphs.back().glyphIndex == font.glyphIndex('\u2026'rune))
    @assert(text.chunks[0].slice == long)

    // The same run in a rectangle that holds it keeps every glyph and gains no mark.
    Painter.computeLayout({0, 0, full + 10, 200}, &text, format)
    @assert(text.chunks[0].shaped.glyphs.count == @countof(long))

    // Without the flag the line still overflows, which is what the flag exists to change.
    var plainFormat = format
    plainFormat.flags.remove(.Ellipsis)
    Painter.computeLayout({0, 0, room, 200}, &text, plainFormat)
    @assert(text.boundRect.width > room)
}

// The line a budget stops on is marked too, so a text cut from below reports it.
//
// A cap on the line count used to drop the rest in silence, which reads as a paragraph that
// simply ended there. A box capped by its height — a tool tip — is what this exists for.
#test
{
    var cache: FontCache
    let font = makeShapingTestFont(&cache)

    var format: RichStringFormat
    format.font.regular  = font
    format.horzAlignment = .Left
    format.flags         |= .Ellipsis
    format.maxLines      = 1

    // Two authored lines in a rectangle wide enough for either, so nothing but the budget can
    // shorten the first one.
    var text: RichString = "alpha\nbeta"
    text.compute()
    Painter.computeLayout({0, 0, 400, 200}, &text, format)

    let kept = text.chunks[0]
    @assert(kept.slice == "alpha")
    @assert(kept.shaped.glyphs.count == @countof("alpha") + 1)

    let glyphs = kept.shaped.glyphs
    @assert(glyphs.back().glyphIndex == font.glyphIndex('…'rune))
    @assert(!text.chunks[text.chunks.count - 1].visible)

    // A budget the text stays under leaves every line alone.
    format.maxLines = 2
    Painter.computeLayout({0, 0, 400, 200}, &text, format)
    @assert(text.chunks[0].shaped.glyphs.count == @countof("alpha"))
    @assert(text.chunks[text.chunks.count - 1].visible)
}
