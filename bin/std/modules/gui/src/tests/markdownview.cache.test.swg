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

    let view = Markdown.View.createText(&host.root, source.toString())
    view.resize(720, 900)
    view.applyLayout()
    let inline = unwrap view.blocks[0].inline

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

    let view = Markdown.View.createText(&host.root, source.toString())
    view.resize(720, 360)
    view.applyLayout()
    discard host.render(view)
    let first = unwrap view.blocks[1].inline
    Swag.assert(first.renderLayer.contentTarget != null)

    let target = view.blocks[80].wnd.position.y
    view.scroll.setScrollPos(0, target)
    Swag.assert(first.renderLayer.contentTarget == null)
    discard host.render(view)
    Swag.assert(view.blocks[81].inline!.renderLayer.contentTarget != null)
}

// Repainting static document blocks reuses their rasters instead of submitting every glyph.
// Fractional DPI, selection and search must produce the same pixels on a cache hit.
#test
{
    for scale in [1.0'f32, 1.5'f32]
    {
        var host: Testing.HeadlessHost
        host.setup(640, 480, dpiScale: scale)
        host.app.frameTrace.enabled = true

        let sources = [
            "## A backlog heading",
            "- First **entry** with `code`\n- Second entry",
            "```\nlet value = 42\n```",
            "> A quoted entry",
            "> [!WARNING]\n> Keep this warning visible."]
        for source in sources
        {
            let view = Markdown.View.createText(&host.root, source)
            view.resize(640, 480)
            view.applyLayout()
            Swag.assert(view.blocks.count == 1)
            let inline = unwrap view.blocks[0].inline

            let first    = host.render(view)
            let vertices = host.surface.paintVertices
            Swag.assert(inline.renderLayer.contentTarget != null)
            let target = inline.renderLayer.contentTarget
            let cached = host.render(view)
            Swag.assert(inline.renderLayer.contentTarget == target)
            Swag.assert(host.surface.paintVertices < vertices)
            Swag.assert(Slice.equals(first.pixels.toSlice(), cached.pixels.toSlice()))

            view.selectAll()
            Swag.assert(inline.renderLayer.contentTarget == null)
            let selected       = host.render(view)
            let selectedCached = host.render(view)
            Swag.assert(not Slice.equals(first.pixels.toSlice(), selected.pixels.toSlice()))
            Swag.assert(Slice.equals(selected.pixels.toSlice(), selectedCached.pixels.toSlice()))
            view.clearSelection()
            Swag.assert(inline.renderLayer.contentTarget == null)
            discard host.render(view)
            let highlighted = inline.highlightText("entry")
            if highlighted
            {
                Swag.assert(inline.renderLayer.contentTarget == null)
                let search       = host.render(view)
                let searchCached = host.render(view)
                Swag.assert(Slice.equals(search.pixels.toSlice(), searchCached.pixels.toSlice()))
                inline.clearSearchHighlight()
                Swag.assert(inline.renderLayer.contentTarget == null)
            }

            view.destroy()
            host.pump()
        }
    }
}

// A scrolling viewport keeps nearby list rasters, retires distant ones, and invalidates on style.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 320)
    var source: String
    for index in 24 do
        source += Format.toString("## Entry %\n\n- Evidence for this entry.\n- Next action for this entry.\n\n", index)
    let view = Markdown.View.createText(&host.root, source.toString())
    view.resize(640, 320)
    view.applyLayout()
    discard host.render(view)
    let list   = unwrap view.blocks[1].inline
    let target = list.renderLayer.contentTarget
    Swag.assert(target != null)
    view.scroll.setScrollPos(0, 16)
    discard host.render(view)
    Swag.assert(list.renderLayer.contentTarget == target)
    view.scroll.setScrollPos(0, 1600)
    Swag.assert(list.renderLayer.contentTarget == null)
    view.scroll.setScrollPos(0, 0)
    discard host.render(view)
    Swag.assert(list.renderLayer.contentTarget != null)
    var style = view.documentStyle
    style.bodyFontSize += 2
    view.setDocumentStyle(style)
    Swag.assert(list.renderLayer.contentTarget == null)
    let resized       = host.render(view)
    let resizedCached = host.render(view)
    Swag.assert(Slice.equals(resized.pixels.toSlice(), resizedCached.pixels.toSlice()))
}
