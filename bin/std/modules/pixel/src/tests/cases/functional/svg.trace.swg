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
        0_u8, 0, 255, 255, 0, 0, 255, 255,
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
    var gray       = Image.create(2, 2, .Gray8, [200_u8, 200, 200, 200])
    let grayResult = rasterizeTrace(&gray).pixelColor(0, 0)
    Swag.require(grayResult.r == grayResult.g and grayResult.g == grayResult.b)
    Swag.require(Math.abs(cast(s32, grayResult.r) - 200) <= 4 and grayResult.a > 0)

    var grayAlpha   = Image.create(2, 2, .GrayAlpha8, [160_u8, 128, 160, 128, 160, 128, 160, 128])
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

    var premultiplied = Image.create(2, 2, .RGBA8, [128_u8, 0, 0, 128, 128, 0, 0, 128, 128, 0, 0, 128, 128, 0, 0, 128], .Premultiplied)
    let result        = rasterizeTrace(&premultiplied).pixelColor(0, 0)
    Swag.require(result.r >= 240 and result.g == 0 and result.b == 0)
    Swag.require(result.a > 0 and result.a < 255)
}

// Color bounds keep both the antialiased halo and shared high-alpha pixels.
#test
{
    const Width  = 32
    const Height = 16
    var pixels: [Width * Height * 4] u8
    func paint(pixels: [..] u8, left, top, width, height: s32, color: Color)
    {
        for dy in height
        {
            let row = (Height - 1 - top - dy) * Width + left
            for dx in width
            {
                let offset = (row + dx) * 4
                pixels[offset + 0] = color.r
                pixels[offset + 1] = color.g
                pixels[offset + 2] = color.b
                pixels[offset + 3] = color.a
            }
        }
    }

    paint(pixels, 0, 0, 4, 8, Color.fromArgb(220_u8, 220_u8, 50_u8, 30_u8))
    paint(pixels, 4, 0, 4, 8, Color.fromArgb(200_u8, 220_u8, 50_u8, 30_u8))
    paint(pixels, 8, 1, 1, 6, Color.fromArgb(112_u8, 220_u8, 50_u8, 30_u8))
    paint(pixels, 27, 11, 5, 5, Color.fromArgb(240_u8, 25_u8, 70_u8, 190_u8))
    paint(pixels, 13, 5, 6, 6, Color.fromArgb(145_u8, 45_u8, 180_u8, 50_u8))

    let source   = Image.create(Width, Height, .RGBA8, pixels)
    let document = Svg.trace(&source, {tolerance: 0, threshold: 160})
    let text     = document.toString()
    Swag.require(text.contains("fill=\"#DC321E\" fill-opacity=\"0.824\""))
    Swag.require(text.contains("fill=\"#1946BE\" fill-opacity=\"0.941\""))

    let drawing = expect Svg.Drawing.parse(text.toString())
    let image   = drawing.rasterize(Width, Height, 4)
    let red     = image.pixelColor(2, 3)
    let edge    = image.pixelColor(8, 4)
    let blue    = image.pixelColor(30, 14)
    let shared  = image.pixelColor(15, 7)
    Swag.require(red.r > red.b and red.a > 200 and red.a < 220)
    Swag.require(edge.a > 0 and edge.a < red.a)
    Swag.require(blue.b > blue.r and blue.a > 230)
    Swag.require(shared.b > shared.r and shared.a > blue.a)
    Swag.require(image.pixelColor(23, 8).a == 0)

    let empty = Svg.trace(&source, {threshold: 255})
    Swag.require(empty.bodyText().isEmpty())
}
