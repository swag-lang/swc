#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// Owns an offline library and the deadline shared by its user journey.
struct SmokeLibrary
{
    root:  String
    watch: Time.Stopwatch
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
        let video = File.readAllBytes(Path.combine(fixtures, "glint-aac-mjpeg.mp4"))
        let image = File.readAllBytes(Path.combine(fixtures, "appicon.png"))
        for index in 160
        {
            discard File.writeAllBytes(Path.combine(films, Format.toString("Film %{03} (2024).mp4", index)), video.toSlice())
            discard File.writeAllBytes(Path.combine(pictures, Format.toString("Picture %{03}.png", index)), image.toSlice())
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
            if stageWatch.elapsedMilliseconds() > 10_000 or .watch.elapsedMilliseconds() > 35_000
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
                }

                fail Errors.InvalidFormatError{Errors.mkString(Format.toString("Explorer stage '%' exceeded its deadline", stage))}
            }

            Threading.Thread.sleep(10'ms)
        }
    }

    mtd waitForLibrary(window: *ViewerWindow, stage, folder: string) fail
    {
        let ready = func|window, folder|()->bool
        {
            let explorer = window.explorer
            if not window.isExploring() or
               not explorer or
               explorer.load.started or
               explorer.listing.path != folder or
               explorer.shown.count != 160 do
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
    surface.show()

    window.openExplorer(films)
    expect library.waitForLibrary(window, "open films", films)
    let explorer = unwrap window.explorer
    explorer.grid.select(explorer.shown.count - 1)
    expect library.waitForLibrary(window, "scroll to last film", films)
    Swag.assert(explorer.grid.visibleRange().first > 0)
    Swag.assert(explorer.selected == explorer.shown[explorer.shown.count - 1])

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
