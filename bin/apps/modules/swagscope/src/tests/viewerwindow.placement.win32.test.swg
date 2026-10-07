#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Win32

// Exercise the real viewer and compositor together; a headless host cannot observe a native
// restore between maximized and full-screen placement or an overlay covering stale WGL pixels.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    registerAppStrings(&app.resources)
    let surface = expect app.createSurface(80, 50, ViewerMinWidth, 680, surfaceId: "scope-placement-test")!
    let window  = ViewerWindow.create(surface.wnd, createViewerPluginRegistry())
    surface.show()
    let normal = surface.position

    for fromMaximized in [false, true]
    {
        if fromMaximized do
            surface.showMaximized()
        let previous = surface.position
        window.setFullScreen(true)
        Swag.assert(window.fullScreen and not surface.isMaximized)
        Swag.assert(surface.position == Env.monitorForRectangle(normal).physicalBounds)
        Swag.assert(IsWindowVisible(surface.win32Handle()))
        app.runFrame()

        window.setFullScreen(false)
        Swag.assert(not window.fullScreen and surface.isMaximized == fromMaximized)
        Swag.assert(surface.position == previous)
        Swag.assert(IsWindowVisible(surface.win32Handle()))
        app.runFrame()
        surface.showNormal()
        Swag.assert(surface.position == normal)
    }
}
