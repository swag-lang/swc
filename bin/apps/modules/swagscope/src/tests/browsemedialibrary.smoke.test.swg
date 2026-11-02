#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// Owns an offline library and the deadline shared by its user journey.
struct SmokeLibrary
{
    root:       String
    watch:      Time.Stopwatch
    entryCount: u64 = 12
}

impl SmokeLibrary
{
    #[Swag.Propagate]
    mtd create() fail
    {
        .watch.start()
        .root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-smoke-%", Guid64.random()))
        Path.normalize(&.root)
        let fixtures = Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas")
        let films    = Path.combine(.root, "Films")
        let pictures = Path.combine(.root, "Pictures")
        Directory.create(.root, recurse: true)
        Directory.create(films)
        Directory.create(pictures)
        let mjpeg  = File.readAllBytes(Path.combine(fixtures, "glint-aac-mjpeg.mp4"))
        let h264   = File.readAllBytes(Path.combine(fixtures, "ffmpeg-h264-baseline.mp4"))
        let multi  = File.readAllBytes(Path.combine(fixtures, "ffmpeg-h264-two-aac.mkv"))
        let legacy = File.readAllBytes(Path.combine(fixtures, "rv40-legacy-clock.mkv"))
        let png    = File.readAllBytes(Path.combine(fixtures, "appicon.png"))
        let webp   = File.readAllBytes(Path.combine(fixtures, "imageset-real-review.webp"))
        let gif    = File.readAllBytes(Path.combine(fixtures, "imageset-animation.gif"))
        let tiff   = File.readAllBytes(Path.combine(fixtures, "imageset-pages-raw.tiff"))
        for index in .entryCount
        {
            switch index % 4
            {
            case 0: discard File.writeAllBytes(Path.combine(films, Format.toString("Film %{03} (2024).mp4", index)), mjpeg.toSlice())
            case 1: discard File.writeAllBytes(Path.combine(films, Format.toString("Film %{03} (2024).mp4", index)), h264.toSlice())
            case 2: discard File.writeAllBytes(Path.combine(films, Format.toString("Film %{03} (2024).mkv", index)), multi.toSlice())
            case 3: discard File.writeAllBytes(Path.combine(films, Format.toString("Film %{03} (2024).mkv", index)), legacy.toSlice())
            }

            switch index % 4
            {
            case 0: discard File.writeAllBytes(Path.combine(pictures, Format.toString("Picture %{03}.png", index)), png.toSlice())
            case 1: discard File.writeAllBytes(Path.combine(pictures, Format.toString("Picture %{03}.webp", index)), webp.toSlice())
            case 2: discard File.writeAllBytes(Path.combine(pictures, Format.toString("Picture %{03}.gif", index)), gif.toSlice())
            case 3: discard File.writeAllBytes(Path.combine(pictures, Format.toString("Picture %{03}.tiff", index)), tiff.toSlice())
            }
        }
    }

    // Existing online artwork is deterministic and needs no network credentials in this journey.
    #[Swag.Propagate]
    mtd seedPosters(window: *ViewerWindow, films: string) fail
    {
        let settings = ThumbnailSettings.capture(window)
        let entries  = expect Directory.enumerateFiles(films)
        for &entry, index in entries
        {
            // Odd RGB widths expose upload alignment mistakes, with a different color per entry.
            var image = Image.create(37, 53, .RGB8)
            image.fill(Color.fromRgb(cast(u8, index), 127, 241))
            let key = expect ThumbnailCache.key(entry.fullName, settings: settings)
            expect ThumbnailCache.write(key, &image)
        }
    }

    // Compare uploaded pixels too: presentation parity alone cannot expose a damaged texture.
    #[Swag.Propagate]
    mtd verifyPosters(window: *ViewerWindow) fail
    {
        let explorer = unwrap window.explorer
        let settings = ThumbnailSettings.capture(window)
        for &entry in explorer.entries where entry.texture.isValid()
        {
            let key      = ThumbnailCache.key(entry.path, settings: settings)
            let expected = ThumbnailCache.read(key).convertedTo(.RGBA8)
            let pixels   = window.app().renderer.readTexturePixels(entry.texture, .RGBA8)
            Swag.assert(entry.texture.width == 37 and entry.texture.height == 53)
            Swag.assert(Slice.equals(pixels.toSlice(), expected.pixels.toSlice()))
        }
    }

