#global internal

using Core, Pixel

// One decoded page a view keeps in memory, with the resources every frame that shows it reuses.
//
// The type identity is part of the exported widget layout, so it is public, but it carries no
// public contract of its own.
#[Swag.NoDoc, Swag.NoCopy]
public struct PdfResidentPage
{
    index: u64          // Zero-based page this entry holds.
    page:  Pdf.Page     // The decoded page, left empty when the document could not give it.

    // Why the page could not be decoded, empty when it decoded. The entry is kept either way, so
    // a page that cannot be read is not decoded again by every frame that reaches it.
    failure: String

    // Textures of the page's image items, uploaded to the application renderer once per page and
    // reused by every subsequent paint, in item order.
    textures:    Array'Texture
    hasTextures: bool

    fonts: Pdf.RenderFontCache     // Typefaces resolved once per page rather than once per paint.

    textIndex:    Pdf.TextIndex     // The page's text, indexed when selection or search first asks for it.
    hasTextIndex: bool

    preparedScale: f32     // How finely the page's geometry is currently flattened.
    used:          u64     // Stamp of the last frame that showed the page, which orders eviction.
    bytes:         u64     // What the page holds in memory, which is what bounds the cache.
}

impl PdfResidentPage
{
    // Uploads the page's images and soft mask coverages to the application renderer, once per page.
    //
    // The decoded page keeps the pixels; the textures are the renderer-side copies every
    // subsequent paint reuses, whatever the zoom.
    mtd ensureTextures(renderer: Pixel.IRenderer)
    {
        if .hasTextures do
            return
        for item in .page.items
        {
            if item.kind == .Image do
                .textures.add(renderer.addImage(item.image))
            elif item.hasMask do
                .textures.add(renderer.addImage(item.maskImage))
        }

        .hasTextures = true
    }

    mtd releaseTextures(renderer: Pixel.IRenderer)
    {
        if .hasTextures
        {
            for &texture in .textures do
                renderer.removeTexture(texture)
        }

        .textures.clear()
        .hasTextures = false
    }

    // Indexes the page's text, once per page and only when selection or search asks for it.
    mtd ensureTextIndex()
    {
        if .hasTextIndex do
            return
        .textIndex    = Pdf.TextIndex.build(&.page)
        .hasTextIndex = true
    }

    // Returns the page's indexed text, which is empty until something asked for the index.
    mtd const text()->string => .textIndex.text.toString()

    // Reports whether the page decoded and can be drawn.
    mtd const isDrawable()->bool => .failure.isEmpty() and .page.width > 0 and .page.height > 0

    // Re-reads what the page holds in memory.
    //
    // A page grows after it is decoded — flattening it finer for a zoom step builds geometry the
    // decode did not — so the size the cache evicts on is taken again whenever that happens
    // rather than once when the page arrived.
    mtd measure()
    {
        .bytes = .page.memoryUsage()
    }
}

// The decoded pages a view keeps around, and the worker that decodes them.
//
// A reader is single-threaded, so the worker opens its own on the same file: the one the view
// answers page counts and page sizes from stays on the GUI thread. One page is decoded at a time
// and the view adopts it between frames, so scrolling into a page, turning to one, or revealing a
// search hit on one never decodes on the thread that draws.
//
// The type identity is part of the exported widget layout, so it is public, but it carries no
// public contract of its own.
#[Swag.NoDoc, Swag.NoCopy]
public struct PdfPageCache
{
    // Resident pages, in no particular order. Entries are allocated one by one, so a page
    // borrowed for a frame stays where it is while another one is adopted or evicted.
    pages: ArrayPtr'PdfResidentPage

    fileName: String
    clock:    u64     // Stamps `PdfResidentPage.used`, so the oldest page outside the band goes first.

    // The worker and everything only it touches between a request and the adoption that follows.
    task:        Swag.Task
    reader:      Pdf.Reader
    readerReady: bool
    readerError: String
    loading:     bool
    loadIndex:   u64
    loadScale:   f32
    loadPage:    Pdf.Page
    loadFailure: String
}

impl PdfPageCache
{
    // Names the file pages are decoded from, releasing the previous document.
    mtd open(fileName: string, renderer: Pixel.IRenderer)
    {
        .close(renderer)
        .fileName = fileName
    }

    // Releases every resident page, the worker's reader, and the file it was reading.
    mtd close(renderer: Pixel.IRenderer)
    {
        .abandonLoad()
        for page in .pages do
            page!.releaseTextures(renderer)
        .pages.clear()
        .fileName.clear()
        .readerError.clear()
        .readerReady = false
        .clock       = 0
        Swag.drop(&.reader, 1)
        Swag.init(&.reader, 1)
    }

    mtd opDrop()
    {
        // Textures belong to a renderer this value no longer has; the view releases them while it
        // still can, and dropping the cache only has to leave the worker's page behind.
        .abandonLoad()
    }

    // Returns the resident entry for `index` and marks it as the most recently shown, or nothing
    // when that page is not decoded.
    mtd resident(index: u64)->*PdfResidentPage?
    {
        for page in .pages where page!.index == index
        {
            .clock     += 1
            page!.used = .clock
            return page
        }

        return null
    }

