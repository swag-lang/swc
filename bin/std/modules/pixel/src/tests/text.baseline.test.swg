#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Where a single line of text lands, and what it is level with.
//
// Two rules are pinned here, because both are invisible in one string and obvious in a row of
// them: a line stands as tall as the band its font reserves, whatever glyphs it happens to
// carry, and the middle a reader sees is the middle of the capitals, not the middle of that
// band. See [[Pixel.Font.opticalOffset]].

private func makeBaselineTestFont(cache: *FontCache)->*Font
{
    let face = expect loadTestTypeFace(getTestDataPath("segoeui.ttf"))!
    return cache.createFont(face, 20, .Bitmap)
}

private func layoutCentered(font: *Font, text: string, box: Math.Rectangle)->RichString
{
    var result: retval
    result.set(text)
    result.compute()

    var format: RichStringFormat
    format.font.regular  = font
    format.vertAlignment = .Center
    format.horzAlignment = .Left
    Painter.computeLayout(box, &result, format, 1)
    return result
}

// A face declares the height of its capitals, and it is smaller than its ascent.
#test
{
    var cache: FontCache
    let font = makeBaselineTestFont(&cache)

    Swag.assert(font.capHeight > 0)
    Swag.assert(font.capHeight < font.ascent)
}

// The middle a glyph is levelled with is the middle of the capitals: inside the band the
// letters really occupy, never the middle of the box, which a face with a generous ascender
// puts above the letters and a compact one below them.
#test
{
    var cache: FontCache
    let font = makeBaselineTestFont(&cache)

    // A line box centered on this point, and the baseline the glyphs then stand on.
    const Center = 50.0'f32
    let baseline   = Center - font.height * 0.5 + font.ascent
    let opticalMid = font.opticalTop(Center, 0)

    Swag.assert(opticalMid < baseline)
    Swag.assert(opticalMid > baseline - font.capHeight)
    Swag.assert(Math.abs(opticalMid - (baseline - font.capHeight * 0.5)) < 0.01)

    // The size is taken off around that middle, so a 16-pixel glyph straddles it.
    Swag.assert(Math.abs(font.opticalTop(Center, 16) - (opticalMid - 8)) < 0.01)
}

// Words centered in the same box land on the same line, whatever glyphs they carry. Measured
// on their own ink instead, the one with a descender would ride higher than the one without
// and the one with an accent lower, which is what put a menu bar on three baselines.
#test
{
    var cache: FontCache
    let font = makeBaselineTestFont(&cache)
    let box  = Math.Rectangle{0, 0, 400, 40}

    let plain    = layoutCentered(font, "Ficher", box)      // No descender, no accent.
    let descend  = layoutCentered(font, "Capture", box)     // Carries a descender.
    let accented = layoutCentered(font, "Édition", box)     // Carries an accent.

    Swag.assert(plain.boundRect.y == descend.boundRect.y)
    Swag.assert(plain.boundRect.y == accented.boundRect.y)
    Swag.assert(plain.boundRect.height == descend.boundRect.height)
    Swag.assert(plain.boundRect.height == accented.boundRect.height)
}

// The band a single line reserves is the font's, so the reported height does not shrink to the
// ink of a word that happens to have neither ascender nor descender.
#test
{
    var cache: FontCache
    let font = makeBaselineTestFont(&cache)
    let box  = Math.Rectangle{0, 0, 400, 40}

    let text = layoutCentered(font, "acemo", box)
    Swag.assert(text.boundRect.height >= font.height)
}
