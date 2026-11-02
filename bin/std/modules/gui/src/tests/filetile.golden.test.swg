#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// One virtual surface paints every cell; no file owns a retained child window.
struct FileTileProbe
{
    using wnd: Wnd
    landscape: Texture
    portrait:  Texture
}

impl IWnd for FileTileProbe
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        for index in 6
        {
            var rect    = Math.Rectangle{24 + cast(f32, index % 3) * 224, 24 + cast(f32, index / 3) * 238, 190, 140}
            var content = FileTile.Content{texture: .landscape, name: "A short name", facts: "2026 · image", detail: "16 KB"}
            var options: FileTile.Options
            switch index
            {
            case 0:
                content.name = "Cover"

            case 1:
                content.name    = "Whole image"
                options.fit     = .Contain
                options.hovered = true

            case 2:
                rect.height      = 180
                content.name     = "Landscape in a poster"
                content.badge    = "2:14"
                options.fit      = .Poster
                options.selected = true

            case 3:
                content.texture  = .portrait
                content.name     = "A long <literal> name & its complete ending.png"
                content.facts    = "Long metadata stays clear of the size"
                options.hovered  = true
                options.selected = true
                options.nameTick = 70

            case 4:
                content.texture = {}
                content.icon    = .theme().fileGlyph("Documents", true, 32)
                content.name    = "Documents"
                content.facts   = "12 items"
                content.detail  = ""

            case 5:
                content.texture     = .portrait
                options.showCaption = false
                options.selected    = true
            }

            let animate = FileTile.paint(me, evt.paintContext.painter, rect, &content, options)
            Swag.assert(animate == (index == 3))
        }
    }
}

// Contrast and interaction states share one renderer in both shipped palettes.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(690, 470)
        if light do
            host.theme.setLight()
        host.notify(.ThemeChanged)
        var landscape = Image.create(79, 37, .RGB8)
        landscape.fillGradient(Color.fromArgb(0xFF316589), Color.fromArgb(0xFFE5B87A), Color.fromArgb(0xFF234D34), Color.fromArgb(0xFF793B68))
        var portrait = Image.create(37, 79, .RGB8)
        portrait.fillGradient(Color.fromArgb(0xFF793B68), Color.fromArgb(0xFFE5B87A))
        var wide = host.app.renderer.addImage(landscape)
        var tall = host.app.renderer.addImage(portrait)
        defer host.app.renderer.removeTexture(&wide)
        defer host.app.renderer.removeTexture(&tall)
        let probe = Wnd.create'FileTileProbe(&host.root)
        probe.dockStyle = .Center
        probe.landscape = wide
        probe.portrait  = tall
        host.root.applyLayout()
        var image = host.render(&host.root)
        Pixel.Testing.assertImageGolden(&image, light ? "filetile.paper" : "filetile.ink")
    }
}