    // Pump normal events until the stage has both its expected state and completed native pixels.
    #[Swag.Propagate]
    mtd waitFor(window: *ViewerWindow, stage: string, ready: func||()->bool) fail
    {
        Console.println("Swag Scope smoke Explorer: ", stage)
        var stageWatch: Time.Stopwatch
        stageWatch.start()
        while true
        {
            window.app().runFrame()
            if ready() and Testing.verifyNativePresentation(unwrap window.surface) do
                return
            if stageWatch.elapsedMilliseconds() > 10_000 or .watch.elapsedMilliseconds() > 40_000
            {
                if window.explorer
                {
                    let explorer = window.explorer
                    Console.println("exploring=",
                                    window.isExploring(),
                                    " listing=",
                                    explorer.load.started,
                                    " entries=",
                                    explorer.entries.count,
                                    " shown=",
                                    explorer.shown.count,
                                    " workers=",
                                    explorer.previews.count,
                                    " path=",
                                    explorer.listing.path)
                    for &preview in explorer.previews do
                        Console.println("preview running=", preview.started, " path=", preview.path, " error=", preview.error)
                    let range = explorer.grid.visibleRange()
                    Console.println("visible=", range.first, "..", range.end)
                    for row in range.first until Math.min(range.end, explorer.shown.count)
                    {
                        let entry = &explorer.entries[explorer.shown[row]]
                        Console.println("tile=", entry.name, " attempted=", entry.attempted, " texture=", entry.texture.isValid())
                    }
                }

                fail Errors.InvalidFormatError{Errors.mkString(Format.toString("Explorer stage '%' exceeded its deadline", stage))}
            }

            Threading.Thread.sleep(10'ms)
        }
    }

    mtd waitForLibrary(window: *ViewerWindow, stage, folder: string) fail
    {
        let ready = func|window, folder, count = me.entryCount|()->bool
        {
            let explorer = window.explorer
            if not window.isExploring() or
               not explorer or
               explorer.load.started or
               explorer.listing.path != folder or
               explorer.shown.count != count do
                return false
            if explorer.isThumbnailView()
            {
                let range = explorer.grid.visibleRange()
                if range.end <= range.first do
                    return false
                for row in range.first until range.end where
                    not explorer.entries[explorer.shown[row]].texture.isValid() do
                    return false
            }

            return true
        }

        try .waitFor(window, stage, ready)
    }

    mtd opDrop()
    {
        if not .root.isEmpty() do
            catch Directory.delete(.root, recurse: true)
    }
}

// Browse a real library larger than the viewport, view a film, and return while work is pending.
// The explicit integration tag keeps native windows out of ordinary headless application tests.
#[Swag.TestTag("integration.application.smoke")]
#test
{
    var library: SmokeLibrary
    expect library.create()
    let films    = Path.combine(library.root, "Films")
    let pictures = Path.combine(library.root, "Pictures")
    var app: Application
    app.setAppIcon(expect Image.decode(".png", AppIcon))
    app.setStatePath(Path.combine(library.root, "settings.scc"))
    registerAppStrings(&app.resources)
    let surface = expect app.createSurface(40, 40, 1100, 790, surfaceId: "scope-explorer-smoke")
    surface.setTitle(ProductName)
    let window = ViewerWindow.create(surface.wnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.onlineMusic  = false
    expect library.seedPosters(window, films)
    surface.show()

    window.openExplorer(films)
    expect library.waitForLibrary(window, "open films", films)
    let explorer = unwrap window.explorer

    expect library.verifyPosters(window)
    for 2
    {
        explorer.setArtworkSource(.Local)
        expect library.waitForLibrary(window, "local video frames", films)
        for &entry in explorer.entries where entry.texture.isValid() do
            Swag.assert(entry.texture.width > entry.texture.height)
        explorer.setArtworkSource(.Online)
        expect library.waitForLibrary(window, "cached online posters", films)
        expect library.verifyPosters(window)
    }

    explorer.forceRefresh()
    expect library.waitForLibrary(window, "refresh video frames", films)

    explorer.setMode(.Details)
    expect library.waitForLibrary(window, "details", films)
    Swag.assert(explorer.list.isLocallyVisible())
    explorer.setMode(.Large)
    explorer.forceBoard(true, .Posters)
    expect library.waitForLibrary(window, "posters", films)
    explorer.setKindFilter(.Videos)
    expect library.waitForLibrary(window, "filter films", films)

    var selectedFile = String.from(explorer.entries[explorer.shown[0]].path)
    explorer.activate(explorer.shown[0])
    let filmReady = func|window, &selectedFile|()->bool
    {
        if window.currentFile != selectedFile or
           window.currentView == null or
           window.activeChoiceIndex >= window.instances.count do
            return false
        let instance = &window.instances[window.activeChoiceIndex]
        Swag.assert(instance.failureReason.isEmpty())
        return not instance.isLoading or not instance.isLoading()
    }

    expect library.waitFor(window, "open film", filmReady)
    window.closeFile()
    expect library.waitForLibrary(window, "return to library", films)

    explorer.navigate(films)
    explorer.navigate(pictures)
    explorer.setKindFilter(.All)
    explorer.forceBoard(false)
    expect library.waitForLibrary(window, "replace pending folder", pictures)
    explorer.forceRefresh()
    expect library.waitForLibrary(window, "refresh pictures", pictures)

    surface.setPosition({40, 40, 1193, 823})
    expect library.waitForLibrary(window, "resize to odd dimensions", pictures)
    surface.setPosition({40, 40, 1100, 790})
    expect library.waitForLibrary(window, "restore dimensions", pictures)
    app.setAppearance(.Light)
    expect library.waitForLibrary(window, "light theme", pictures)
    app.setAppearance(.Dark)
    expect library.waitForLibrary(window, "dark theme", pictures)
}

// Revisit a library beyond the GPU texture budget using persisted thumbnails. Codec startup is
// covered by the journey above; this case isolates upload, eviction and presentation under churn.
#[Swag.TestTag("integration.application.smoke")]
#test
{
    var library = SmokeLibrary{entryCount: 160}
    expect library.create()
    let films = Path.combine(library.root, "Films")
    var app: Application
    app.setAppIcon(expect Image.decode(".png", AppIcon))
    app.setStatePath(Path.combine(library.root, "settings.scc"))
    registerAppStrings(&app.resources)
    let surface = expect app.createSurface(40, 40, 1100, 790, surfaceId: "scope-preview-cache-smoke")
    let window  = ViewerWindow.create(surface.wnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.onlineMusic  = false
    expect library.seedPosters(window, films)

    surface.show()
    window.openExplorer(films)
    expect library.waitForLibrary(window, "open cached films", films)
    let explorer = unwrap window.explorer

    // Exercise the 128-texture cache with normal scrolling, then revisit evicted previews.
    explorer.setMode(.Medium)
    let page = explorer.scroll.view.position.height * 0.8
    let last = explorer.scroll.scrollSize.y - explorer.scroll.view.position.height
    var top  = page
    while top < last
    {
        explorer.scroll.setScrollPos(0, top)
        expect library.waitForLibrary(window, "scroll film library", films)
        expect library.verifyPosters(window)
        top += page
    }

    explorer.scroll.setScrollPos(0, last)
    expect library.waitForLibrary(window, "reach end of film library", films)
    Swag.assert(explorer.cached.count == 128)
    explorer.scroll.setScrollPos(0, 0)
    expect library.waitForLibrary(window, "reload evicted film previews", films)
    Swag.assert(explorer.cached.count == 128)

    explorer.grid.select(explorer.shown.count - 1)
    expect library.waitForLibrary(window, "scroll to last film", films)
    Swag.assert(explorer.grid.visibleRange().first > 0)
    Swag.assert(explorer.selected == explorer.shown[explorer.shown.count - 1])
}
