#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

const SampleText   = "Manuscript figure"
const SampleWidth  = 640's32
const SampleHeight = 200's32

// Draws one line of text at a small bitmap size and at two sizes past the distance-field threshold.
struct DrawingOrderWnd
{
    using wnd: Wnd
    fonts:     Array'(*Font)
    text:      string = SampleText
}

impl IWnd for DrawingOrderWnd
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        if evt.kind != .Content do
            return

        let painter = evt.paintContext.painter
        painter.fillRect(.clientRect(), Argb.White)

        // Fractional pens keep the glyph quads off the texel grid, so every edge pixel is shaded
        // from an interpolated atlas position rather than a texel center.
        var top = 4.35'f32
        for font in .fonts
        {
            painter.drawString(6.4, top, .text, font, Argb.Black)
            top += font.height + 3.7
        }
    }
}

// Renders `SampleText` in a fresh host after the same fonts drew `warm` in an earlier frame.
func renderAfter(warm: string)->Image
{
    var host: Testing.HeadlessHost
    host.setup(cast(f32, SampleWidth), cast(f32, SampleHeight))

    let wnd   = Wnd.create'DrawingOrderWnd(&host.root, {0, 0, cast(f32, SampleWidth), cast(f32, SampleHeight)})
    let cache = host.app.renderer.fontCache()
    for size in [14'u32, 41, 67] do
        wnd.fonts.add(cache.createFont(host.theme.res.defaultTypeFaceR, size))

    if warm.count
    {
        wnd.text = warm
        discard host.render()
    }

    wnd.text = SampleText
    return host.render()
}

// A glyph is drawn the same whatever text the font drew before it. Earlier text decides where
// each glyph lands in the shared atlas, and that placement must not reach the pixels a glyph
// produces: a document whose outline measured its headings first would otherwise differ, by a
// shade on a few antialiased pixels, from the same document drawn alone.
#test
{
    let reference = renderAfter("")
    // GPU filtering and framebuffer conversion can round antialiased coverage by one byte.
    // Keep the CPU reference exact and allow only that single-level edge rounding on GPU.
    let tolerance = Env.variable("SWAG_TEST_RENDERER") == "cpu" ? 0'u32 : 1'u32
    for warm in ["The quick brown fox jumps over the lazy dog, 0123456789.",
                 "erugif tpircsunaM",
                 "WAVE wave Typography: kerning, ligatures & glyphs!"]
    {
        let image = renderAfter(warm)
        for y in SampleHeight
        {
            for x in SampleWidth
            {
                let expected = reference.pixelColor(x, y).argb
                let actual   = image.pixelColor(x, y).argb
                Swag.require((actual >> 24) == (expected >> 24), Format.toString("after \"%\": pixel (%, %) alpha is % instead of %", warm, x, y, actual, expected).toString())
                for shift in [0'u32, 8, 16]
                {
                    let expectedChannel = (expected >> shift) & 0xFF
                    let actualChannel   = (actual >> shift) & 0xFF
                    let difference      = expectedChannel > actualChannel ? expectedChannel - actualChannel : actualChannel - expectedChannel
                    Swag.require(difference <= tolerance, Format.toString("after \"%\": pixel (%, %) is % instead of %", warm, x, y, actual, expected).toString())
                }
            }
        }
    }
}
