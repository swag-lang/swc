#global if #command == Swag.CompilerCommand.Test

using Core

// Layout controls never enter fallback discovery or its miss cache, on any platform.
#test
{
    var cache: FontCache
    cache.setFallbackTypeFaces([expect fallbackTestFace(true)])
    let font = cache.createFont(expect fallbackTestFace(false), 19, .Bitmap, true, true)
    for c in [0'rune, '\t'rune, '\n'rune, '\r'rune, '\u007F'rune, '\u0085'rune, '\u009F'rune, '\U0010FFFF'rune]
    {
        let resolved = font.resolveRune(c)
        Swag.require(not isFontFallbackRune(c))
        Swag.require(resolved == font)
        Swag.require(font.fallbackFonts.count == 0)
    }

    Swag.require(isFontFallbackRune(' ') and isFontFallbackRune('\u2192'rune))
}

// Coverage, negative caching, policy replacement, UTF-8 byte clusters, spacing and cache identity.
#test
{
    var cache: FontCache
    let primary = expect fallbackTestFace(false)
    let symbols = expect fallbackTestFace(true)
    var empty: Array'(*TypeFace)
    cache.setFallbackTypeFaces(empty.toSlice(), false)
    let font = cache.createFont(primary, 24, .Bitmap)
    Swag.require(font.glyphIndex('\u2192'rune) == 0)
    Swag.require(font.resolveRune('\u2192'rune) == font)
    cache.setFallbackTypeFaces([primary, symbols], false)
    let fallback = font.resolveRune('\u2192'rune)
    Swag.require(fallback != font)
    Swag.require(fallback == font.resolveRune('\u2192'rune))
    Swag.require(font.resolveRune('A') == font)
    Swag.require(font.resolveRune('\U0010FFFF'rune) == font)
    Swag.require(font.getGlyphDesc('\u2192'rune) == fallback.getGlyphDescByIndex(fallback.glyphIndex('\u2192'rune)))

    let run = Painter.shapeRun("A\u2192V\U0001F680", font, letterSpacing: 2)
    Swag.require(run.glyphs.count == 4)
    Swag.require(run.glyphs[0].cluster == 0 and
                 run.glyphs[1].cluster == 1 and
                 run.glyphs[2].cluster == 4 and
                 run.glyphs[3].cluster == 5)
    Swag.require(run.glyphs[0].font == font and
                 run.glyphs[1].font == fallback and
                 run.glyphs[2].font == font and
                 run.glyphs[3].font == fallback)
    for glyph, index in run.glyphs
    {
        Swag.require(glyph.glyphIndex != 0)
        Swag.require(glyph.offsetX == (index == 0 ? 0 : 2))
    }

    let expected = Painter.measureString("A", font).width + Painter.measureString("V", font).width + Painter.measureString("\u2192\U0001F680", fallback).width + 6
    Swag.require(Math.isEqualEpsilon(run.metrics.width, expected, 0.001))
    let descriptors = Painter.glyphs("A\u2192V", font)
    Swag.require(Math.isEqualEpsilon(Painter.measureString(descriptors, font).width, Painter.measureString("A\u2192V", font).width, 0.001))
    Swag.require(Math.isEqualEpsilon(Painter.measureRune('\u2192'rune, font).x, Painter.measureString("\u2192", fallback).width, 0.001))
    let crossFace = Painter.shapeRun("A\U0001F680", font)
    let kerned    = Painter.shapeRun("AV", font)
    Swag.require(kerned.glyphs[1].offsetX != 0)
    Swag.require(crossFace.glyphs[1].offsetX == 0)
    var rich: RichString = "A\u2192V\nA\u2192V"
    rich.compute()
    var format: RichStringFormat
    format.font.regular = font
    Painter.computeLayout({0, 0, 300, 300}, &rich, format)
    Swag.require(rich.boundRect.height >= Painter.measureString("A\u2192V", font).height * 2)
    cache.setFallbackTypeFaces(empty.toSlice(), false)
    Swag.require(font.resolveRune('\u2192'rune) == font)
    Swag.require(Painter.shapeRun("", font).glyphs.isEmpty())
}

// Rebuilding at another size or render mode must preserve each typeface's glyph indices.
#test
{
    var cache: FontCache
    let primary = expect fallbackTestFace(false)
    cache.setFallbackTypeFaces([expect fallbackTestFace(true)], false)
    let font = cache.createFont(primary, 19, .Auto, true, true)
    let run  = Painter.shapeRun("A\u2192 V\t\U0001F680", font, 8, 1.5, 3)
    for mode in [FontRenderMode.Bitmap, FontRenderMode.Msdf]
    {
        let target  = cache.createFont(primary, 38, mode, true, true)
        let rebuilt = Painter.shapeRunForFont(&run, target)
        let direct  = Painter.shapeRun("A\u2192 V\t\U0001F680", target, 8, 1.5, 3)
        Swag.require(Math.isEqualEpsilon(rebuilt.metrics.width, direct.metrics.width, 0.001))
        for glyph, index in rebuilt.glyphs
        {
            Swag.require(glyph.glyphIndex == run.glyphs[index].glyphIndex)
            Swag.require(glyph.cluster == run.glyphs[index].cluster)
            Swag.require(glyph.font!.forceBold and glyph.font.forceItalic)
            Swag.require(glyph.font.mode == mode)
        }
    }

    for scale in [1.0'f32, 1.5'f32, 2.0'f32]
    {
        let drawFont = Painter.computeTextDrawInfo(font, 1, scale).drawFont
        let resolved = Painter.shapeRun("A\u2192 V\t\U0001F680", drawFont, 8, 1.5, 3)
        Swag.require(Math.isEqualEpsilon(Painter.measureStringSnapped(&run, deviceScale: scale), Painter.measureStringSnapped(&resolved, deviceScale: scale), 0.001))
    }
}
