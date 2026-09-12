#global if #command == Swag.CompilerCommand.Test

using Core

// Reuse our own fixture's outlines with a deliberately small Unicode map. No test depends
// on an optional installed font. The supplementary rune deliberately maps to V so a mistaken
// cross-face A/V kerning lookup is observable, independently of any system font's coverage.
private func fallbackTestFace(symbols: bool)->*TypeFace? fail
{
    let original = try TypeFace.load(getTestDataPath("segoeui.ttf"))
    var bytes    = try File.readAllBytes(getTestDataPath("segoeui.ttf"))
    var reader   = ByteStream.openRead(bytes.toSlice())
    reader.setPosition(4)
    let tables            = try reader.readBigEndian'u16()
    var directory         = 0'u64
    var horizontalMetrics = 0'u32
    for index in tables
    {
        let offset = 12 + cast(u64) index * 16
        reader.setPosition(offset)
        let tag = try reader.readBigEndian'u32()
        if tag == 0x636D6170
        {
            directory = offset
        }
        elif tag == 0x68686561
        {
            reader.setPosition(offset + 8)
            horizontalMetrics = try reader.readBigEndian'u32()
        }
    }

    Swag.assert(directory != 0)

    let offset = bytes.count
    var writer = ByteStream.openWrite(&bytes)
    writer.setPosition(offset)
    writer.writeBigEndian(0'u16)
    writer.writeBigEndian(1'u16)
    writer.writeBigEndian(3'u16)
    writer.writeBigEndian(10'u16)
    writer.writeBigEndian(12'u32)
    writer.writeBigEndian(12'u16)
    writer.writeBigEndian(0'u16)
    let count = symbols ? 5'u32 : 3'u32
    writer.writeBigEndian(16'u32 + count * 12)
    writer.writeBigEndian(0'u32)
    writer.writeBigEndian(count)
    const codes = [' 'rune, 'A'rune, 'V'rune, '\u2192'rune, '\U0001F680'rune]
    for index in count
    {
        let code  = codes[index]
        let glyph = original.face.glyphIndex(code == '\U0001F680'rune ? 'V'rune : code)
        Swag.assert(glyph != 0)
        writer.writeBigEndian(cast(u32) code)
        writer.writeBigEndian(cast(u32) code)
        writer.writeBigEndian(glyph)
    }

    let length = bytes.count - offset
    writer.setPosition(directory + 8)
    writer.writeBigEndian(cast(u32) offset)
    writer.writeBigEndian(cast(u32) length)
    if not symbols
    {
        // Make a short primary line box: fallback ink must still fit, and drawing a fallback
        // face explicitly needs a different top coordinate to retain the primary baseline.
        Swag.assert(horizontalMetrics != 0)
        writer.setPosition(horizontalMetrics + 4)
        writer.writeBigEndian(800'u16)
        writer.writeBigEndian(0xFF9C'u16)     // Signed descender: -100 font units.
    }

    return try TypeFace.create(symbols ? "pixel-fallback-symbol-fixture" : "pixel-fallback-primary-fixture", bytes.toSlice())
}

// Coverage, negative caching, policy replacement, UTF-8 byte clusters, spacing and cache identity.
#test
{
    var cache: FontCache
    let primary = (expect fallbackTestFace(false)!)
    let symbols = (expect fallbackTestFace(true)!)
    var empty: Array'(*TypeFace)
    cache.setFallbackTypeFaces(empty.toSlice(), false)
    let font = cache.createFont(primary, 24, .Bitmap)
    Swag.assert(font.glyphIndex('\u2192'rune) == 0)
    Swag.assert(font.resolveRune('\u2192'rune) == font)
    cache.setFallbackTypeFaces([primary, symbols], false)
    let fallback = font.resolveRune('\u2192'rune)
    Swag.assert(fallback != font)
    Swag.assert(fallback == font.resolveRune('\u2192'rune))
    Swag.assert(font.resolveRune('A') == font)
    Swag.assert(font.resolveRune('\U0010FFFF'rune) == font)
    Swag.assert(font.getGlyphDesc('\u2192'rune) == fallback.getGlyphDescByIndex(fallback.glyphIndex('\u2192'rune)))

    let run = Painter.shapeRun("A\u2192V\U0001F680", font, letterSpacing: 2)
    Swag.assert(run.glyphs.count == 4)
    Swag.assert(run.glyphs[0].cluster == 0 and run.glyphs[1].cluster == 1 and run.glyphs[2].cluster == 4 and run.glyphs[3].cluster == 5)
    Swag.assert(run.glyphs[0].font == font and run.glyphs[1].font == fallback and run.glyphs[2].font == font and run.glyphs[3].font == fallback)
    for glyph, index in run.glyphs
    {
        Swag.assert(glyph.glyphIndex != 0)
        Swag.assert(glyph.offsetX == (index == 0 ? 0 : 2))
    }

    let expected = Painter.measureString("A", font).width + Painter.measureString("V", font).width + Painter.measureString("\u2192\U0001F680", fallback).width + 6
    Swag.assert(Math.isEqualEpsilon(run.metrics.width, expected, 0.001))
    let descriptors = Painter.glyphs("A\u2192V", font)
    Swag.assert(Math.isEqualEpsilon(Painter.measureString(descriptors, font).width, Painter.measureString("A\u2192V", font).width, 0.001))
    Swag.assert(Math.isEqualEpsilon(Painter.measureRune('\u2192'rune, font).x, Painter.measureString("\u2192", fallback).width, 0.001))
    let crossFace = Painter.shapeRun("A\U0001F680", font)
    let kerned    = Painter.shapeRun("AV", font)
    Swag.assert(kerned.glyphs[1].offsetX != 0)
    Swag.assert(crossFace.glyphs[1].offsetX == 0)
    var rich: RichString = "A\u2192V\nA\u2192V"
    rich.compute()
    var format: RichStringFormat
    format.font.regular = font
    Painter.computeLayout({0, 0, 300, 300}, &rich, format)
    Swag.assert(rich.boundRect.height >= Painter.measureString("A\u2192V", font).height * 2)
    cache.setFallbackTypeFaces(empty.toSlice(), false)
    Swag.assert(font.resolveRune('\u2192'rune) == font)
    Swag.assert(Painter.shapeRun("", font).glyphs.isEmpty())
}

// Rebuilding at another size or render mode must preserve each typeface's glyph indices.
#test
{
    var cache: FontCache
    let primary = (expect fallbackTestFace(false)!)
    cache.setFallbackTypeFaces([(expect fallbackTestFace(true)!)], false)
    let font = cache.createFont(primary, 19, .Auto, true, true)
    let run  = Painter.shapeRun("A\u2192 V\t\U0001F680", font, 8, 1.5, 3)
    for mode in [FontRenderMode.Bitmap, FontRenderMode.Msdf]
    {
        let target  = cache.createFont(primary, 38, mode, true, true)
        let rebuilt = Painter.shapeRunForFont(&run, target)
        let direct  = Painter.shapeRun("A\u2192 V\t\U0001F680", target, 8, 1.5, 3)
        Swag.assert(Math.isEqualEpsilon(rebuilt.metrics.width, direct.metrics.width, 0.001))
        for glyph, index in rebuilt.glyphs
        {
            Swag.assert(glyph.glyphIndex == run.glyphs[index].glyphIndex)
            Swag.assert(glyph.cluster == run.glyphs[index].cluster)
            Swag.assert(glyph.font!.forceBold and glyph.font!.forceItalic)
            Swag.assert(glyph.font!.mode == mode)
        }
    }

    for scale in [1.0'f32, 1.5'f32, 2.0'f32]
    {
        let drawFont = Painter.computeTextDrawInfo(font, 1, scale).drawFont
        let resolved = Painter.shapeRun("A\u2192 V\t\U0001F680", drawFont, 8, 1.5, 3)
        Swag.assert(Math.isEqualEpsilon(Painter.measureStringSnapped(&run, deviceScale: scale), Painter.measureStringSnapped(&resolved, deviceScale: scale), 0.001))
    }
}

private func renderFallbackText(mode: FontRenderMode, explicitFaces: bool)->Image fail
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()
    let cache = renderer.fontCache()
    cache.setFallbackTypeFaces([(try fallbackTestFace(true)!)], false)
    let font     = cache.createFont((try fallbackTestFace(false)!), 24, mode)
    let fallback = font.resolveRune('\u2192'rune)
    var target   = renderer.createRenderTarget(160, 64)
    defer renderer.deleteRenderTarget(&target)
    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.clear(Color.fromArgb(Argb.White))
    if explicitFaces
    {
        painter.drawString(8, 24, "A", font, Color.fromArgb(Argb.Black))
        let x = 8 + Painter.measureStringSnapped("A", font)
        painter.drawString(x, 24 + font.ascent - fallback.ascent, "\u2192", fallback, Color.fromArgb(Argb.Black))
        painter.drawString(x + Painter.measureStringSnapped("\u2192", fallback), 24, "V", font, Color.fromArgb(Argb.Black))
    }
    else do
        painter.drawString(8, 24, "A\u2192V", font, Color.fromArgb(Argb.Black))
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)
    return renderer.readRenderTarget(&target, 0, 0, 160, 64)
}

// Different atlas contents expose an accidental binding to the primary font. Compare both
// bitmap and MSDF against explicitly selected faces, then keep a visible bitmap regression.
#[Swag.TestTag("golden")]
#test
{
    for mode in [FontRenderMode.Bitmap, FontRenderMode.Msdf]
    {
        var actual   = expect renderFallbackText(mode, false)
        let expected = expect renderFallbackText(mode, true)
        Testing.assertImagesNear(&expected, &actual, "text.fallback.explicit")
        if mode == .Bitmap do
            Testing.assertImageGolden(&actual, "text.fallback")
    }
}

#test
{
    #static if #os == Swag.TargetOs.Windows
    {
        var cache: FontCache
        let font  = cache.createFont((expect fallbackTestFace(false)!), 19, .Bitmap, true, true)
        let arrow = font.resolveRune('\u2192'rune)
        Swag.assert(arrow != font and arrow.glyphIndex('\u2192'rune) != 0)
        Swag.assert(arrow.cache.typeFace.isBold() or arrow.cache.typeFace.forceBold or arrow.forceBold)
        Swag.assert(arrow.cache.typeFace.isItalic() or arrow.cache.typeFace.forceItalic or arrow.forceItalic)
    }
}
