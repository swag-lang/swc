#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel, Viewers

// Exercise the history-to-player transition with native presentation, real playback time and
// repeated retirement. A loaded first frame alone does not cover later control invalidations.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var library: MediaLibraryFixture
    expect library.create()
    let file = expect videoPreviewFileAt(Path.combine(library.root, "Recent film.y4m"), 40)
    var app: Application
    app.setAppIcon(expect Image.decode(".png", AppIcon))
    app.setStatePath(Path.combine(library.root, "recent-settings.scc"))
    registerAppStrings(&app.resources)
    let surface = expect app.createSurface(40, 40, 1100, 790, surfaceId: "scope-recent-video")
    surface.setTitle(ProductName)
    let window = ViewerWindow.create(surface.wnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.onlineMusic  = false
    surface.show()
    window.recent.clear()
    window.recentOpened.clear()
    window.recent.add(file)
    window.recentOpened.add(Time.Timestamp.now().ticks)
    window.home.refresh()

    for 2
    {
        Swag.require(window.home.isLocallyVisible() and window.home.rows.count == 1)
        window.home.chosen = 0
        var activate   = KeyEvent{kind: .Pressed, key: .Return}
        let home: IWnd = window.home
        home.onKeyEvent(&activate)

        let played = func|window|()->bool
        {
            if window.currentView == null or window.activeChoiceIndex >= window.instances.count do
                return false
            let instance = &window.instances[window.activeChoiceIndex]
            Swag.require(instance.failureReason.isEmpty())
            Swag.require(window.choices[window.activeChoiceIndex].key == "video")
            let view = assume cast(*Film.Panel, instance.view)
            Swag.require(not view.hasFailure)
            return view.hasFrame and view.playing and view.frameIndex >= 18
        }

        expect library.waitFor(window, "play recent film beyond the first frame", played)
        window.closeFile()
        let closed = func|window|()->bool { return window.home.isLocallyVisible() and window.currentView == null }
        expect library.waitFor(window, "return to history", closed)
    }
}
