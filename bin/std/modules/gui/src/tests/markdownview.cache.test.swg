#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Stable prose is rasterized once and subsequent scroll frames composite the retained block.
#test
{
    var source: String
    for 80 do
        source += "A manuscript paragraph keeps enough words to span many rendered lines. "

    var host: Testing.HeadlessHost
    host.setup(720, 900, 1.5)
    defer host.shutdown()

    let view = Markdown.View.createText(&host.root, source.toString())
    view.resize(720, 900)
    view.applyLayout()
    let inline = view.blocks[0].inline!

    let first = host.render(view)
    Swag.assert(inline.renderLayer.contentTarget != null)
    var hasInk: bool
    for pixel in first.pixels where pixel != first.pixels[0]
    {
        hasInk = true
        break
    }

    Swag.assert(hasInk)
    let second   = host.render(view)
    let commands = host.surface.painter.commandBuffer.count
    Swag.assert(Slice.equals(first.pixels.toSlice(), second.pixels.toSlice()))
    Swag.assert(commands < 80)
}

// Scrolling retains one screen behind the reader, then releases older block textures.
#test
{
    var source: String
    for index in 80 do
        source += Format.toString("## Section %\n\nEach section owns a stable paragraph raster while it remains close to the viewport.\n\n", index)

    var host: Testing.HeadlessHost
    host.setup(720, 360)
    defer host.shutdown()

    let view = Markdown.View.createText(&host.root, source.toString())
    view.resize(720, 360)
    view.applyLayout()
    discard host.render(view)
    let first = view.blocks[1].inline!
    Swag.assert(first.renderLayer.contentTarget != null)

    let target = view.blocks[80].wnd.position.y
    view.scroll.setScrollPos(0, target)
    Swag.assert(first.renderLayer.contentTarget == null)
    discard host.render(view)
    Swag.assert(view.blocks[81].inline!.renderLayer.contentTarget != null)
}
