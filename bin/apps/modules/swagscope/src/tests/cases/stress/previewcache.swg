#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private
using Core, Gui, Pixel

#[Swag.TestTag("integration.application.stress")]
#test
{
    var library = MediaLibraryFixture{entryCount: 160}
    expect library.create()
    let films = Path.combine(library.root, "Films")
    var app: Application
    app.setAppIcon(expect Image.decode(".png", AppIcon))
    app.setStatePath(Path.combine(library.root, "settings.scc"))
    registerAppStrings(&app.resources)
    let surface = expect app.createSurface(40, 40, 1100, 790, surfaceId: "scope-preview-cache-stress")
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
