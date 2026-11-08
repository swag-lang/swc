#global if #os == Swag.TargetOs.Linux
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// X11 reports the native origin; full-window pixel comparison also verifies its size.
func waitForViewerNativeBounds(app: *Application, surface: *Surface, expected: Math.Rectangle) fail
{
    var watch: Time.Stopwatch
    watch.start()
    while watch.elapsedMilliseconds() < 10_000
    {
        app.runFrame()
        var origin = Math.Point{0, 0}
        surface.surfaceToScreen(&origin)
        if surface.position == expected and
           origin == {expected.x, expected.y} and
           surface.renderingContext().width == cast(s32, expected.width) and
           surface.renderingContext().height == cast(s32, expected.height) and
           try Testing.verifyNativePresentation(surface) do
            return
        Threading.Thread.sleep(10'ms)
    }

    var origin = Math.Point{0, 0}
    surface.surfaceToScreen(&origin)
    Console.println("Requested bounds: ", expected.x, ",", expected.y, " ", expected.width, "x", expected.height,
                    "; actual bounds: ", surface.position.x, ",", surface.position.y, " ",
                    surface.position.width, "x", surface.position.height, "; native origin: ", origin.x, ",", origin.y,
                    "; render context: ", surface.renderingContext().width, "x", surface.renderingContext().height,
                    "; pixels match: ", try Testing.verifyNativePresentation(surface))
    fail Errors.InvalidFormatError{"Swag Scope did not present the requested native X11 bounds"}
}

// Repeated full-screen transitions must restore normal placement and document insets.
#[Swag.TestTag("integration.application.placement")]
#test
{
    Swag.require(Env.variable("SWAG_TEST_ISOLATED_X11") == "1")
    var app: Application
    registerAppStrings(&app.resources)
    let surface = expect app.createSurface(80, 50, ViewerWindow.MinWidth, 680, surfaceId: "scope-linux-placement-test")
    let window  = ViewerWindow.create(surface.wnd, createViewerPluginRegistry())
    window.openFile(Path.combine(testSourceRoot(#curlocation), "datas/markdown.images.md"), remember: false)
    surface.show()

    var watch: Time.Stopwatch
    watch.start()
    while watch.elapsedMilliseconds() < 10_000
    {
        app.runFrame()
        if window.currentView is Markdown.View as view where not view.isLoading() do
            break
        Threading.Thread.sleep(10'ms)
    }
    Swag.require(not expect cast(*Markdown.View, window.currentView).isLoading())
    let normal = surface.position
    let monitor = Env.monitorForRectangle(normal).physicalBounds
    expect waitForViewerNativeBounds(&app, surface, normal)

    for 3
    {
        window.sendCommandEvent(ViewerCommands.FullScreen)
        Swag.require(window.fullScreen and not surface.isMaximized)
        expect waitForViewerNativeBounds(&app, surface, monitor)
        Swag.require(window.currentView!.padding.y == 0 and window.documentHost.padding.y == 0)

        window.sendCommandEvent(ViewerCommands.FullScreen)
        Swag.require(not window.fullScreen and not surface.isMaximized)
        expect waitForViewerNativeBounds(&app, surface, normal)
        Swag.require(window.currentView.padding.y == window.stripInset())
    }
}
