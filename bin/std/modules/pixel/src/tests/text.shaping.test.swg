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
    Swag.assert(glyph.outline.count() != 0)
    Swag.assert(glyph.advance > 0)

    let text = expect face.buildStringOutline("AB", 32)
    Swag.assert(text.count() >= glyph.outline.count())
}

#test
{
    var cache: FontCache
    let font   = makeShapingTestFont(&cache)
    let text   = "A\u00E9"
    var shaped = Painter.shapeRun(text, font)

    Swag.assert(shaped.font == font)
    Swag.assert(shaped.glyphs.count == 2)
    Swag.assert(shaped.glyphs[0].cluster == 0)
    Swag.assert(shaped.glyphs[1].cluster == 1)
    Swag.assert(shaped.glyphs[0].glyphIndex == font.glyphIndex('A'))
    Swag.assert(shaped.glyphs[1].glyphIndex == font.glyphIndex('\u00E9'rune))
    Swag.assert(shaped.metrics.width > 0)
    Swag.assert(shaped.hasInk)
    Swag.assert(shaped.inkBounds.width > 0)
    Swag.assert(shaped.inkBounds.height > 0)
    Swag.assert(shaped.inkBounds.x <= shaped.metrics.width)

    let glyphA = font.getGlyphDescByIndex(font.glyphIndex('A'))
    Swag.assert(shaped.glyphs[0].desc == glyphA)
    Swag.assert(font.getGlyphDesc('A') == glyphA)

    let measured = Painter.measureString(text, font)
    Swag.assert(Math.isEqualEpsilon(measured.width, shaped.metrics.width, 0.001))
    Swag.assert(Math.isEqualEpsilon(measured.height, shaped.metrics.height, 0.001))

    let normalABC         = Painter.shapeRun("ABC", font)
    let spacedABC         = Painter.shapeRun("ABC", font, 4, 1.5'f32)
    let measuredSpacedABC = Painter.measureString("ABC", font, 4, 1.5'f32)
    Swag.assert(spacedABC.metrics.width > normalABC.metrics.width + 2.9)
    Swag.assert(Math.isEqualEpsilon(measuredSpacedABC.width, spacedABC.metrics.width, 0.001))
    Swag.assert(spacedABC.letterSpacing == 1.5'f32)

    let spaces = Painter.shapeRun("    ", font)
    let tab    = Painter.shapeRun("\t", font)
    Swag.assert(tab.glyphs.count == 1)
    Swag.assert(tab.glyphs[0].isTab)
    Swag.assert(!tab.hasInk)
    Swag.assert(Math.isEqualEpsilon(tab.metrics.width, spaces.metrics.width, 0.001))

    var tab8 = Painter.shapeRun("\t", font, 8)
    Swag.assert(tab8.metrics.width > tab.metrics.width)

    let msdfFont = font.owner.createFont(font.cache.typeFace, 32, .Msdf)
    let reshaped = Painter.shapeRunForFont(&shaped, msdfFont)
    Swag.assert(reshaped.font == msdfFont)
    Swag.assert(reshaped.glyphs.count == shaped.glyphs.count)
    Swag.assert(reshaped.glyphs[0].glyphIndex == shaped.glyphs[0].glyphIndex)
    Swag.assert(reshaped.glyphs[1].cluster == shaped.glyphs[1].cluster)

    let reshapedTab = Painter.shapeRunForFont(&tab8, msdfFont)
    Swag.assert(reshapedTab.tabSize == 8)
    Swag.assert(reshapedTab.glyphs[0].isTab)

    let largeFont            = font.owner.createFont(font.cache.typeFace, 48, .Bitmap)
    var richText: RichString = "<b>A</b>\nA"
    var format:   RichStringFormat
    format.font.regular = font
    format.font.bold    = largeFont
    format.lineGap      = 3

    richText.compute()
    Painter.computeLayout({0, 0, 300, 300}, &richText, format)
    Swag.assert(richText.boundRect.height >= largeFont.height + font.height + format.lineGap)
    Swag.assert(richText.chunks[0].pos.y < richText.chunks[richText.chunks.count - 1].pos.y)

    var paragraphText:   RichString = "A\nB\nC"
    var paragraphFormat: RichStringFormat
    paragraphFormat.font.regular  = font
    paragraphFormat.lineGap       = 2
    paragraphFormat.paragraphGap  = 7
    paragraphFormat.minLineHeight = font.height + 6.0
    paragraphFormat.maxLines      = 2

    paragraphText.compute()
    Painter.computeLayout({0, 0, 300, 300}, &paragraphText, paragraphFormat)
    Swag.assert(paragraphText.boundRect.height >= paragraphFormat.minLineHeight * 2 + cast(f32) paragraphFormat.lineGap + cast(f32) paragraphFormat.paragraphGap)

    var visibleChunks = 0
    for &chunk in paragraphText.chunks
    {
        if chunk.visible and !chunk.isEol do
            visibleChunks += 1
    }

    Swag.assert(visibleChunks == 2)
    Swag.assert(!paragraphText.chunks[paragraphText.chunks.count - 1].visible)

    var forced: RichString = "<b>A</b>"
    forced.compute()
    forced.chunks.clear()
    forced.compute(true)
    Swag.assert(forced.chunks.count != 0)
    Swag.assert(forced.chunks[0].fontStyle == .Bold)

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

    Swag.assert(eolCount == 3)
    Swag.assert(spaceCount == 0)

    var styledUrl: RichString = "<url>A<b>B</b><p1>C</p></url>D"
    styledUrl.compute()
    Swag.assert(styledUrl.hasUrl)
    Swag.assert(styledUrl.chunks.count == 4)
    Swag.assert(styledUrl.chunks[0].isUrl)
    Swag.assert(styledUrl.chunks[1].isUrl)
    Swag.assert(styledUrl.chunks[1].fontStyle == .Bold)
    Swag.assert(styledUrl.chunks[2].isUrl)
    Swag.assert(styledUrl.chunks[2].colorIdx == 1)
    Swag.assert(!styledUrl.chunks[3].isUrl)

    var urlFormat: RichStringFormat
    urlFormat.font.regular = font
    urlFormat.font.bold    = largeFont
    Painter.computeLayout({0, 0, 300, 100}, &styledUrl, urlFormat)
    let hotChunk = styledUrl.getUrlChunkAt({styledUrl.chunks[1].pos.x + styledUrl.chunks[1].boundRect.width * 0.5, styledUrl.chunks[1].pos.y + styledUrl.chunks[1].boundRect.height * 0.5})
    Swag.assert(hotChunk != null)
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
    for &c in text.chunks where c.slice.count > 20 do
        longChunk = c

    Swag.assert(longChunk != null)
    Swag.assert(longChunk.visible)

    // Every word survives the wrap, not only the one that could not break.
    var visibleWords = 0
    for &c in text.chunks where c.visible and !c.isSpace and !c.isEol do
        visibleWords += 1
    Swag.assert(visibleWords == 3)
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
    Swag.assert(text.chunks.count == 1)

    let room = full * 0.4
    Painter.computeLayout({0, 0, room, 200}, &text, format)
    Swag.assert(text.boundRect.width <= room)
    Swag.assert(text.chunks[0].shaped.glyphs.count < long.count)

    // The mark is the last thing drawn, and the text it was cut from is left intact so the next
    // layout starts from the whole run again.
    let glyphs = text.chunks[0].shaped.glyphs
    Swag.assert(glyphs.back().glyphIndex == font.glyphIndex('\u2026'rune))
    Swag.assert(text.chunks[0].slice == long)

    // The same run in a rectangle that holds it keeps every glyph and gains no mark.
    Painter.computeLayout({0, 0, full + 10, 200}, &text, format)
    Swag.assert(text.chunks[0].shaped.glyphs.count == long.count)

    // Without the flag the line still overflows, which is what the flag exists to change.
    var plainFormat = format
    plainFormat.flags.remove(.Ellipsis)
    Painter.computeLayout({0, 0, room, 200}, &text, plainFormat)
    Swag.assert(text.boundRect.width > room)
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
    Swag.assert(kept.slice == "alpha")
    Swag.assert(kept.shaped.glyphs.count == ("alpha").count + 1)

    let glyphs = kept.shaped.glyphs
    Swag.assert(glyphs.back().glyphIndex == font.glyphIndex('…'rune))
    Swag.assert(!text.chunks[text.chunks.count - 1].visible)

    // A budget the text stays under leaves every line alone.
    format.maxLines = 2
    Painter.computeLayout({0, 0, 400, 200}, &text, format)
    Swag.assert(text.chunks[0].shaped.glyphs.count == ("alpha").count)
    Swag.assert(text.chunks[text.chunks.count - 1].visible)
}

// A style boundary is not a place to break a line.
//
// Markup splits one word into several chunks — '<url>here</url>.' is three of them — and a wrap
// that fell between two of them put the closing period alone on the next line. The whole word
// moves down together instead.
#test
{
    var cache: FontCache
    let font = makeShapingTestFont(&cache)

    var format: RichStringFormat
    format.font.regular  = font
    format.horzAlignment = .Left
    format.flags         |= .WordWrap

    var text: RichString = "alpha <url>beta</url>."
    text.compute()

    // Room for 'alpha beta' and not for the period after it, which is where the break used to go.
    let room = Painter.measureStringSnapped("alpha ", font) + Painter.measureStringSnapped("beta", font) + 1
    Painter.computeLayout({0, 0, room, 400}, &text, format)

    var alphaChunk, betaChunk, dotChunk: #null *RichChunk
    for &c in text.chunks
    {
        switch c.slice
        {
        case "alpha": alphaChunk = c
        case "beta":  betaChunk = c
        case ".":     dotChunk = c
        }
    }

    Swag.assert(alphaChunk != null and betaChunk != null and dotChunk != null)
    Swag.assert(alphaChunk.visible and betaChunk.visible and dotChunk.visible)

    // The period stays on the line of the run it closes, and that run left the first line.
    Swag.assert(dotChunk.pos.y == betaChunk.pos.y)
    Swag.assert(dotChunk.pos.x > betaChunk.pos.x)
    Swag.assert(betaChunk.pos.y > alphaChunk.pos.y)
}
