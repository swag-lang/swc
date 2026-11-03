#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Minimizing a normal surface preserves its latest bounds and defers repaints until restoration.
#test
{
    var cpu: RenderCpu
    var app: Application
    app.setRenderer(&cpu)

    let surface = expect app.createSurface(40, 40, 320, 180)
    surface.show()

    for bounds in [Math.Rectangle{40, 40, 320, 180}, Math.Rectangle{60, 50, 400, 240}]
    {
        surface.setPosition(bounds)
        surface.requestMinimize()
        app.runFrame()
        surface.invalidate()
        app.runFrame()
        Swag.require(surface.isMinimized and surface.isDirty)
        Swag.require(surface.position == bounds)

        surface.requestRestore()
        app.runFrame()
        Swag.require(not surface.isMinimized and not surface.isMaximized)
        Swag.require(surface.position == bounds)
        Swag.require(not surface.isDirty)
    }
}

// Maximizing, resizing, and restoring a CPU surface keeps its target and layout in sync without
// creating a native window. The platform assigns maximized bounds only when a HWND exists.
#test
{
    var cpu: RenderCpu
    var app: Application
    app.setRenderer(&cpu)

    let surface = expect app.createSurface(40, 40, 320, 180)
    Swag.require(not surface.hWnd)
    surface.show()
    let normal = surface.position

    surface.showMaximized()
    Swag.require(surface.isMaximized and not surface.isMinimized)
    surface.setPosition({40, 40, 640, 400})
    surface.paint()
    Swag.require(surface.rc.width == 640 and surface.rc.height == 400)
    Swag.require(surface.rt.colorBuffer.width >= surface.rc.width and surface.rt.colorBuffer.height >= surface.rc.height)

    surface.showNormal()
    surface.paint()
    Swag.require(not surface.isMaximized and not surface.isMinimized)
    Swag.require(surface.position == normal)
    Swag.require(surface.rc.width == normal.width and surface.rc.height == normal.height)
    Swag.require(not surface.hWnd)
}

// The application command path restores a minimized maximized surface to maximized state, and a
// minimized normal surface to normal state. Explicit showNormal also leaves both states at once.
#test
{
    var cpu: RenderCpu
    var app: Application
    app.setRenderer(&cpu)

    let surface = expect app.createSurface(40, 40, 640, 400)
    Swag.require(not surface.hWnd)
    surface.show()

    let normal = surface.position
    surface.showMaximized()
    let maximized = surface.position

    surface.requestMinimize()
    app.runFrame()
    Swag.require(surface.isMinimized and surface.isMaximized)
    Swag.require(surface.position == maximized)

    surface.requestRestore()
    app.runFrame()
    Swag.require(not surface.isMinimized and surface.isMaximized)
    Swag.require(not surface.isHidden)
    Swag.require(surface.position == maximized)

    surface.showNormal()
    surface.requestMinimize()
    app.runFrame()
    surface.requestRestore()
    app.runFrame()
    Swag.require(not surface.isMinimized and not surface.isMaximized)
    Swag.require(not surface.isHidden)
    Swag.require(surface.position == normal)

    surface.showMaximized()
    surface.requestMinimize()
    app.runFrame()
    surface.showNormal()
    Swag.require(not surface.isMinimized and not surface.isMaximized)
    Swag.require(not surface.isHidden)
    Swag.require(surface.position == normal)
    Swag.require(not surface.hWnd)
}
