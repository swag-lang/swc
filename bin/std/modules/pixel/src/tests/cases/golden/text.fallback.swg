#global if #command == Swag.CompilerCommand.Test
#global private

using Core

private func renderFallbackText(mode: FontRenderMode, explicitFaces: bool)->Image fail
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()
    let cache = renderer.fontCache()
    cache.setFallbackTypeFaces([try fallbackTestFace(true)], false)
    let font     = cache.createFont(try fallbackTestFace(false), 24, mode)
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
    else
    {
        painter.drawString(8, 24, "A\u2192V", font, Color.fromArgb(Argb.Black))
    }

    painter.unbindRenderTarget()
    painter.end()
    expect renderer.draw(&painter)
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
