#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Win32, Ogl

func inspectPlacementFrame(surface: *Surface)
{
    if Env.variable("SWAG_SCOPE_PLACEMENT_PROBE").isEmpty() do
        return
    let renderer = glGetString(GL_RENDERER)
    if renderer do
        Console.println("Renderer: ", cast(string, cast(const cstring, renderer)))
    var watch: Time.Stopwatch
    watch.restart()
    glFinish()
    Console.println("GPU completion (us): ", watch.elapsedMicroseconds())
    let rc = surface.renderingContext()
    var viewport: [4] GLint
    glGetIntegerv(GL_VIEWPORT, &viewport[0])
    Console.println("Viewport: ", viewport[2], " x ", viewport[3], "; client: ", rc.width, " x ", rc.height)
    var front: u32
    glReadBuffer(GL_FRONT)
    glReadPixels(rc.width - 40, rc.height / 2, 1, 1, GL_BGRA, GL_UNSIGNED_BYTE, cast([*] u8, &front))
    glReadBuffer(GL_BACK)
    var frame = surface.app.renderer.readRenderTarget(&surface.rt, 0, 0, rc.width, rc.height)
    Console.println("Right-edge pixels, front / target: ", front, " / ", frame.pixelColor(rc.width - 40, rc.height / 2).argb)
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
    let surface = expect app.createSurface(80, 50, ViewerMinWidth, 680, surfaceId: "scope-placement-test")
    app.theme.setSwagDark()
    app.notifyThemeChanged()
    let window   = ViewerWindow.create(surface.wnd, createViewerPluginRegistry())
    var fileName = Env.variable("SWAG_SCOPE_PLACEMENT_DOCUMENT")
    if fileName.isEmpty() do
        fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/markdown.images.md")
    window.openFile(fileName.toString(), remember: false)
    surface.show()

    var watch: Time.Stopwatch
    watch.restart()
    while watch.elapsedMicroseconds() < 10_000_000
    {
        app.runFrame()
        if window.currentView is Markdown.View and not assume cast(*Markdown.View, window.currentView).isLoading() do
            break
        Threading.Thread.sleep(1'ms)
    }

    Swag.assert(window.currentView is Markdown.View)
    Swag.assert(not assume cast(*Markdown.View, window.currentView).isLoading())
    let normal = surface.position
    Swag.assert(not surface.isMaximized)
    observeViewerPlacement(&app)

    for fromMaximized in [false, true]
    {
        if fromMaximized
        {
            surface.showMaximized()
            observeViewerPlacement(&app)
        }

        let previous = surface.position
        watch.restart()
        window.setFullScreen(true)
        Console.println("Full-screen entry (us): ", watch.elapsedMicroseconds())
        inspectPlacementFrame(surface)
        Swag.assert(window.fullScreen and not surface.isMaximized)
        Swag.assert(surface.position == Env.monitorForRectangle(normal).physicalBounds)
        Swag.assert(IsWindowVisible(surface.win32Handle()))
        observeViewerPlacement(&app)

        watch.restart()
        window.setFullScreen(false)
        Console.println("Full-screen exit (us): ", watch.elapsedMicroseconds())
        inspectPlacementFrame(surface)
        Swag.assert(not window.fullScreen and surface.isMaximized == fromMaximized)
        Swag.assert(surface.position == previous)
        Swag.assert(IsWindowVisible(surface.win32Handle()))
        observeViewerPlacement(&app)
        surface.showNormal()
        Swag.assert(surface.position == normal)
        observeViewerPlacement(&app)
    }
}
