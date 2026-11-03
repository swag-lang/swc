#global if #command == Swag.CompilerCommand.Test
using Swag, Core

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

    Swag.assert(painter.vertexBuffer.count == 6)
    Swag.assert(cast #bit (u32, painter.vertexBuffer[0].pos.x) == 0xC0ACCCCC)
    Swag.assert(cast #bit (u32, painter.vertexBuffer[1].pos.x) == 0x4201999A)
    Swag.assert(cast #bit (u32, painter.vertexBuffer[5].pos.x) == 0x4201999A)
}
