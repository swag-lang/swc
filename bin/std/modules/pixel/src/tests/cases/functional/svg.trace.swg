#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func rasterizeTrace(image: const *Image)->Image
{
    let document = Svg.trace(image)
    let text     = document.toString()
    let drawing  = expect Svg.Drawing.parse(text.toString())
    return drawing.rasterize(image.width, image.height, 1)
}

// Tracing preserves the source's top-left row order even though Image storage is bottom-up.
#test
{
    var source = Image.create(2, 4, .RGBA8, [
        0'u8, 0, 255, 255, 0, 0, 255, 255,
        0, 0, 255, 255, 0, 0, 255, 255,
        255, 0, 0, 255, 255, 0, 0, 255,
        255, 0, 0, 255, 255, 0, 0, 255])

    let traced = rasterizeTrace(&source)
    let top    = traced.pixelColor(0, 0)
    let bottom = traced.pixelColor(0, 3)
    Swag.require(top.r == 255 and top.g == 0 and top.b == 0 and top.a == 255)
    Swag.require(bottom.r == 0 and bottom.g == 0 and bottom.b == 255 and bottom.a == 255)
}

// Gray and GrayAlpha formats are valid trace sources and read their logical color and alpha.
#test
{
    var gray       = Image.create(2, 2, .Gray8, [200'u8, 200, 200, 200])
    let grayResult = rasterizeTrace(&gray).pixelColor(0, 0)
    Swag.require(grayResult.r == grayResult.g and grayResult.g == grayResult.b)
    Swag.require(Math.abs(cast(s32, grayResult.r) - 200) <= 4 and grayResult.a > 0)

    var grayAlpha   = Image.create(2, 2, .GrayAlpha8, [160'u8, 128, 160, 128, 160, 128, 160, 128])
    let alphaResult = rasterizeTrace(&grayAlpha).pixelColor(0, 0)
    Swag.require(alphaResult.r == alphaResult.g and alphaResult.g == alphaResult.b)
    Swag.require(Math.abs(cast(s32, alphaResult.r) - 160) <= 4)
    Swag.require(alphaResult.a > 0 and alphaResult.a < 255)
}

// Wider and premultiplied inputs are converted to logical straight-alpha colors before grouping.
#test
{
    var wide = Image.create(2, 2, .Gray16)
    wide.fill(Color.fromRgb(255, 255, 255))
    Swag.require(rasterizeTrace(&wide).pixelColor(0, 0).r == 255)

    var premultiplied = Image.create(2, 2, .RGBA8, [128'u8, 0, 0, 128, 128, 0, 0, 128, 128, 0, 0, 128, 128, 0, 0, 128], .Premultiplied)
    let result        = rasterizeTrace(&premultiplied).pixelColor(0, 0)
    Swag.require(result.r >= 240 and result.g == 0 and result.b == 0)
    Swag.require(result.a > 0 and result.a < 255)
}
