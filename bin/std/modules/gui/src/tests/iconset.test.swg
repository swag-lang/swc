#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Icons already stored in controls remain valid when another request raises the atlas density.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 60)
    defer host.shutdown()

    var atlas: IconAtlas
    expect atlas.setup(#raw """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect x="4" y="4" width="16" height="16" fill="black"/></svg>""")
    var icons: IconSet
    icons.setup(&host.renderer, &atlas)
    defer icons.free()

    let small     = icons.icon(0, 16, 1)
    let large     = icons.icon(0, 24, 1)
    let smallList = small.imageList!
    let largeList = large.imageList!
    discard IconButton.create(&host.root, small, {10, 10, 40, 40})
    discard IconButton.create(&host.root, large, {65, 10, 40, 40})
    let before = host.render()

    // A third size raises the density without re-requesting either stored icon.
    let another = icons.icon(0, 20, 1.5)
    Swag.assert(another.imageList!.frameWidth == 40)
    Swag.assert(smallList.frameWidth == 32 and largeList.frameWidth == 48)
    Swag.assert(smallList.frameCount == 1 and largeList.frameCount == 1)
    Swag.assert(icons.icon(0, 16, 1).imageList == smallList)
    Swag.assert(icons.icon(0, 24, 1).imageList == largeList)
    let after = host.render()
    Swag.assert(before.width == after.width and before.height == after.height)
    Swag.assert(after.pixelColor(30, 30).argb == before.pixelColor(30, 30).argb)
    Swag.assert(after.pixelColor(85, 30).argb == before.pixelColor(85, 30).argb)
}