    // Reports whether `index` is decoded, without marking it as used.
    mtd const isResident(index: u64)->bool
    {
        for page in .pages where page!.index == index do
            return true
        return false
    }

    // Reports whether the worker is decoding a page.
    mtd const isLoading()->bool => .loading

    // Returns the page the worker is decoding, or `Swag.U64.Max` when it is idle.
    mtd const loadingIndex()->u64 => .loading ? .loadIndex : Swag.U64.Max

    // Has the worker decode `index` and flatten it for a draw at `scale`.
    //
    // One page is decoded at a time: a request that arrives while the worker is busy is ignored,
    // and the caller asks again on the next frame with whatever the viewport needs by then.
    // Reports whether a page is being decoded when it returns.
    mtd request(index: u64, scale: f32)->bool
    {
        if .loading do
            return true
        if .fileName.isEmpty() or .isResident(index) do
            return false

        .loadIndex = index
        .loadScale = scale
        .loading   = true
        .loadFailure.clear()

        let cache = me
        .task.submit(func|cache|() { cache.runLoad() })
        return true
    }

    // Publishes a finished decode and returns the entry it added, or nothing while none finished.
    //
    // A page that could not be decoded is published too, carrying the reason: the entry is what
    // stops the view from asking for it again on every frame.
    mtd adopt()->*PdfResidentPage?
    {
        if !.loading or !.task.isDone() do
            return null

        .task.wait()
        .loading = false

        let entry = .pages.addNew()
        entry.index = .loadIndex
        swap(&entry.page, &.loadPage)
        swap(&entry.failure, &.loadFailure)
        entry.fonts.reset(entry.page.fonts.count)
        entry.preparedScale = entry.isDrawable() ? .loadScale : 0
        entry.measure()
        .clock     += 1
        entry.used = .clock
        return entry
    }

    // Takes a page decoded outside the cache, exchanging it with the empty page `page` keeps.
    //
    // This is how the first page a host decoded away from the GUI thread reaches the view without
    // being decoded a second time here.
    mtd insert(index: u64, page: *Pdf.Page)->*PdfResidentPage
    {
        let entry = .pages.addNew()
        entry.index = index
        swap(&entry.page, page)
        entry.fonts.reset(entry.page.fonts.count)
        entry.measure()
        .clock     += 1
        entry.used = .clock
        return entry
    }

    // Returns what every resident page holds in memory, in bytes.
    mtd const memoryUsage()->u64
    {
        var result = 0'u64
        for page in .pages do
            result += page!.bytes
        return result
    }

    // Evicts the pages furthest from the band the view is showing, until at most `limit` pages
    // holding at most `budget` bytes remain.
    //
    // Two bounds are needed because a page is not a unit of memory: a page of text costs a
    // hundredth of a page of scans, so a count alone either keeps too little of a slide deck or
    // too much of a scanned book. A page from `keepFrom` to `keepTo` is never evicted, whatever
    // the bounds: the frame about to run needs it. Among the others the least recently shown goes
    // first, which keeps the page a reader just left in memory for the step back.
    mtd trim(renderer: Pixel.IRenderer, keepFrom, keepTo, limit, budget: u64)
    {
        while .pages.count > limit or .memoryUsage() > budget
        {
            var victim = Swag.U64.Max
            var oldest = Swag.U64.Max
            for page, index in .pages
            {
                if page!.index >= keepFrom and page!.index <= keepTo do
                    continue
                if page!.used < oldest
                {
                    oldest = page!.used
                    victim = index
                }
            }

            if victim == Swag.U64.Max do
                return

            .pages[victim]!.releaseTextures(renderer)
            .pages.deleteAt(victim)
        }
    }

    // Waits for the page being decoded and throws it away.
    //
    // A decode cannot be abandoned once it starts, so this is a wait and not a cancellation: the
    // caller pays what remains of one page rather than of the document.
    mtd abandonLoad()
    {
        if !.loading do
            return
        .task.wait()
        .loading = false
        .loadFailure.clear()
        Swag.drop(&.loadPage, 1)
        Swag.init(&.loadPage, 1)
    }

    // Runs on the worker: decodes one page and flattens it for the scale that asked for it.
    //
    // The reader is opened here, on the first page the view asks for, and kept for the rest of
    // the document. A file that cannot be reopened fails every page with the same reason rather
    // than being retried once per page.
    private mtd runLoad()
    {
        if !.readerReady
        {
            if !.readerError.isEmpty()
            {
                .loadFailure = .readerError
                return
            }

            var opened = catch Pdf.Reader.open(.fileName.toString()) as openError
            if openError != null
            {
                .readerError = Errors.message(openError)
                .loadFailure = .readerError
                return
            }

            swap(&.reader, &opened)
            .readerReady = true
        }

        var page = catch .reader.loadPage(.loadIndex) as pageError
        if pageError != null
        {
            .loadFailure = Errors.message(pageError)
            return
        }

        // The page is this worker's own until it is adopted, so the flattening the first frame
        // needs is built here instead of inside that frame.
        page.prepare(.loadScale)
        swap(&.loadPage, &page)
    }
}
