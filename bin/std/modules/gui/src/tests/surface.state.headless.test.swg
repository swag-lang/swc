#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Maximizing, resizing, and restoring a CPU surface keeps its target and layout in sync without
// creating a native window. The platform assigns maximized bounds only when a HWND exists.
#test
{
    var cpu: RenderCpu
    var app: Application
    app.setRenderer(&cpu)

    let surface = expect app.createSurface(40, 40, 320, 180)!
    Swag.assert(not surface.hWnd)
    surface.show()
    let normal = surface.position

    surface.showMaximized()
    Swag.assert(surface.isMaximized and not surface.isMinimized)
    surface.setPosition({40, 40, 640, 400})
    surface.paint()
    Swag.assert(surface.rc.width == 640 and surface.rc.height == 400)
    Swag.assert(surface.rt.colorBuffer.width >= surface.rc.width and surface.rt.colorBuffer.height >= surface.rc.height)

    surface.showNormal()
    surface.paint()
    Swag.assert(not surface.isMaximized and not surface.isMinimized)
    Swag.assert(surface.position == normal)
    Swag.assert(surface.rc.width == normal.width and surface.rc.height == normal.height)
    Swag.assert(not surface.hWnd)
}

// The application command path restores a minimized maximized surface to maximized state, and a
// minimized normal surface to normal state. Explicit showNormal also leaves both states at once.
#test
{
    var cpu: RenderCpu
    var app: Application
    app.setRenderer(&cpu)

    let surface = expect app.createSurface(40, 40, 640, 400)!
    Swag.assert(not surface.hWnd)
    surface.show()

    let normal = surface.position
    surface.showMaximized()
    let maximized = surface.position

    surface.requestMinimize()
    app.runFrame()
    Swag.assert(surface.isMinimized and surface.isMaximized)
    Swag.assert(surface.position == maximized)

    surface.requestRestore()
    app.runFrame()
    Swag.assert(not surface.isMinimized and surface.isMaximized)
    Swag.assert(not surface.isHidden)
    Swag.assert(surface.position == maximized)

    surface.showNormal()
    surface.requestMinimize()
    app.runFrame()
    surface.requestRestore()
    app.runFrame()
    Swag.assert(not surface.isMinimized and not surface.isMaximized)
    Swag.assert(not surface.isHidden)
    Swag.assert(surface.position == normal)

    surface.showMaximized()
    surface.requestMinimize()
    app.runFrame()
    surface.showNormal()
    Swag.assert(not surface.isMinimized and not surface.isMaximized)
    Swag.assert(not surface.isHidden)
    Swag.assert(surface.position == normal)
    Swag.assert(not surface.hWnd)
}
