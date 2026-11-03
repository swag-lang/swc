#global if #command == Swag.CompilerCommand.Test

using Swag, Core

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
