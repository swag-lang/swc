#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// A source or rasterizer edit must regenerate the shipped derivatives. Compare the
// decoded pixels, including transparent RGB, rather than PNG encoder choices.
func checkThemeRaster(source: const [..] u8, bytes: const [..] u8, size: s32, units: f32, limit: s32)
{
    let drawing = expect Svg.Drawing.parse(Swag.makeString(source.buffer, source.count))
    let width   = cast(s32, Math.round(drawing.width * cast(f32, size) / units))
    let height  = cast(s32, Math.round(drawing.height * cast(f32, size) / units))
    var samples = 4'u8
    while samples > 1 and width * cast(s32, samples) > limit do
        samples /= 2

    let expected = drawing.rasterize(width, height, samples)
    let actual   = decodeThemeRaster(bytes)
    Swag.assert(actual.width == expected.width and actual.height == expected.height)
    Swag.assert(actual.byteCount == expected.byteCount)
    Swag.assert(actual.pixelFormat == expected.pixelFormat and actual.alphaMode == expected.alphaMode)
    #static if #cfg != "release" do
        Swag.assert(Memory.compare(actual.pixels.storage(), expected.pixels.storage(), actual.byteCount) == 0)
    else
    {
        // DevMode generates the assets, matching the GUI goldens. Release floating-point
        // code can round coverage one level differently; all other channels still agree.
        for i in actual.byteCount
        {
            let tolerance = i % 4 == 3 ? 1 : 0
            Swag.assert(Math.abs(cast(s32, actual.pixels[i]) - cast(s32, expected.pixels[i])) <= tolerance)
        }
    }
}

#test
{
    const Source = #include("../theme/icons.svg")
    for size in [16, 20, 24, 28, 32, 40, 48] do
        checkThemeRaster(Source, unwrap themeIconRaster(size), size, 24, 8192)
    Swag.assert(themeIconRaster(37) == null)
}

#test
{
    const Source = #include("../theme/widgets.svg")
    for scale in [1, 2] do
        checkThemeRaster(Source, unwrap themeWidgetRaster(scale), scale, 1, 4096)
    Swag.assert(themeWidgetRaster(3) == null)
}

// The live stock cache uses the embedded sizes and still rasterizes unusual requests.
#test
{
    var host: Testing.HeadlessHost
    host.setup(80, 60)
    let atlas   = unwrap host.theme.res.icons.atlas
    let baked   = atlas.image(32)
    let decoded = decodeThemeRaster(unwrap themeIconRaster(32))
    Swag.assert(baked.byteCount == decoded.byteCount)
    Swag.assert(Memory.compare(baked.pixels.storage(), decoded.pixels.storage(), baked.byteCount) == 0)
    let unusual = atlas.image(37)
    Swag.assert(unusual.width == 8 * 37 and unusual.height == 11 * 37)

    var custom: IconAtlas
    custom.embedded = true
    expect custom.setup("<svg width='24' height='24'><rect width='24' height='24' fill='red'/></svg>")
    let red = custom.image(32)
    Swag.assert(red.width == 32 and red.height == 32)
    Swag.assert(red.pixelColor(16, 16).argb == 0xFFFF0000)
}
