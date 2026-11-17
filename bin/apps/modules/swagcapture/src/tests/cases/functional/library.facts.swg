#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

struct LibraryFactsProbe
{
    using wnd: Wnd
    favorite:  bool
    rating:    u8
}

impl IWnd for LibraryFactsProbe
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        paintLibraryFacts(me, evt.paintContext.painter, {0, 0, 120, 30}, "", .favorite, .rating)
    }
}

// Rating and favorite marks keep visible ink in both palettes without installed-font fallback.
#test
{
    Swag.require(not FontFamily.hasSystemFontAccess())
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(120, 30)
        if light do
            host.theme.setLight()
        host.notify(.ThemeChanged)
        let probe = Wnd.create'LibraryFactsProbe(&host.root, {0, 0, 120, 30})
        let plain = host.renderSettled()
        let font  = host.theme.createDefaultFontFs(host.theme.metrics.fileTile_FactsFontSize)
        let left  = cast(s32, Math.ceil(Painter.measureString(" · ", font).width))
        for favorite in [false, true]
        {
            probe.favorite = favorite
            probe.rating   = favorite ? 0 : 3
            probe.invalidate()
            let marked = host.renderSettled()
            var ink: u32
            for y in 30 do
                for x in cast(u32, RatingGlyphSize) do
                    if marked.pixelColor(left + cast(s32, x), cast(s32, y)) != plain.pixelColor(left + cast(s32, x), cast(s32, y)) do
                        ink += 1
            Swag.require(ink > 5, "a library metadata mark has no visible ink")
        }
    }
}
