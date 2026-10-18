#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// The first paint shows a ring in each image box. Completion replaces it without reflow,
// for both Markdown images and embedded HTML, in every shipped palette and at high DPI.
#[Swag.TestTag("golden")]
#test
{
    let fileName = Testing.tempFilePath("markdown-image-loading-", ".svg")
    defer discard catch File.delete(fileName)
    let secondFileName = Testing.tempFilePath("markdown-image-gallery-", ".svg")
    defer discard catch File.delete(secondFileName)
    const Picture = "<svg width='120' height='60'><rect width='120' height='60' fill='#285078'/></svg>"
    discard expect File.writeAllText(fileName, Picture)
    discard expect File.writeAllText(secondFileName, Picture)
    let source = Format.toString("![Figure](<%>)\n\n<div><img src='%'><img src='%'></div>",
                                 fileName,
                                 fileName,
                                 secondFileName)

    for name, index in ["swagdark", "dark", "light", "hidpi", "paper"]
    {
        var host: Testing.HeadlessHost
        host.setup(480, 240, index == 3 ? 2 : 1)
        defer host.shutdown()
        switch index
        {
        case 0, 3, 4: host.theme.setSwagDark()
        case 1:       host.theme.setDark()
        case 2:       host.theme.setLight()
        }

        host.app.deterministicStreaming = false
        let view = Markdown.View.createText(&host.root, source.toString())
        if index == 4 do
            view.setDocumentThemeColors("view_Bk 0xFFFFFFFF\nlabel_Text 0xFF333333")
        view.resize(480, 240)
        view.applyLayout()
        let inline = view.blocks[0].inline!
        let html   = view.blocks[1].html!
        let first  = view.blocks[0].wnd.position
        let second = view.blocks[1].wnd.position
        var image  = host.render(view)
        Swag.assert(inline.images.raster != null and html.images.raster != null)
        Swag.assert(not inline.images.entries[0].uploaded and not html.images.entries[0].uploaded)
        Pixel.Testing.assertImageGolden(&image, Format.toString("markdownview.images.loading.%", name).toString())

        // Waiting belongs to the test harness; an actual frame only polls the tasks.
        for 3
        {
            inline.images.raster?.task.wait()
            html.images.raster?.task.wait()
            image = host.render(view)
        }

        Swag.assert(inline.images.raster == null and html.images.raster == null)
        Swag.assert(inline.images.entries[0].uploaded and html.images.entries[0].uploaded)
        Swag.assert(html.images.entries.count == 2 and html.images.entries[1].uploaded)
        Swag.assert(view.blocks[0].wnd.position == first and view.blocks[1].wnd.position == second)
        Swag.assert(inline.images.entries[0].image.pixelColor(60, 30).argb == 0xFF285078)
        Swag.assert(html.images.entries[0].image.pixelColor(60, 30).argb == 0xFF285078)
    }
}

// Raster jobs survive entry-array growth, publish on the UI thread, grow at a new DPI,
// reuse a sufficiently large texture, and join before a cache is cleared or destroyed.
#test
{
    let fileName = Testing.tempFilePath("markdown-image-worker-", ".svg")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName,
                                     "<svg width='120' height='60'><rect width='120' height='60' fill='#285078'/></svg>")
    var host: Testing.HeadlessHost
    host.setup(320, 240)
    defer host.shutdown()
    var cache: HtmlImageCache
    cache.asynchronous = true

    let pending = cache.texture(host.app.renderer, fileName.toString(), 120, 60)
    Swag.assert(pending == null and cache.raster != null and not cache.entries[0].uploaded)
    for index in 64 do
        discard cache.fetch(Format.toString("missing-image-%.png", index).toString())
    cache.raster.task.wait()
    let ready = cache.texture(host.app.renderer, fileName.toString(), 120, 60)
    Swag.assert(ready != null and cache.raster == null and cache.entries[0].uploaded)
    Swag.assert(cache.entries[0].image.width == 120)

    let larger = cache.texture(host.app.renderer, fileName.toString(), 240, 120)
    Swag.assert(larger == null and cache.raster != null and not cache.entries[0].uploaded)
    cache.raster.task.wait()
    let resized = cache.texture(host.app.renderer, fileName.toString(), 240, 120)
    Swag.assert(resized != null and cache.entries[0].image.width == 240)
    let pixels  = cast(u64, cache.entries[0].image.pixels.buffer)
    let smaller = cache.texture(host.app.renderer, fileName.toString(), 60, 30)
    Swag.assert(smaller != null and cache.raster == null)
    Swag.assert(cast(u64, cache.entries[0].image.pixels.buffer) == pixels)

    discard cache.texture(host.app.renderer, fileName.toString(), 480, 240)
    cache.clear()
    Swag.assert(cache.raster == null and cache.entries.isEmpty() and cache.index.isEmpty())
    discard cache.texture(host.app.renderer, fileName.toString(), 120, 60)
    Swag.assert(cache.raster != null)
}

// File preparation publishes dimensions without decoding SVG contents. A later read failure
// retires the spinner and remains cached instead of retrying the missing resource every frame.
#test
{
    let imagePath = Testing.tempFilePath("markdown-image-deferred-", ".svg")
    defer discard catch File.delete(imagePath)
    let fileName = Testing.tempFilePath("markdown-image-deferred-", ".md")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(imagePath,
                                     "<svg width='120' height='60'><image width='120' height='60' href='unavailable.png'/></svg>")
    discard expect File.writeAllText(fileName, Format.toString("![Deferred](<%>)", imagePath).toString())
    var host: Testing.HeadlessHost
    host.setup(320, 240)
    defer host.shutdown()
    host.app.deterministicStreaming = false
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(320, 240)
    view.applyLayout()
    for 4
    {
        host.fireTimers()
        view.imageTask.wait()
    }

    Swag.assert(view.blocks.count == 1)
    let cache = &view.blocks[0].inline!.images
    Swag.assert(cache.entries[0].needsParsing and cache.entries[0].loaded)
    Swag.assert(cache.entries[0].drawing.shapeCount() == 0)
    expect File.delete(imagePath)
    discard host.render(view)
    Swag.assert(cache.raster != null)
    cache.raster.task.wait()
    discard host.render(view)
    Swag.assert(cache.raster == null and not cache.entries[0].loaded)
    discard host.render(view)
    Swag.assert(cache.raster == null and cache.entries.count == 1)
}
