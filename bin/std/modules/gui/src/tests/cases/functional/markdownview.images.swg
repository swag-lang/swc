#global if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core, Pixel

#test
{
    let imagePath = Testing.tempFilePath("markdown-overlap-", ".svg")
    let fileName  = Testing.tempFilePath("markdown-overlap-", ".md")
    defer discard catch File.delete(imagePath)
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(imagePath, "<svg width='40' height='20'><rect width='40' height='20'/></svg>")
    var source = Format.toString("![Figure](<%>)\n\n<div><img src='%'></div>\n\n", imagePath, imagePath)
    for 100 do
        source += "A paragraph after the figures.\n\n"
    discard expect File.writeAllText(fileName, source.toString())

    var host: Testing.HeadlessHost
    host.setup(480, 240)
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(480, 240)
    view.applyLayout()
    for 64 where view.isLoading() do
        host.fireTimers()
    discard host.render(view)
    let inline = unwrap view.blocks[0].inline
    let html   = unwrap view.blocks[1].html
    Swag.assert(inline.images.entries[0].uploaded and html.images.entries[0].uploaded)
    let inlinePixels = cast(u64, inline.images.entries[0].image.pixels.buffer)
    let htmlPixels   = cast(u64, html.images.entries[0].image.pixels.buffer)

    view.pendingSeek       = true
    view.pendingSeekOffset = 0
    view.pendingSeekPreservesPosition = true
    if not view.loadTimer do
        view.loadTimer = view.addTimer(8'ms)
    host.fireTimer(view.loadTimer)
    for 64 where view.isLoading() do
        host.fireTimers()
    Swag.assert(view.retainedBlocks.isEmpty())
    let newInline = unwrap view.blocks[0].inline
    let newHtml   = unwrap view.blocks[1].html
    Swag.assert(newInline.images.entries[0].uploaded and newHtml.images.entries[0].uploaded)
    Swag.assert(cast(u64, newInline.images.entries[0].image.pixels.buffer) == inlinePixels)
    Swag.assert(cast(u64, newHtml.images.entries[0].image.pixels.buffer) == htmlPixels)
}
#test
{
    let fileName = Testing.tempFilePath("markdown-scrolled-image-", ".svg")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName,
                                     "<svg width='120' height='60'><rect width='120' height='60' fill='#285078'/></svg>")
    var source: String
    for 20 do
        source += "A paragraph above the embedded image.\n\n"
    source += Format.toString("<div><img src='%'></div>\n\nTrailing paragraph.", fileName)

    var gate:    Swag.Semaphore
    var started: Swag.Semaphore
    var host:    Testing.HeadlessHost
    host.setup(480, 240)
    host.app.deterministicStreaming = false
    let view = Markdown.View.createText(&host.root, source.toString())
    view.resize(480, 240)
    view.applyLayout()
    let html = unwrap view.blocks[20].html
    view.scroll.setScrollPos(0, html.position.y - 40)
    Swag.assert(view.scroll.scrollPosition().y > 240)
    Swag.assert(html.canvas.surfaceRect().y == html.surfaceRect().y)

    // JIT submissions run on the caller, so a gated body would block before submit returns.
    // Its first frame still paints the loading state; the next frame publishes the image.
    if Swag.jit()
    {
        discard host.render(view)
        Swag.assert(not html.images.parsing.isEmpty() and not html.images.entries[0].uploaded)
        Swag.assert(host.surface.isDirty)
        for parsing in html.images.parsing do
            parsing.task.wait()
        host.surface.paintWnd(view)
        Swag.assert(html.images.parsing.isEmpty() and html.images.entries[0].uploaded)
        Swag.assert(html.images.entries[0].image.pixelColor(60, 30).argb == 0xFF285078)
        return
    }

    // Hold completion beyond the first paint so unrelated initial invalidations cannot hide
    // a loading indicator that stops requesting frames once the rest of the surface is idle.
    let parsing = Memory.new'HtmlImageParse()
    html.images.parsing.add(parsing)
    parsing.task.submit(func|parsing, gate = &gate, started = &started|() fail
    {
        started.release()
        gate.acquire()
        parsing.drawing = expect Svg.Drawing.parse("<svg width='120' height='60'><rect width='120' height='60' fill='#285078'/></svg>")
    })
    defer
    {
        gate.release()
        for parsing in html.images.parsing do
            parsing.task.wait()
    }

    started.acquire()
    discard host.render(view)
    Swag.assert(not html.images.parsing.isEmpty() and not html.images.entries[0].uploaded)

    // The surface loop consumes only the region the loading image invalidated.
    for 4
    {
        Swag.assert(host.surface.isDirty)
        let phase = html.images.loadingPhase
        host.surface.paintWnd(view)
        Swag.assert(html.images.loadingPhase != phase)
    }

    gate.release()
    parsing.task.wait()
    host.surface.paintWnd(view)
    Swag.assert(html.images.parsing.isEmpty() and html.images.entries[0].uploaded)
}
#test
{
    let fileName = Testing.tempFilePath("markdown-image-worker-", ".svg")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName,
                                     "<svg width='120' height='60'><rect width='120' height='60' fill='#285078'/></svg>")
    var host: Testing.HeadlessHost
    host.setup(320, 240)
    var cache: HtmlImageCache
    cache.asynchronous = true

    let pending = cache.texture(host.app.renderer, fileName.toString(), 120, 60)
    Swag.assert(pending == null and not cache.parsing.isEmpty() and not cache.entries[0].uploaded)
    for index in 64 do
        discard cache.fetch(Format.toString("missing-image-%.png", index).toString())
    cache.parsing[0].task.wait()
    Swag.assert(cache.parsing[0].drawing.shapeCount() == 1 and not cache.entries[0].image.isValid())
    let ready = cache.texture(host.app.renderer, fileName.toString(), 120, 60)
    Swag.assert(ready != null and cache.parsing.isEmpty() and cache.entries[0].uploaded)
    Swag.assert(cache.entries[0].image.width == 120)

    let larger = cache.texture(host.app.renderer, fileName.toString(), 240, 120)
    Swag.assert(larger != null and cache.parsing.isEmpty() and cache.entries[0].image.width == 240)
    let pixels  = cast(u64, cache.entries[0].image.pixels.buffer)
    let smaller = cache.texture(host.app.renderer, fileName.toString(), 60, 30)
    Swag.assert(smaller != null and cache.parsing.isEmpty())
    Swag.assert(cast(u64, cache.entries[0].image.pixels.buffer) == pixels)

    cache.clear()
    discard cache.texture(host.app.renderer, fileName.toString(), 480, 240)
    cache.clear()
    Swag.assert(cache.parsing.isEmpty() and cache.entries.isEmpty() and cache.index.isEmpty())
    discard cache.texture(host.app.renderer, fileName.toString(), 120, 60)
    Swag.assert(not cache.parsing.isEmpty())
}
#test
{
    // A gated task cannot yield the caller in JIT execution; native tests exercise the overlap.
    if Swag.jit() do
        return
    const Source = "<svg width='120' height='60'><rect width='120' height='60' fill='#285078'/></svg>"
    let fileName = Testing.tempFilePath("markdown-gallery-", ".svg")
    discard expect File.writeAllText(fileName, Source)
    defer discard catch File.delete(fileName)
    var slowGate, fastGate, started: Swag.Semaphore
    var host: Testing.HeadlessHost
    host.setup(320, 240)
    var cache: HtmlImageCache

    // All four jobs deliberately block. Dedicated executors keep this fixture independent
    // of the shared pool's worker ceiling, including a one-worker test run.
    var executors: [4] Swag.Executor
    cache.asynchronous = true
    defer
    {
        for 3 do
            slowGate.release()
        fastGate.release()
        cache.release()
    }

    // Distinct authored references can name the same local file.
    var sources: Array'String
    var relative = String.from(unwrap Path.fileName(fileName.toString()))
    for index in 5
    {
        sources.add(Path.combine(unwrap Path.directoryName(fileName.toString()), relative.toString()))
        relative = Format.toString("./%", relative.toString())
        discard cache.fetch(sources[index].toString())
        if index == 4 do
            continue
        let parsing = Memory.new'HtmlImageParse()
        parsing.slot = cast(u32, index)
        cache.parsing.add(parsing)
        executors[index].start()
        parsing.task.submit(func|parsing, gate = index == 1 ? &fastGate : &slowGate, started = &started|() fail
        {
            started.release()
            gate.acquire()
            parsing.drawing = expect Svg.Drawing.parse(Source)
        },
                            executor: &executors[index])
    }

    for 4 do
        started.acquire()
    let duplicate = cache.texture(host.app.renderer, sources[0].toString(), 120, 60)
    Swag.assert(duplicate == null and cache.parsing.count == 4)
    let saturated = cache.texture(host.app.renderer, sources[4].toString(), 120, 60)
    Swag.assert(saturated == null and cache.parsing.count == 4)
    fastGate.release()
    cache.parsing[1].task.wait()
    let ready = cache.texture(host.app.renderer, sources[1].toString(), 120, 60)
    Swag.assert(ready != null and cache.parsing.count == 3 and not cache.entries[0].uploaded)
    let next = cache.texture(host.app.renderer, sources[4].toString(), 120, 60)
    Swag.assert(next == null and cache.parsing.count == 4)
}
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
    Swag.assert(not cache.parsing.isEmpty())
    cache.parsing[0].task.wait()
    discard host.render(view)
    Swag.assert(cache.parsing.isEmpty() and not cache.entries[0].loaded)
    discard host.render(view)
    Swag.assert(cache.parsing.isEmpty() and cache.entries.count == 1)
}
