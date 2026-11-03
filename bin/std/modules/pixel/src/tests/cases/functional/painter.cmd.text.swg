#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// The shaped run retains this descriptor, so it needs addressable static storage. This test only reads it.
private var g_CapturedHeadingGlyph: GlyphDesc = {uv: Math.Rectangle{0, 0, 0.1640625, 0.1796875}, atlasIndex: 0, shiftX: -6, shiftY: 38, width: 42, height: 46}

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
    painter.drawShapedRun(0, 0, &run, font, {})
    painter.end()

    Swag.require(painter.vertexBuffer.count == 6)
    Swag.require(cast #bit (u32, painter.vertexBuffer[0].pos.x) == 0xC0ACCCCC)
    Swag.require(cast #bit (u32, painter.vertexBuffer[1].pos.x) == 0x4201999A)
    Swag.require(cast #bit (u32, painter.vertexBuffer[5].pos.x) == 0x4201999A)
}
