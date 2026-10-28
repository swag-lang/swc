#global internal

using Core, Pixel

// Keep 4K figures sharp while bounding each cached RGBA bitmap to 32 MiB.
private const HtmlSvgRasterLimit  = 4096.0
private const HtmlSvgRasterPixels = 8 * 1024 * 1024'u64

// A photo embedded in one SVG must not hold every lighter gallery image behind its decoder.
// Bound concurrent parsing because each drawing may own full-resolution decoded photographs.
private const HtmlImageParseLimit = 4'u64

// Resolves an offline resource without accepting URL schemes, UNC paths, or device namespaces.
internal func htmlLocalResourcePath(basePath, source: string)->String
{
    if not Path.isValidPathName(source) or
       Utf8.contains(source, "://") or
       Utf8.startsWith(source, "data:") do
        return {}
    let colon = Utf8.indexOf(source, ':'rune)
    if colon != Swag.U64.Max and not (WINDOWS and colon == 1 and Latin1.isLetter(source[0])) do
        return {}
    if basePath.count and not Path.isValidPathName(basePath) do
        return {}

    let fileName = Path.isRooted(source) ? String.from(source) : Path.combine(basePath, source)
    if fileName.count >= 2 and
       Path.isDirectorySeparator(fileName[0]) and
       Path.isDirectorySeparator(fileName[1]) do
        return {}
    return fileName
}

// One image a document referenced, decoded at most once.
struct HtmlImageEntry
{
    source:       String
    image:        Image
    drawing:      Svg.Drawing
    texture:      Texture
    naturalSize:  Math.Vector2     // Layout dimensions; cached raster resolution may differ.
    rasterSize:   Math.Vector2     // Largest physical size requested by layout before any texture is drawn.
    loaded:       bool
    uploaded:     bool
    isVector:     bool
    needsParsing: bool     // SVG dimensions are ready; contents still belong to the next parse job.
}

// Stable storage keeps the worker independent of cache moves and entry-array growth.
struct HtmlImageParse
{
    drawing:  Svg.Drawing
    task:     Swag.Task
    slot:     u32
    fileName: String
}

// The images of one document, resolved against the folder the document was read from.
//
// A reference that cannot be resolved is remembered as a failure, so a broken `src` repeated a
// hundred times costs one attempt rather than one attempt per layout. Asynchronous caches reserve
// SVG dimensions first and prepare visible drawings on a bounded set of workers. Rasterization
// and texture uploads belong to paint, when the surface renderer exists.
struct HtmlImageCache
{
    basePath:     String
    entries:      Array'HtmlImageEntry
    index:        HashTable'(String, u32)
    renderer:     IRenderer?
    asynchronous: bool
    parsing:      Array'(*HtmlImageParse)
    loadingPhase: f32
}

impl HtmlImageCache
{
    // Releases every texture this cache uploaded.
    mtd release()
    {
        .finishParsing(wait: true)
        let renderer = .renderer
        if renderer
        {
            for &entry in .entries where entry.uploaded
            {
                renderer.removeTexture(&entry.texture)
                entry.uploaded = false
            }
        }

        .renderer = null
    }

    // Paint publishes completed drawings without waiting for another image's decoder.
    // Retirement joins every worker before the cache or its entries can move out of scope.
    mtd finishParsing(wait = false)
    {
        for index in reversed(.parsing.count)
        {
            let parsing = .parsing[index]
            if not wait and parsing.task.isPending() do
                continue
            var errorOutcome: Swag.Error
            catch parsing.task.take() as errorOutcome
            let error = errorOutcome.value()
            let entry = &.entries[parsing.slot]
            entry.loaded       = error == null
            entry.needsParsing = false
            entry.drawing      = #move parsing.drawing
            Memory.delete(parsing)
            .parsing.removeAt(index)
        }
    }

    mtd paintLoading(wnd: *Wnd, painter: *Painter, frame: Math.Rectangle)
    {
        painter.pushState()
        defer painter.popState()
        let metrics = wnd.themeMetrics()
        let colors  = wnd.themeColors()
        let size    = Math.min(metrics.spinner_Size, Math.min(frame.width, frame.height))
        Spinner.paintRing(painter,
                          Math.Rectangle{frame.horzCenter() - size * 0.5, frame.vertCenter() - size * 0.5, size, size},
                          .loadingPhase,
                          colors.spinner_Track,
                          colors.spinner_Mark,
                          metrics)
        wnd.invalidate()
    }

    mtd opDrop()
    {
        .release()
    }

    mtd clear()
    {
        .release()
        .entries.clear()
        .index.clear()
    }

