#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

struct FileTileFactsProbe
{
    using wnd:   Wnd
    tile:        Math.Rectangle = {20, 10, 180, 50}
    factsRect:   Math.Rectangle
    called:      bool
    showCaption: bool = true
}

impl IWnd for FileTileFactsProbe
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        var content = FileTile.Content{name: "Preview", facts: "Replaced", detail: "1280 x 800"}
        var options: FileTile.Options
        options.showCaption  = .showCaption
        options.factsPainter = func|probe = me|(_, painter, rect)
        {
            probe.called    = true
            probe.factsRect = rect

            // A hostile overdraw must not cover the caption, detail, or neighboring tile.
            painter.fillRect({0, 0, 240, 140}, Argb.Magenta)
        }

        FileTile.paint(me, evt.paintContext.painter, .tile, &content, options)
    }
}

// A custom metadata mark stays in the space left by the trailing detail.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 140)
    let probe = Wnd.create'FileTileFactsProbe(&host.root, {0, 0, 240, 140})
    let image = host.renderSettled()
    Swag.require(probe.called and probe.factsRect.width > 0)
    Swag.require(probe.factsRect.x == probe.tile.x)
    Swag.require(probe.factsRect.right() < probe.tile.right())
    let x = cast(s32, probe.factsRect.x + 1)
    let y = cast(s32, probe.factsRect.vertCenter())
    Swag.require(image.pixelColor(x, y).argb == cast(u32, Argb.Magenta))
    Swag.require(image.pixelColor(10, y).argb != cast(u32, Argb.Magenta))
    Swag.require(image.pixelColor(cast(s32, probe.tile.right() - 1), y).argb != cast(u32, Argb.Magenta))
    Swag.require(image.pixelColor(x, cast(s32, probe.factsRect.y - 1)).argb != cast(u32, Argb.Magenta))

    probe.called      = false
    probe.showCaption = false
    probe.invalidate()
    discard host.renderSettled()
    Swag.require(not probe.called)

    probe.called      = false
    probe.showCaption = true
    let font = host.theme.createDefaultFontFs(host.theme.metrics.fileTile_FactsFontSize)
    probe.tile.width = Painter.measureStringSnapped("1280 x 800", font, deviceScale: probe.deviceScale()) + 1
    probe.invalidate()
    discard host.renderSettled()
    Swag.require(not probe.called)
}

// At fractional scaling the detail ends at the tile edge and the name scrolls only in its own slot.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 180, dpiScale: 1.5)
    let probe = Wnd.create'FileTileFactsProbe(&host.root, {0, 0, 360, 180})
    discard host.renderSettled()
    let mono = host.theme.createDefaultFontFs(host.theme.metrics.fileTile_FactsFontSize)
    let width = Painter.measureStringSnapped("1280 x 800", mono, deviceScale: probe.deviceScale())
    Swag.require(Math.isEqualEpsilon(probe.factsRect.right() + host.theme.metrics.fileTile_Inset + width, probe.tile.right(), 0.01))
    let name = "Contact sheet.png"
    let room = Painter.measureStringSnapped(name, nnFont(probe.font().regular), deviceScale: probe.deviceScale()) + 1
    Swag.require(not FileTile.nameScrollTicks(probe, name, room))
    Swag.require(FileTile.nameScrollTicks(probe, name, room, host.theme.fileGlyph(name, false, 14)) > 0)
}
