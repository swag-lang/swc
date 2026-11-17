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
    probe.tile.width = Painter.measureString("1280 x 800", font).width + 1
    probe.invalidate()
    discard host.renderSettled()
    Swag.require(not probe.called)
}
