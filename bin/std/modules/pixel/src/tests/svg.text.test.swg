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
