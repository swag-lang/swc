#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Pixel

func paintBackdropDocument(wnd: *Wnd, event: IEvent)->bool
{
    if event is PaintEvent as paint where paint.kind == .Content
    {
        let painter = paint.paintContext.painter
        let colors  = wnd.themeColors()
        let font    = wnd.theme().createDefaultFont(14)
        for row in 14
        {
            let y = 30 + row * 30
            painter.fillRect(Math.Rectangle{24, y, 4, 16}, colors.arc)
            painter.drawString(44, y, "A document stays in place while its commands come into focus.", font, colors.text)
        }
    }

    return false
}

func backdropLens(host: *Testing.HeadlessHost, light: bool, scale: f32 = 1, compact = false)->*Lens.View
{
    host.setup(compact ? 320 : 760, compact ? 240 : 520, scale)
    if light do
        host.theme.setLight()
    else do
        host.theme.setDark()
    host.notify(.ThemeChanged)
    host.root.backgroundStyle = .Window
    host.root.hookOnEvent     = &paintBackdropDocument
    let lens = Lens.View.create(&host.root)
    lens.addRestSource(func(results)
    {
        let section = results.addSection("Document")
        discard section.addEntry("Find in Document")
        discard section.addEntry("Save as Image")
    })
    return lens
}
