#global if #command == Swag.CompilerCommand.Test

using Swag, Core

private func countTextPixels(image: const *Image, left, right: s32)->u32
{
    var result: u32
    for y in image.height
    {
        for x in left until right where image.pixelColor(x, y).a > 32 do
            result += 1
    }

    return result
}

// Text and a positioned tspan use the configured typeface, baseline, size and inherited paint.
#test
{
    let fontPath = getTestDataPath("segoeui.ttf")
    var options: Svg.ParseOptions
    options.fontFileName = fontPath.toString()
    const Source = "<svg width='64' height='24'>" ++
                   "<text x='3' y='19' font-size='17' fill='white'>Hi" ++
                   "<tspan x='34' fill='#ff0000' font-weight='bold'>A</tspan></text></svg>"

    let drawing = expect Svg.Drawing.parse(Source, options)
    let image   = drawing.rasterize(64, 24, 1)
    Swag.assert(countTextPixels(&image, 2, 28) > 20)
    Swag.assert(countTextPixels(&image, 32, 52) > 20)

    var hasRed = false
    for y in image.height
    {
        for x in 32 until 52
        {
            let color = image.pixelColor(x, y)
            hasRed = hasRed or color.r > 128 and color.g < 32 and color.b < 32 and color.a > 32
        }
    }

    Swag.assert(hasRed)
}

// Returns the horizontal extent of the ink a text source produces.
private func textInkWidth(source: string, options: Svg.ParseOptions)->s32
{
    let drawing = expect Svg.Drawing.parse(source, options)
    let image   = drawing.rasterize(200, 32, 1)

    var minX = image.width
    var maxX = -1's32
    for y in image.height
    {
        for x in image.width where image.pixelColor(x, y).a > 32
        {
            minX = Math.min(minX, x)
            maxX = Math.max(maxX, x)
        }
    }

    return maxX < minX ? 0 : maxX - minX + 1
}

// `letter-spacing` and `word-spacing` widen a run by exactly what they state.
#test
{
    let fontPath = getTestDataPath("segoeui.ttf")
    var options: Svg.ParseOptions
    options.fontFileName = fontPath.toString()

    const Plain    = "<svg width='200' height='32'><text x='4' y='24' font-size='18' fill='white'>ABC DEF</text></svg>"
    const Spaced   = "<svg width='200' height='32'><text x='4' y='24' font-size='18' fill='white' letter-spacing='6'>ABC DEF</text></svg>"
    const Worded   = "<svg width='200' height='32'><text x='4' y='24' font-size='18' fill='white' word-spacing='20'>ABC DEF</text></svg>"
    const Normal   = "<svg width='200' height='32'><text x='4' y='24' font-size='18' fill='white' letter-spacing='normal'>ABC DEF</text></svg>"
    const Relative = "<svg width='200' height='32'><text x='4' y='24' font-size='18' fill='white' letter-spacing='0.5em'>ABC DEF</text></svg>"

    let plain = textInkWidth(Plain, options)
    Swag.assert(plain > 0)

    // Six units between each of the seven glyphs.
    Swag.assert(textInkWidth(Spaced, options) == plain + 6 * 6)

    // One blank, widened by twenty.
    Swag.assert(textInkWidth(Worded, options) == plain + 20)

    // `normal` is the absence of extra spacing, and `em` resolves against the font size.
    Swag.assert(textInkWidth(Normal, options) == plain)
    Swag.assert(textInkWidth(Relative, options) == plain + 6 * 9)
}

// A centred run is centred on the width its spacing produces, not on the width it would have had
// without it.
#test
{
    let fontPath = getTestDataPath("segoeui.ttf")
    var options: Svg.ParseOptions
    options.fontFileName = fontPath.toString()

    const Plain  = "<svg width='200' height='32'><text x='100' y='24' font-size='18' fill='white' text-anchor='middle'>ABC</text></svg>"
    const Spaced = "<svg width='200' height='32'><text x='100' y='24' font-size='18' fill='white' text-anchor='middle' letter-spacing='8'>ABC</text></svg>"

    Swag.assert(textInkWidth(Spaced, options) == textInkWidth(Plain, options) + 2 * 8)
}

// `font-family` selects one of the three configured typefaces: the serif and monospace names the
// table knows reach their own file, and everything else reaches the default one.
#test
{
    let fontPath = getTestDataPath("segoeui.ttf")
    var options: Svg.ParseOptions
    options.fontFileName = fontPath.toString()

    // A file that exists and is not a font, so a family that selects it fails to parse while a
    // family that does not select it is unaffected.
    let notAFont = getTestDataPath("THIRDPARTY.md")
    options.serifFontFileName = notAFont.toString()

    const Serif   = "<svg width='200' height='32'><text x='4' y='24' font-size='18' fill='white' font-family='Georgia, serif'>Hi</text></svg>"
    const Sans    = "<svg width='200' height='32'><text x='4' y='24' font-size='18' fill='white' font-family='Helvetica, sans-serif'>Hi</text></svg>"
    const Unknown = "<svg width='200' height='32'><text x='4' y='24' font-size='18' fill='white' font-family='Papyrus'>Hi</text></svg>"
    const Mono    = "<svg width='200' height='32'><text x='4' y='24' font-size='18' fill='white' font-family='Consolas, monospace'>Hi</text></svg>"

    let serif = catch Svg.Drawing.parse(Serif, options) as serifError
    discard serif
    Swag.assert(serifError != null)

    Swag.assert(textInkWidth(Sans, options) > 0)
    Swag.assert(textInkWidth(Unknown, options) > 0)

    // An empty selection, and one naming a file the host does not have, fall back to the default
    // typeface rather than failing the document.
    options.serifFontFileName = ""
    options.monoFontFileName  = "no-such-font-file.ttf"
    Swag.assert(textInkWidth(Serif, options) > 0)
    Swag.assert(textInkWidth(Mono, options) > 0)
}

// A drawing that both writes text and strokes a shape still rasterizes onto a usable alpha
// plane.
//
// The two need opposite things from the target: text writes its own alpha, and the overlap-safe
// pass an antialiased stroke goes through clears the alpha across the target to use it as
// scratch. Getting that choice wrong empties the alpha of the whole sheet, and the drawing
// rasterizes to nothing at all.
#test
{
    let fontPath = getTestDataPath("segoeui.ttf")
    var options: Svg.ParseOptions
    options.fontFileName = fontPath.toString()

    const Source = "<svg width='60' height='30'>" ++
                   "<rect x='4' y='4' width='52' height='22' fill='none' stroke='#ffffff' stroke-width='2'/>" ++
                   "<text x='10' y='21' font-size='14' fill='white'>Hi</text></svg>"

    let drawing = expect Svg.Drawing.parse(Source, options)
    let image   = drawing.rasterize(60, 30, 2)

    var opaque = 0's32
    for y in image.height
    {
        for x in image.width where image.pixelColor(x, y).a > 200 do
            opaque += 1
    }

    // The frame alone covers well over a hundred samples; an emptied alpha plane covers none.
    Swag.assert(opaque > 100)
}
