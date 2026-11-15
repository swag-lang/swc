#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Styling and whitespace split draw runs without splitting a logical link's activation.
#test
{
    var text = RichString.fromMarkup("<a>First <b>action</b></a> then <a>Second action</a>.")
    text.compute()
    var starts: Array'u64
    for &chunk in text.chunks where chunk.isUrl and not starts.contains(chunk.urlStart) do
        starts.add(chunk.urlStart)
    Swag.require(starts.count == 2)
    Swag.require(text.urlText(starts[0]) == "First action")
    Swag.require(text.urlText(starts[1]) == "Second action")
    Swag.require(text.urlText(Swag.U64.Max).isEmpty())
}

// The disabled link uses one brush for its glyphs and persistent underline. Surrounding prose
// keeps its own palette entry in both states.
#[Swag.TestTag("golden")]
#test
{
    var cache: FontCache
    let font = makeTextTestFont(&cache, 16, .Bitmap)
    for enabled in [true, false]
    {
        var text = RichString.fromMarkup("Wait <a>15\u00A0minutes</a>.")
        var format: RichStringFormat
        format.font.regular        = font
        format.palette[0]          = Color.fromRgb(150, 150, 150)
        format.colorUrl            = Color.fromRgb(56, 189, 248)
        format.colorDisabledUrl    = Color.fromRgb(90, 90, 90)
        format.urlsEnabled         = enabled
        format.underlineUrls       = true
        format.urlUnderlineOpacity = 0.35
        var painter: Painter
        painter.begin()
        painter.drawRichString({0, 0, 240, 40}, &text, format)
        painter.end()
        Testing.assertGolden(&painter, enabled ? "text.richlink.active" : "text.richlink.disabled")
    }
}
