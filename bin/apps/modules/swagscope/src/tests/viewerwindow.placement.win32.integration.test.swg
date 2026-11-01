#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Win32

// Logical placement and the native HWND must agree after every presentation transition.
func assertViewerNativeBounds(surface: *Surface)
{
    var bounds: RECT
    let measured = GetWindowRect(surface.win32Handle(), &bounds)
    Swag.assert(measured)
    Swag.assert(bounds.left == cast(s32, surface.position.x) and
                bounds.top == cast(s32, surface.position.y) and
                bounds.right == cast(s32, surface.position.right()) and
                bounds.bottom == cast(s32, surface.position.bottom()))
}

// Optional capture pacing belongs to the observer, never to the placement implementation.
func observeViewerPlacement(app: *Application)
{
    app.runFrame()
    if Env.variable("SWAG_SCOPE_PLACEMENT_CAPTURE").isEmpty() do
        return
    var watch: Time.Stopwatch
    watch.restart()
    while watch.elapsedMicroseconds() < 500_000
    {
        app.runFrame()
        Threading.Thread.sleep(1'ms)
    }
}

// Set SWAG_SCOPE_PLACEMENT_DOCUMENT to exercise a local document instead of the shipped fixture.
// Calls target this viewer directly, so another application's focus cannot redirect the test.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    registerAppStrings(&app.resources)
    let surface = expect app.createSurface(80, 50, ViewerWindow.MinWidth, 680, surfaceId: "scope-placement-test")
    app.theme.setDark()
    app.notifyThemeChanged()
    let window   = ViewerWindow.create(surface.wnd, createViewerPluginRegistry())
    var fileName = Env.variable("SWAG_SCOPE_PLACEMENT_DOCUMENT")
    if fileName.isEmpty() do
        fileName = Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/markdown.images.md")
    window.openFile(fileName, remember: false)
    surface.show()

    var watch: Time.Stopwatch
    watch.restart()
    while watch.elapsedMicroseconds() < 10_000_000
    {
        app.runFrame()
        if window.currentView is Markdown.View as view where not view.isLoading() do
            break
        Threading.Thread.sleep(1'ms)
    }

    Swag.assert(not expect cast(*Markdown.View, window.currentView).isLoading())
    let normal = surface.position
    Swag.assert(not surface.isMaximized)
    observeViewerPlacement(&app)

    for fromMaximized in [false, true, false, true, false, true]
    {
        if fromMaximized
        {
            surface.showMaximized()
            observeViewerPlacement(&app)
        }

        let previous = surface.position
        watch.restart()
        window.sendCommandEvent(ViewerCommands.FullScreen)
        Console.println("Full-screen entry (us): ", watch.elapsedMicroseconds())
        Swag.assert(window.fullScreen and not surface.isMaximized)
        Swag.assert(surface.position == Env.monitorForRectangle(normal).physicalBounds)
        Swag.assert(IsWindowVisible(surface.win32Handle()))
        observeViewerPlacement(&app)
        assertViewerNativeBounds(surface)
        Swag.assert(window.currentView!.padding.y == 0 and window.documentHost.padding.y == 0)

        watch.restart()
        window.sendCommandEvent(ViewerCommands.FullScreen)
        Console.println("Full-screen exit (us): ", watch.elapsedMicroseconds())
        Swag.assert(not window.fullScreen and surface.isMaximized == fromMaximized)
        Swag.assert(surface.position == previous)
        Swag.assert(IsWindowVisible(surface.win32Handle()))
        observeViewerPlacement(&app)
        assertViewerNativeBounds(surface)
        Swag.assert(window.currentView.padding.y == window.stripInset())
        surface.showNormal()
        Swag.assert(surface.position == normal)
        observeViewerPlacement(&app)
    }
}
