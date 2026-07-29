#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Command-stream goldens for text. Text is the only primitive that writes per-vertex texture
// coordinates, so these are the goldens that pin glyph atlas addressing. See
// [[Testing.assertGolden]].
//
// A glyph cache is a process-wide shared resource keyed by typeface, size, render mode and
// spread, and glyph slots are packed in first-use order. Two tests sharing a cache would
// therefore see atlas coordinates that depend on which one ran first. Every test below asks for
// its own size so that it owns a private cache and stays reproducible whatever the test order.
private func makeTextTestFont(size: u32, mode: FontRenderMode)->*Font
{
    var face: *TypeFace = undefined
    catch loadTestTypeFace(&face, getTestDataPath("segoeui.ttf")) as err
    @assert(err == null)
    return Font.create(face, size, mode)
}

#test
{
    var painter: Painter
    let font = makeTextTestFont(21, .Bitmap)

    painter.begin()
    painter.drawString(10, 10, "AB", font, Color.fromArgb(Argb.Black))
    painter.end()
    Testing.assertGolden(&painter, "text.bitmap.simple")
}

// Consecutive glyphs from one atlas must extend a single DrawTriangles batch rather than
// re-binding per glyph: two characters make one batch of twelve vertices.
#test
{
    var painter: Painter
    let font = makeTextTestFont(22, .Bitmap)

    painter.begin()
    painter.drawString(10, 10, "AAAA", font, Color.fromArgb(Argb.Black))
    painter.end()
    Testing.assertGolden(&painter, "text.bitmap.batched")
}

// A space carries no ink and must not emit any geometry of its own.
#test
{
    var painter: Painter
    let font = makeTextTestFont(23, .Bitmap)

    painter.begin()
    painter.drawString(10, 10, "A A", font, Color.fromArgb(Argb.Black))
    painter.end()
    Testing.assertGolden(&painter, "text.bitmap.space")
}

// An MSDF font goes through a different shader program, so it emits StartMsdfFont rather than
// StartFont and re-issues the texture0 setup.
#test
{
    var painter: Painter
    let font = makeTextTestFont(24, .Msdf)

    painter.begin()
    painter.drawString(10, 10, "AB", font, Color.fromArgb(Argb.Black))
    painter.end()
    Testing.assertGolden(&painter, "text.msdf.simple")
}

// Switching program between two runs must re-emit the font setup commands.
#test
{
    var painter: Painter
    let bitmap = makeTextTestFont(25, .Bitmap)
    let msdf   = makeTextTestFont(26, .Msdf)

    painter.begin()
    painter.drawString(10, 10, "A", bitmap, Color.fromArgb(Argb.Black))
    painter.drawString(10, 40, "A", msdf, Color.fromArgb(Argb.Black))
    painter.drawString(10, 70, "A", bitmap, Color.fromArgb(Argb.Black))
    painter.end()
    Testing.assertGolden(&painter, "text.program.switch")
}
