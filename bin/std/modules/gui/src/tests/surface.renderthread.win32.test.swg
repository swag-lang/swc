#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Win32, Ogl

// The window's rendering context must stay on its owner thread. Delegating synchronous WGL
// calls to another thread lets drawable reallocation overlap USER32's geometry transaction;
// the driver can then stall for seconds even when the surface contains no controls.
#[Swag.TestTag("gpu")]
#test
{
    var app: Application
    let surface = (expect app.createSurface(40, 40, 320, 180, surfaceId: "gui-render-owner-test"))!
    let context = Ogl.wglGetCurrentContext()
    Swag.assert(context != null, "the window owner must own the default OpenGL context")

    var processId: u32
    let owner = GetWindowThreadProcessId(surface.win32Handle(), &processId)
    Swag.assert(owner == GetCurrentThreadId())

    for step in 4
    {
        surface.setPosition({40, 40, cast(f32) (320 + step * 2), 180})
        surface.paint()
        Swag.assert(Ogl.wglGetCurrentContext() == context)
        Swag.assert(surface.rt.colorBuffer.isValid())
    }
}

// Discrete placements finish with a target and client rectangle of the same size. In particular,
// preparing the large maximized frame before USER32 changes the window must not leave the surface
// dirty or publish the normal-sized target through the maximized drawable.
#[Swag.TestTag("gpu")]
#test
{
    var app: Application
    let surface = (expect app.createSurface(40, 40, 640, 400, surfaceId: "gui-discrete-placement-test"))!
    surface.show()

    let normal = surface.position
    surface.showMaximized()

    var client: RECT
    Swag.assert(GetClientRect(surface.win32Handle(), &client))
    Swag.assert(surface.isMaximized)
    Swag.assert(surface.rc.width == client.right and surface.rc.height == client.bottom)
    Swag.assert(surface.rt.colorBuffer.width >= surface.rc.width and surface.rt.colorBuffer.height >= surface.rc.height)
    Swag.assert(not surface.preparedFrame and not surface.isDirty)

    surface.showNormal()
    Swag.assert(GetClientRect(surface.win32Handle(), &client))
    Swag.assert(not surface.isMaximized)
    Swag.assert(surface.position == normal)
    Swag.assert(surface.rc.width == client.right and surface.rc.height == client.bottom)
    Swag.assert(not surface.preparedFrame and not surface.isDirty)
}
