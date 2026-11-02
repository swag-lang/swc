#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Accumulated advances must use the same rounding with and without automatic FMA contraction.
// A one-ULP drift here can select another quarter-pixel glyph several characters later.
#test
{
    var info: TextDrawInfo
    info.scale = 0.8
    let first = Painter.advanceTextX(8.099998474, 0, 9, info)
    let second = Painter.advanceTextX(first.rightX, 0, 9, info)
    Swag.assert(first.glyphX == 8.099998474'f32)
    Swag.assert(first.rightX == 15.299999237'f32)
    Swag.assert(second.rightX == 22.5'f32)

    let offset = Painter.advanceTextX(-8.099998474, -9, -9, info)
    Swag.assert(offset.glyphX == -15.299999237'f32)
    Swag.assert(offset.rightX == -22.5'f32)
}

func assertSnappedGlyphPhase(left, origin: f32, phase: u32)
{
    var cache: FontCache
    let face = expect TypeFace.load(getTestDataPath("segoeui.ttf"))
    let font = cache.createFont(face, 12, .Bitmap)
    let drawnFont = Font.resolveDrawFont(font, 15)

    var painter: Painter
    painter.setContentScale(1.25)
    painter.begin()
    painter.translateTransform(origin, 0)
    painter.drawString(left, 0, "4", font, Color.fromArgb(Argb.Black))
    painter.end()

    let expected = drawnFont.cache.getGlyphDescByIndex(drawnFont.glyphIndex('4'), phase)
    Swag.assert(painter.vertexBuffer.count == 6)
    Swag.assert(painter.vertexBuffer[0].uv == Math.Vector2{expected.uv.x, expected.uv.y})
}

// Adjacent representable positions straddle a quarter-pixel midpoint after translation and
// 125% scaling. Quantization must not move the lower position onto that midpoint first.
#test
{
    assertSnappedGlyphPhase(8.099998474, 67, 3)
    assertSnappedGlyphPhase(8.100001335, 67, 0)
    assertSnappedGlyphPhase(-8.099998474, -67, 1)
    assertSnappedGlyphPhase(-8.100001335, -67, 0)
}
