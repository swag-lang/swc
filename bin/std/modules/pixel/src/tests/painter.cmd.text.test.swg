#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Command-stream goldens for text. Text is the only primitive that writes per-vertex texture
// coordinates, so these are the goldens that pin glyph atlas addressing. See
// [[Testing.assertGolden]].
//
// Glyph slots are packed in first-use order, so tests that shared a cache would record atlas
// coordinates depending on which one ran first. Each test owns its cache, which makes it
// reproducible whatever the test order without any arrangement between tests.
private func makeTextTestFont(cache: *FontCache, size: u32, mode: FontRenderMode)->*Font
{
    let face = expect loadTestTypeFace(getTestDataPath("segoeui.ttf"))!
    return cache.createFont(face, size, mode)
}

#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var cache:   FontCache
    let font = makeTextTestFont(&cache, 16, .Bitmap)

    painter.begin()
    painter.drawString(10, 10, "AB", font, Color.fromArgb(Argb.Black))
    painter.end()
    Testing.assertGolden(&painter, "text.bitmap.simple")
}

// Consecutive glyphs from one atlas must extend a single DrawTriangles batch rather than
// re-binding per glyph: four characters make one batch of twenty-four vertices.
#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var cache:   FontCache
    let font = makeTextTestFont(&cache, 16, .Bitmap)

    painter.begin()
    painter.drawString(10, 10, "AAAA", font, Color.fromArgb(Argb.Black))
    painter.end()
    Testing.assertGolden(&painter, "text.bitmap.batched")
}

// A space carries no ink and must not emit any geometry of its own.
#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var cache:   FontCache
    let font = makeTextTestFont(&cache, 16, .Bitmap)

    painter.begin()
    painter.drawString(10, 10, "A A", font, Color.fromArgb(Argb.Black))
    painter.end()
    Testing.assertGolden(&painter, "text.bitmap.space")
}

// An MSDF font goes through a different shader program, so it emits StartMsdfFont rather than
// StartFont and re-issues the texture0 setup.
#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var cache:   FontCache
    let font = makeTextTestFont(&cache, 16, .Msdf)

    painter.begin()
    painter.drawString(10, 10, "AB", font, Color.fromArgb(Argb.Black))
    painter.end()
    Testing.assertGolden(&painter, "text.msdf.simple")
}

// Switching program between two runs must re-emit the font setup commands.
#[Swag.TestTag("golden")]
#test
{
    var painter: Painter
    var cache:   FontCache
    let bitmap = makeTextTestFont(&cache, 16, .Bitmap)
    let msdf   = makeTextTestFont(&cache, 16, .Msdf)

    painter.begin()
    painter.drawString(10, 10, "A", bitmap, Color.fromArgb(Argb.Black))
    painter.drawString(10, 40, "A", msdf, Color.fromArgb(Argb.Black))
    painter.drawString(10, 70, "A", bitmap, Color.fromArgb(Argb.Black))
    painter.end()
    Testing.assertGolden(&painter, "text.program.switch")
}

// The shaped run retains this descriptor, so it needs addressable static storage. This test only reads it.
private var g_CapturedHeadingGlyph: GlyphDesc = {uv: {0, 0, 0.1640625, 0.1796875}, atlasIndex: 0, shiftX: -6, shiftY: 38, width: 42, height: 46}

// Pin scaled quad emission independently of glyph generation. The captured 36-pixel heading's
// right edge moved by one f32 step under contraction.
#test
{
    var cache: FontCache
    let font = makeTextTestFont(&cache, 36, .Msdf)
    var run  = Painter.shapeRun("H", font)
    run.glyphs[0].desc = &g_CapturedHeadingGlyph
    var painter: Painter
    painter.begin()
    painter.drawShapedRun(0, 0, &run, font, Brush{})
    painter.end()

    Swag.assert(painter.vertexBuffer.count == 6)
    Swag.assert(cast #bit (u32) painter.vertexBuffer[0].pos.x == 0xC0ACCCCC)
    Swag.assert(cast #bit (u32) painter.vertexBuffer[1].pos.x == 0x4201999A)
    Swag.assert(cast #bit (u32) painter.vertexBuffer[5].pos.x == 0x4201999A)
}