    // Returns a decoded raster or parsed vector, or null when there is none to draw.
    //
    // A `data:` reference carries its bytes in the document and decodes in place. Otherwise only
    // a local reference is followed: the engine never opens a network connection for a document
    // it is asked to display, which is what makes viewing an untrusted file safe.
    mtd fetch(source: string)->*HtmlImageEntry?
    {
        if not source.count do
            return null

        let found = .index.tryFind(String.from(source))
        if found do
            return .entries[found.value].loaded ? &.entries[found.value] : null

        let slot = cast(u32, .entries.count)
        var entry: HtmlImageEntry
        entry.source = source
        .entries.add(#move entry)
        .index.add(String.from(source), slot)

        if Utf8.startsWith(source, "data:")
        {
            let embedded = catch Image.fromDataUri(source) { return null }
            .entries[slot].image       = embedded
            .entries[slot].naturalSize = Math.Vector2{cast(f32, embedded.width), cast(f32, embedded.height)}
            .entries[slot].loaded      = true
            return &.entries[slot]
        }

        let fileName = htmlLocalResourcePath(.basePath.toString(), source)
        if fileName.isEmpty() do
            return null

        if Path.lowercaseExtension(fileName.toString()) == ".svg"
        {
            let text = catch File.readAllText(fileName) { return null }
            if .asynchronous
            {
                let size = catch Svg.parseImageSize(text.toString()) { return null }
                .entries[slot].naturalSize  = size
                .entries[slot].isVector     = true
                .entries[slot].loaded       = true
                .entries[slot].needsParsing = true
                return &.entries[slot]
            }

            var parseErrorOutcome: Swag.Error
            var drawing: #decltype(expect Svg.Drawing.parse(text.toString()))
            catch { drawing = try Svg.Drawing.parse(text.toString()) } as parseErrorOutcome
            let parseError = parseErrorOutcome.value()
            if parseError != null or drawing.width <= 0 or drawing.height <= 0 do
                return null
            .entries[slot].naturalSize = drawing.naturalSize()
            .entries[slot].drawing     = #move drawing
            .entries[slot].isVector    = true
            .entries[slot].loaded      = true
            return &.entries[slot]
        }

        let image = catch Image.load(fileName.toString()) { return null }

        .entries[slot].image       = image
        .entries[slot].naturalSize = Math.Vector2{cast(f32, image.width), cast(f32, image.height)}
        .entries[slot].loaded      = true
        return &.entries[slot]
    }

    // Collects layout sizes before paint, so repeated references share one sufficiently large texture.
    mtd requestSize(source: string, pixelWidth, pixelHeight: f32)
    {
        let entry = .fetch(source)
        if not entry or not entry.isVector do
            return
        entry.rasterSize.x = Math.max(entry.rasterSize.x, pixelWidth)
        entry.rasterSize.y = Math.max(entry.rasterSize.y, pixelHeight)
    }

    // Rasterizes vectors at their displayed pixel size, retaining the largest requested raster.
    // Layout only parses the source; invisible vectors do not allocate or render a bitmap.
    mtd texture(renderer: IRenderer, source: string, pixelWidth, pixelHeight: f32)->*Texture?
    {
        .finishParsing()
        let entry = .fetch(source)
        if not entry do
            return null
        if entry.isVector
        {
            // Keep the source aspect ratio: CSS may stretch the uploaded texture independently.
            let size           = entry.naturalSize
            let requestedScale = Math.max(Math.max(pixelWidth, entry.rasterSize.x) / size.x, Math.max(pixelHeight, entry.rasterSize.y) / size.y)
            let scale          = Math.min(requestedScale, HtmlSvgRasterLimit / Math.max(size.x, size.y), Math.sqrt(cast(f32, HtmlSvgRasterPixels) / size.x / size.y))
            let capped         = scale < requestedScale
            let width          = cast(s32, Math.max(capped ? Math.floor(size.x * scale) : Math.ceil(size.x * scale), 1))
            let height         = cast(s32, Math.max(capped ? Math.floor(size.y * scale) : Math.ceil(size.y * scale), 1))
            if entry.image.width < width or entry.image.height < height
            {
                if entry.uploaded
                {
                    .renderer!.removeTexture(&entry.texture)
                    entry.uploaded = false
                }

                if .asynchronous and entry.needsParsing
                {
                    // Parse visible drawings off-thread, then rasterize through the surface
                    // renderer. A software raster here bypasses the application's GPU entirely.
                    let slot = .index.find(String.from(source)).value
                    for parsing in .parsing where parsing.slot == slot do
                        return null
                    if .parsing.count < HtmlImageParseLimit
                    {
                        let parsing = Memory.new'HtmlImageParse()
                        parsing.slot     = slot
                        parsing.fileName = htmlLocalResourcePath(.basePath.toString(), source)
                        .parsing.add(parsing)
                        parsing.task.submit(func|parsing|() fail
                        {
                            let text = try File.readAllText(parsing.fileName)
                            parsing.drawing = try Svg.Drawing.parse(text.toString())
                        })
                    }

                    return null
                }

                // The surface renderer is ready during paint. Reuse its backend for the
                // offscreen raster instead of blocking the frame with a software render.
                entry.image = entry.drawing.rasterize(renderer, width, height)
            }
        }

        if entry.uploaded do
            return &entry.texture

        .renderer      = renderer
        entry.texture  = renderer.addImage(entry.image)
        entry.uploaded = true
        return &entry.texture
    }
}
