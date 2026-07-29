#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Command-stream goldens for text decorations, layout options and MSDF effects.
//
// As in [[painter.cmd.text.test.swg]], every test asks for its own font size: a glyph cache is
// shared process-wide and packs its atlas in first-use order, so two tests sharing a font would
// record atlas coordinates that depend on which one ran first. See [[Testing.assertGolden]].
private func makeEffectTestFont(size: u32, mode: FontRenderMode)->*Font
{
    var face: *TypeFace = undefined
    catch loadTestTypeFace(&face, getTestDataPath("segoeui.ttf")) as err
    @assert(err == null)
    return Font.create(face, size, mode)
}

// A decoration is a separate solid quad, so it lands in its own batch after the glyph batch.
#test
{
    var painter: Painter
    let font = makeEffectTestFont(31, .Bitmap)

    painter.begin()
    painter.drawString(10, 10, "AB", font, Color.fromArgb(Argb.Black), .Underline)
    painter.end()
    Testing.assertGolden(&painter, "texteffect.underline")
}

#test
{
    var painter: Painter
    let font = makeEffectTestFont(32, .Bitmap)

    painter.begin()
    painter.drawString(10, 10, "AB", font, Color.fromArgb(Argb.Black), .Strikeout)
    painter.end()
    Testing.assertGolden(&painter, "texteffect.strikeout")
}

// Zoom scales the quads without touching the atlas, so the bounds grow while the texture
// coordinates stay put.
#test
{
    var painter: Painter
    let font = makeEffectTestFont(33, .Bitmap)

    painter.begin()
    painter.drawString(10, 10, "AB", font, Color.fromArgb(Argb.Black), .None, 2.0)
    painter.end()
    Testing.assertGolden(&painter, "texteffect.zoom")
}

#test
{
    var painter: Painter
    let font = makeEffectTestFont(34, .Bitmap)

    painter.begin()
    painter.drawStringCenter(50, 50, "AB", font, Color.fromArgb(Argb.Black))
    painter.end()
    Testing.assertGolden(&painter, "texteffect.centered")
}

// A tab advances the pen without emitting ink, so the batch keeps two glyphs but widens.
#test
{
    var painter: Painter
    let font = makeEffectTestFont(35, .Bitmap)

    painter.begin()
    painter.drawString(10, 10, "A\tB", font, Color.fromArgb(Argb.Black))
    painter.end()
    Testing.assertGolden(&painter, "texteffect.tab")
}

// Every MSDF effect field must reach SetFontEffect. These goldens are the only place where the
// painter-to-shader mapping of an outline, a glow or a bevel is pinned.
#test
{
    var painter: Painter
    let font = makeEffectTestFont(36, .Msdf)
    var effect: TextEffect
    effect.outlineWidth = 0.2
    effect.outlineColor = Color.fromArgb(Argb.Blue)

    painter.begin()
    painter.drawString(10, 10, "AB", font, Color.fromArgb(Argb.Black), effect)
    painter.end()
    Testing.assertGolden(&painter, "texteffect.msdf.outline")
}

#test
{
    var painter: Painter
    let font = makeEffectTestFont(37, .Msdf)
    var effect: TextEffect
    effect.glowColor  = Color.fromArgb(Argb.Yellow)
    effect.glowOuter  = 0.6
    effect.glowOffset = 0.1

    painter.begin()
    painter.drawString(10, 10, "AB", font, Color.fromArgb(Argb.Black), effect)
    painter.end()
    Testing.assertGolden(&painter, "texteffect.msdf.glow")
}

#test
{
    var painter: Painter
    let font = makeEffectTestFont(38, .Msdf)
    var effect: TextEffect
    effect.faceDilate = 0.15
    effect.softness   = 0.05
    effect.bevel      = 0.4

    painter.begin()
    painter.drawString(10, 10, "AB", font, Color.fromArgb(Argb.Black), effect)
    painter.end()
    Testing.assertGolden(&painter, "texteffect.msdf.face")
}

// Two runs sharing one effect must emit SetFontEffect once: the painter caches the last one, and
// losing that cache means a uniform upload per run.
#test
{
    var painter: Painter
    let font = makeEffectTestFont(39, .Msdf)
    var effect: TextEffect
    effect.outlineWidth = 0.2

    painter.begin()
    painter.drawString(10, 10, "A", font, Color.fromArgb(Argb.Black), effect)
    painter.drawString(10, 40, "B", font, Color.fromArgb(Argb.Black), effect)
    painter.end()
    Testing.assertGolden(&painter, "texteffect.msdf.cached")
}
