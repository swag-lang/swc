#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// Browse a real library larger than the viewport, view a film, and return while work is pending.
// The explicit integration tag keeps native windows out of ordinary headless application tests.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var library: MediaLibraryFixture
    expect library.create()
    let films    = Path.combine(library.root, "Films")
    let pictures = Path.combine(library.root, "Pictures")
    var app: Application
    app.setAppIcon(expect Image.decode(".png", AppIcon))
    app.setStatePath(Path.combine(library.root, "settings.scc"))
    registerAppStrings(&app.resources)
    let surface = expect app.createSurface(40, 40, 1100, 790, surfaceId: "scope-explorer-journey")
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
            Swag.require(entry.texture.width > entry.texture.height)
        explorer.setArtworkSource(.Online)
        expect library.waitForLibrary(window, "cached online posters", films)
        expect library.verifyPosters(window)
    }

    explorer.forceRefresh()
    expect library.waitForLibrary(window, "refresh video frames", films)

    explorer.setMode(.Details)
    expect library.waitForLibrary(window, "details", films)
    Swag.require(explorer.list.isLocallyVisible())
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
        Swag.require(instance.failureReason.isEmpty())
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
