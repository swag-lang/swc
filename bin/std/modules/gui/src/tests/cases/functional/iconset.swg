#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

struct IconTintProbe
{
    using wnd: Wnd
    icon:      Icon
    fallback:  Color
}

impl IWnd for IconTintProbe
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        .icon.paint(evt.paintContext.painter, 0, 0, .fallback)
    }
}

// Icon.paint owns tint precedence even for a caller that always supplies neutral ink.
#test
{
    var host: Testing.HeadlessHost
    host.setup(64, 32)
    var atlas: IconAtlas
    expect atlas.setup("<svg width='24' height='24'><rect width='24' height='24' fill='white'/></svg>")
    var icons: IconSet
    icons.setup(host.app.renderer, &atlas)
    defer icons.free()
    let probe = Wnd.create'IconTintProbe(&host.root, {0, 0, 24, 24})
    probe.icon       = icons.icon(0, 24, 1)
    probe.icon.color = host.theme.colors.fileKind_Video
    probe.fallback   = host.theme.colors.softText
    let colored = host.renderSettled()
    Swag.require(colored.pixelColor(12, 12) == probe.icon.color)

    probe.icon.color = {}
    probe.invalidate()
    let neutral = host.renderSettled()
    Swag.require(neutral.pixelColor(12, 12) == probe.fallback)
}

// Supplied rasters own their pixels; invalid geometry leaves the cache unchanged.
#test
{
    var atlas: IconAtlas
    expect atlas.setup("<svg width='24' height='24'><rect width='24' height='24' fill='blue'/></svg>")
    var pixels = Image.create(32, 32, .BGRA8)
    pixels.fill(Argb.Blue)
    expect atlas.setRaster(32, pixels)
    pixels.fill(Argb.Red)
    Swag.require(atlas.image(32).pixelColor(16, 16).argb == cast(u32, Argb.Blue))

    for cell in [0, -1, 31]
    {
        var failure: Swag.Error
        catch atlas.setRaster(cell, pixels) as failure
        Swag.require(failure.value() != null)
        Swag.require(atlas.image(32).pixelColor(16, 16).argb == cast(u32, Argb.Blue))
    }

    let fallback = atlas.image(40)
    Swag.require(fallback.width == 40 and fallback.pixelColor(20, 20).argb == cast(u32, Argb.Blue))
    expect atlas.setup("<svg width='24' height='24'><rect width='24' height='24' fill='red'/></svg>")
    Swag.require(atlas.image(32).pixelColor(16, 16).argb == cast(u32, Argb.Red))
}

// Icons already stored in controls remain valid when another request raises the atlas density.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 60)

    var atlas: IconAtlas
    expect atlas.setup(#raw """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect x="4" y="4" width="16" height="16" fill="black"/></svg>""")
    var icons: IconSet
    icons.setup(host.app.renderer, &atlas)
    defer icons.free()

    let small     = icons.icon(0, 16, 1)
    let large     = icons.icon(0, 24, 1)
    let smallList = unwrap small.imageList
    let largeList = unwrap large.imageList
    discard IconButton.create(&host.root, small, {10, 10, 40, 40})
    discard IconButton.create(&host.root, large, {65, 10, 40, 40})
    let before = host.render()

    // A third size raises the density without re-requesting either stored icon.
    let another = icons.icon(0, 20, 1.5)
    Swag.require(another.imageList!.frameWidth == 40)
    Swag.require(smallList.frameWidth == 32 and largeList.frameWidth == 48)
    Swag.require(smallList.frameCount == 1 and largeList.frameCount == 1)
    Swag.require(icons.icon(0, 16, 1).imageList == smallList)
    Swag.require(icons.icon(0, 24, 1).imageList == largeList)
    let after = host.render()
    Swag.require(before.width == after.width and before.height == after.height)
    Swag.require(after.pixelColor(30, 30).argb == before.pixelColor(30, 30).argb)
    Swag.require(after.pixelColor(85, 30).argb == before.pixelColor(85, 30).argb)
}
