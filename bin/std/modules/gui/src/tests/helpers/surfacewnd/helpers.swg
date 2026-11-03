#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core, Pixel

// A product mark as an application ships it: a Voltage glyph cut from an ink tile.
func chromeTestMark()->Image
{
    var result = Image.create(32, 32, .RGBA8)
    result.visitPixels()
    {
        let frame = x >= 6 and x < 26 and y >= 6 and y < 26
        let hole  = x >= 12 and x < 20 and y >= 12 and y < 20
        let color = (frame and not hole) ? MarkVoltage : MarkInk
        pix[0] = color.r
        pix[1] = color.g
        pix[2] = color.b
        pix[3] = 0xFF
    }

    return result
}

// Builds a standard application window around an empty document, in the theme the host wears.
//
// The window keeps the corner of the charter; the host squares it by default because a headless
// image has no desktop under it, and the corner is part of what this test pins. The strip floats
// over the view, so the view takes the whole body inside the outline.
func buildChromeWindow(host: *Testing.HeadlessHost)
{
    host.app.setAppIcon(chromeTestMark())
    host.theme.metrics.surfaceWnd_CornerRadius = 10
    host.surface.flags        = .StandardWindow
    host.surfaceWnd.padding   = {1, 1, 1, 1}
    host.root.backgroundStyle = .Window
    host.surface.setTitle("viewerchrome.swg")
    host.surfaceWnd.create(&host.root, null)
    host.surfaceWnd.sendResizeEvent()
}
